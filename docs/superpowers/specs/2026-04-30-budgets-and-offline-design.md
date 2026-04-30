# Design — Project budgets (#4) + Offline-first writes (#3)

**Date:** 2026-04-30
**Status:** Approved (per chat brainstorming)
**Scope:** Two new features for `SuiviDepenses-Supabase`. No backend services; stays inside the existing "static PWA + Supabase" architecture.

## Goals

1. **Project budgets + burn-rate dashboard** — let admins set a budget per project, show spent-vs-budget on every screen with a coloured progress indicator. Informational only; budgets do not block writes.
2. **Offline-first writes** — let supervisors record expenses and edits while disconnected (basements, dead-zone sites). Mutations queue locally and sync FIFO on reconnect with optimistic UI.

## Build order

**#4 first, then #3.** Reasoning: #4 adds two columns to `projects`; #3 adds one column to `expenses` and a non-trivial mutation router. Shipping #4 first locks the schema before queue replay logic depends on it. Both features can be merged independently.

---

## Feature #4 — Project budgets + burn-rate dashboard

### Schema

New idempotent migration `supabase/migrations/20260430000005_project_budgets.sql`:

```sql
-- 1. Budget columns
alter table public.projects
    add column if not exists budget_amount numeric(14,2),
    add column if not exists budget_alert_pct int not null default 80
        check (budget_alert_pct between 0 and 100);

-- 2. Aggregation RPC — returns one row per visible project with the
-- TRUE spent total computed across ALL expenses on the project (not
-- just the caller's own rows, which is what RLS would otherwise expose).
create or replace function public.get_project_summary()
returns table (
    project_id      uuid,
    name            text,
    budget_amount   numeric(14,2),
    budget_alert_pct int,
    spent           numeric(14,2),
    expense_count   int
)
language sql stable security definer set search_path = public as $$
    select
        p.id,
        p.name,
        p.budget_amount,
        p.budget_alert_pct,
        coalesce(sum(e.amount), 0)::numeric(14,2) as spent,
        count(e.*)::int as expense_count
    from public.projects p
    left join public.expenses e on e.project_id = p.id
    where
        public.is_admin(auth.uid())
        or p.id = (select project_id from public.profiles where id = auth.uid())
    group by p.id, p.name, p.budget_amount, p.budget_alert_pct;
$$;

-- 3. Live updates: publish projects changes too (was only expenses before)
alter publication supabase_realtime add table public.projects;
```

- `budget_amount` is **nullable**. Null = no budget set; UI hides the card.
- `budget_alert_pct` defaults to 80 (amber threshold).
- **No currency column.** App stays currency-agnostic (no currency on `expenses` either).
- The RPC is `SECURITY DEFINER` so it can `SUM(amount)` across all expenses on a project the caller is permitted to see, even though direct `select` on `expenses` is RLS-filtered to just the caller's own rows. Authorization is enforced inside the function via `is_admin(auth.uid())` + the caller's `project_id` — same pattern as the existing `_admin_helpers.sql`.

### RLS

- `projects` columns inherit existing policies (`projects_update_admin`, `projects_select`). No changes.
- `get_project_summary()` is callable by all `authenticated` users; the function body returns only the rows that user is allowed to see. Grant: `grant execute on function public.get_project_summary() to authenticated;` (added to the migration).

### Data flow (online)

1. On login (`loadCurrentUser`), the existing profile select is extended to embed budget fields:
   ```js
   .select('id, full_name, is_admin, project_id, projects(name, budget_amount, budget_alert_pct)')
   ```
   Single round-trip, no schema cost — PostgREST embedding handles it.
2. Immediately after, `supabase.rpc('get_project_summary')` returns the spent totals. For supervisors, this is one row; for admins, all rows.
3. Subscribe a **second realtime channel** on `public.projects` to catch budget edits. On any change, refetch `get_project_summary` (debounced 250ms — admin might bulk-edit several projects).
4. The existing `expenses` realtime channel handler already triggers a UI render on every INSERT/UPDATE/DELETE. Extend the handler to **also refetch `get_project_summary`** (debounced) so the spent total stays accurate when other supervisors' rows change (which RLS hides from the local `expenses` cache).

### Frontend (`index.html`)

**Stat cards row** — add a 5th card "Budget" beside the existing four:

- Hidden when the visible project has `budget_amount = null`.
- Shows: `spent / budget` on one line; horizontal progress bar below.
- Bar colour:
  - green if `spent / budget < alert_pct/100`
  - amber if `alert_pct/100 ≤ spent / budget < 1.0`
  - red if `spent / budget ≥ 1.0`
- For an **admin viewing all projects**: summed budget vs summed spent across non-null-budget projects.

**Admin panel → Projects section** — each project row gets two extra inputs + Save:

- `Budget` (numeric, blank = null) and `Alert %` (int 0–100).
- Save = `supabase.from('projects').update({ budget_amount, budget_alert_pct }).eq('id', pid)` — RLS gates it. The realtime publication on `projects` will fan the change out to every live supervisor on that project.

### Offline behavior of the budget card

When the network is down, the RPC is unavailable. The card uses **last-known server values + the user's own optimistic offline additions** added in:

- `displayed_spent = last_summary.spent + sum(offline_pending_inserts.amount) - sum(offline_pending_deletes.amount)`
- The card gains a small `stale` indicator (e.g. dashed border, tooltip "Données en attente de synchronisation").

This undercounts other supervisors' offline activity (which we can't know about), but it accurately reflects the user's own offline impact. Once any op replays successfully, refetch the RPC and clear `stale`.

### i18n

Add to **both** `dict.en` and `dict.fr` (mandatory dual-update per CLAUDE.md):

```
budgetCardLabel       "Budget"           "Budget"
budgetSpentOf         "{spent} of {budget}"   "{spent} sur {budget}"
budgetOver            "Over budget"      "Dépassement"
adminBudgetInput      "Budget"           "Budget"
adminAlertPct         "Alert at %"       "Alerte à %"
adminBudgetSave       "Save"             "Enregistrer"
```

### Out of scope (deferred)

- Per-category budgets.
- Time-bound budgets (monthly / quarterly).
- Email or push alerts.
- Hard enforcement (rejecting INSERTs past 100%) — explicitly chosen as informational only; over-budget recording is a legitimate workflow.

---

## Feature #3 — Offline-first writes

### Approach: write-through queue + optimistic UI

A small **mutation router** wraps every write the app does today:

1. **Try-direct-first.** Always attempt the Supabase call first.
2. If it succeeds → behaviour identical to today.
3. If it fails with a **network-level error** (no response / timeout / `TypeError: Failed to fetch`) OR `navigator.onLine === false` at call time → enqueue the op in IndexedDB and update the local `expenses` array optimistically. Show "Hors ligne (n en attente)".
4. If it fails with a **server-level error** (HTTP response with non-2xx, including RLS rejections, validation, 5xx) → do **NOT** queue. Surface the error inline as today; the user fixes it manually.

This keeps the queue scoped to true connectivity loss, not server bugs or auth problems. `navigator.onLine` is consulted as a hint but is not the source of truth — the actual fetch result is.

On reconnect (the `window.online` event fires, OR a previously-queued op succeeds, OR Supabase realtime channel emits a `SUBSCRIBED` state), drain the queue **FIFO**, one op at a time.

### Schema change

New idempotent migration `supabase/migrations/20260430000006_expense_client_id.sql`:

```sql
alter table public.expenses
    add column if not exists client_id uuid;

create unique index if not exists expenses_client_id_uidx
    on public.expenses(client_id) where client_id is not null;
```

`client_id` is set by the client at the moment of creation (UUID v4, generated in JS via `crypto.randomUUID()`). On replay, INSERTs use `on conflict (client_id) do nothing` so a network blip that lost the response (but the row was created) does not produce a duplicate.

UPDATEs and DELETEs identify rows by their server PK (`id`), not `client_id`. `client_id` is purely an INSERT-idempotency token.

### IndexedDB layout

DB name: `suividepenses_offline`. Single object store `pending_ops`:

```
{
  id:          autoIncrement int,
  op_type:     'insert' | 'update' | 'delete',
  client_id:   uuid,                // always present; copied to expenses.client_id on insert
  target_id:   uuid | null,         // server PK for update/delete; null for insert
  payload:     object | null,       // row data for insert/update; null for delete
  blob:        Blob | null,         // optional receipt for insert/update
  mime:        string | null,
  ext:         string | null,
  created_at:  ISO timestamp,
  attempts:    int,
  last_error:  string | null
}
```

**No standalone `upload_receipt` op.** The receipt is a property of the insert/update op, not a separate operation. The replay executor handles the multi-step sequence atomically:

```
For an insert with blob:
  1. INSERT expense (gets real `id`)
  2. If blob present: upload to receipts/<user_id>/<id>.<ext>
  3. UPDATE expenses SET receipt_path = ... WHERE id = ...

For an update with blob:
  1. (Optional) delete previous storage object if receipt_path is being replaced
  2. UPDATE expense fields
  3. Upload new blob, then UPDATE receipt_path
```

If step 2 or 3 fails after step 1 succeeded, retry on next reconnect (the row is in the DB; only the receipt is missing, which is recoverable on its own).

Single store keeps the queue model simple. Receipt blobs live inline; browsers comfortably store hundreds of MB in IDB.

**No library** — raw IndexedDB API. Matches the no-toolchain ethos. The wrapper is small (~80–100 lines).

### Optimistic UI

- An offline-created expense appears in the table **immediately**, faded (e.g. `opacity: 0.6`) with a 🕒 clock icon in a new "Sync" cell.
- On successful replay: the row settles (full opacity, real DB id replaces the temporary client-side id, clock icon disappears).
- On rejected replay (RLS, validation, etc.): the row turns red, clock becomes ⚠️, and an inline action `Échec — supprimer / réessayer` appears.
- The existing **En ligne / Hors ligne** pill in the header gains a counter when ops are queued: `Hors ligne (3 en attente)` / `Online (2 syncing)`.

### Conflict policy (kept dumb on purpose)

| Scenario | Resolution |
|---|---|
| Two offline users insert into the same project | Both rows land. Different `client_id`s, different PKs. No conflict. |
| Offline UPDATE of a row that someone else updated online in the meantime | Last-write-wins. My offline payload overwrites the server's later edit. |
| Offline DELETE of a row that someone else updated online | Delete still applies (RLS-permitting). Server-wins for delete-vs-update. |
| Offline INSERT, replayed twice (network blip lost the response but the row was created) | The unique index on `client_id` makes the second insert a no-op. |
| Offline INSERT/UPDATE that fails RLS on replay (user demoted, project unassigned) | Op is marked rejected in the queue, surfaced inline on the row, user can delete or fix-and-retry. |

This is deliberately simple. Ownership is narrow (each supervisor edits only their own rows; admins rarely edit a supervisor's row in flight), so collisions are rare in practice. No vector clocks, no merge UI.

### Replay edge cases

- **Auth-token-expired during offline period.** The Supabase JS client auto-refreshes silently when it can. If the refresh fails (refresh token also expired), we pause the queue, surface a "Reconnect to sync" banner, prompt the user to re-login, then resume the queue.
- **Mid-replay disconnect.** Each op is committed-or-not in IDB; nothing is in flight in two places. On the next reconnect, the queue resumes from the next un-attempted op.
- **App reload while offline.** Queue persists in IDB, picked up on next load.

### Out of scope (deferred)

- **Offline read of historical data.** Only what's loaded in the current session is offline-readable. The PWA shell is already cached; data caching is its own feature.
- **Encrypted IDB.** The data is already on the device once it has been read; not adding browser-level crypto.
- **Conflict UI / merge dialog.** Last-write-wins.
- **Offline support for admin operations** (renaming projects, promoting users, etc.). Admins are typically on stable connections; admin RPCs are not queued.

---

## Cross-feature integration points

- **Budget total is correct under RLS.** Because `get_project_summary()` is `SECURITY DEFINER`, supervisors see the true project-wide spent total even though they can't `select` other supervisors' rows. The card's number matches what the admin sees.
- **Live updates from any source.** Two realtime channels are subscribed: `expenses` (handler updates the local cache + debounced refetch of `get_project_summary`) and `projects` (handler refetches `get_project_summary` on budget edits). The result is: when ANY user adds/edits/deletes an expense on the project, OR an admin changes the budget, every supervisor's card reflects it within ~1s.
- **Offline writes participate gracefully.** The optimistic-offline state shows the user's own pending impact added to the last-known server total, with a stale indicator. On replay, the realtime channel fans the canonical rows back, the RPC is refetched, and the card transitions from "approximate (stale)" to "true".
- **Budget over-shoot from concurrent offline replays** is **expected and visible**, never blocked. Construction reality.

---

## Testing approach

No automated test runner exists in the repo and adding one is its own phase. Verification is by **manual checklist**, documented alongside the feature in `SETUP.md` (or a new `TESTING.md`):

**Budget feature:**
1. As admin, set budget=1000 / alert=80 on Project X. Card appears, green at 0/1000.
2. Add expenses summing 800. Card flips to amber.
3. Add expenses past 1000. Card flips to red, "Dépassement" label appears.
4. Clear `budget_amount`. Card disappears.
5. As supervisor on Project X, see the card with the same colour state.
6. As admin viewing all projects, see the summed view.
7. **Cross-supervisor accuracy** — set budget=1000. As supervisor A, log 200. As supervisor B (also on Project X), log 500. **Both A and B's cards show "700 / 1000"**, not just their own subtotal. (Validates the SECURITY DEFINER RPC.)
8. **Live budget edit** — open two browsers (admin + supervisor on the project). Admin edits the budget from 1000 to 1500. Supervisor's card updates within ~1s without reload. (Validates `projects` realtime.)

**Offline writes:**
1. Open DevTools → Network → Offline. Add 5 expenses. Confirm rows appear faded with 🕒. Counter shows `Hors ligne (5 en attente)`.
2. Toggle Network back on. Confirm rows settle to full opacity in order, counter clears.
3. Repeat with one row that includes a receipt photo. Confirm both expense and receipt sync.
4. While offline, edit an existing expense. Confirm optimistic update appears, then settles on reconnect.
5. While offline, delete an expense. Confirm row vanishes optimistically, stays gone after reconnect.
6. While offline, in another browser as admin, edit the row that user A is editing offline. User A reconnects → user A's edit wins (last-write-wins; expected).
7. Demote a user mid-offline-session, have them replay. Confirm rejected ops appear red with retry/delete actions.
8. Force-quit the browser tab while ops are queued. Re-open. Confirm queue persists, drains on reconnect.

---

## Decisions baked in

| # | Decision | Rationale |
|---|---|---|
| 1 | Build order: #4 first | Smaller surface, locks schema before #3 depends on it |
| 2 | Currency-agnostic | Matches existing `expenses` schema; avoids feature creep |
| 3 | Last-write-wins for updates | Narrow ownership pattern makes merge UI overkill |
| 4 | No automated tests | Matches existing repo posture (zero test runner today) |
| 5 | Two new migrations: `..._project_budgets.sql`, `..._expense_client_id.sql` | Idempotent, conventional naming |
| 6 | Budgets are informational, not enforced | Construction reality: over-budget spending happens and must be recorded |
| 7 | Single IDB object store, no library, blob inline on insert/update | Simplicity; matches no-toolchain ethos |
| 8 | Offline scope = mutations only (no offline catalog read) | Smaller surface; the realtime cache covers the in-session view |
| 9 | Burn-rate via `SECURITY DEFINER` RPC, not client-side sum | Client-side sum would undercount because RLS hides peers' rows from supervisors |
| 10 | Add `projects` to the realtime publication | Live budget edits propagate to supervisors without reload |

---

## Supabase platform leverage

This spec deliberately uses the platform primitive that fits each problem, instead of reaching for application code. Mapping:

| Concern | Supabase primitive | Why this and not something else |
|---|---|---|
| Authorization for budget aggregation that needs to see across RLS | **`SECURITY DEFINER` SQL function** (`get_project_summary`) | Same pattern already used by `is_admin()` and `claim_first_admin()`. Single round-trip, no Edge Function needed (no compute, no secrets). RLS would otherwise hide other users' rows from a supervisor's `SELECT SUM(amount)`. |
| Live budget edits propagating to supervisors | **Realtime publication on `projects`** | Already use realtime for `expenses`; adding the table to the publication is one line of SQL and one extra channel subscribe in JS. No webhooks, no polling. |
| Hydrating profile + project + budget in one call | **PostgREST embedded reads** (`profiles -> projects(name, budget_amount, budget_alert_pct)`) | The existing query already embeds `projects(name)`; we just widen the embed. Zero new round-trips. |
| Idempotent INSERT replay after offline | **Unique partial index on `expenses.client_id`** + `on conflict (client_id) do nothing` | Lets the client retry safely without duplicates. Couldn't be done with PG sequences alone; needed a client-supplied stable token. |
| Receipt storage with per-user isolation | **Storage RLS using `(storage.foldername(name))[1] = auth.uid()::text`** (already in place) | Path-based authorization is enforced server-side by the bucket policy; the offline replay just has to build the path correctly. |
| Admin mutations that must bypass per-row RLS | **`SECURITY DEFINER` RPCs** (existing `set_user_admin`, `assign_user_project`) | Already established pattern. New code stays consistent. |
| Atomic `updated_at` bump on every UPDATE | **Postgres trigger `touch_updated_at`** (already in place) | Frontend never sets `updated_at` manually. |

**Not used (and why):**

- **Edge Functions** — Nothing in this scope needs server-side compute, secrets, or external API calls. Aggregation is a SQL function. Receipt upload is a client→Storage call. Adding an Edge Function would be ceremony without payoff.
- **Database webhooks / `pg_net`** — Out of scope (no email/push alerts on budget threshold).
- **Supabase Vault** — No new secrets to store.
- **`pg_cron`** — No scheduled work in this spec. (Future: weekly budget summary email would use it.)
- **Postgres views** — Could implement `project_summary` as a view, but a function gives us conditional `WHERE` logic on `auth.uid()` more cleanly.
- **Generated columns** — Considered for `is_over_budget` on `projects`, but generated columns can't reference other tables (where the SUM lives).

---

## Files touched (anticipated)

- `supabase/migrations/20260430000005_project_budgets.sql` (new) — adds budget columns, `get_project_summary()` RPC, `projects` to realtime publication, grant on the function.
- `supabase/migrations/20260430000006_expense_client_id.sql` (new) — adds `expenses.client_id` + unique partial index.
- `index.html` — new stat card, admin panel inputs, i18n strings, second realtime channel on `projects`, debounced RPC refetcher, mutation router, IDB wrapper, optimistic UI, stale-indicator on offline budget card.
- `sw.js` — bump `CACHE` version string so users get the new build.
- `SETUP.md` — append "Run migrations 5 and 6" + manual test checklists.
- `GUIDE.md` — short FR section explaining the offline indicator and what the queue counter means.
- `CLAUDE.md` — note the new architectural elements (budget RPC, dual realtime channels, offline mutation router, client_id idempotency).
