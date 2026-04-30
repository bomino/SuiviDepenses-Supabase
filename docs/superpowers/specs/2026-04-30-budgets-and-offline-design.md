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
alter table public.projects
    add column if not exists budget_amount numeric(14,2),
    add column if not exists budget_alert_pct int not null default 80
        check (budget_alert_pct between 0 and 100);
```

- `budget_amount` is **nullable**. Null means "no budget set" — UI hides the budget card.
- `budget_alert_pct` defaults to 80 (the threshold at which the bar turns amber).
- **No currency column.** The app is currency-agnostic today (no currency on `expenses` either). Keep it that way; numbers are formatted with the user's locale.

### RLS

No new policies. The existing `projects_update_admin` policy already gates writes to admins; the existing `projects_select` policy lets every authenticated user read. The new columns inherit those policies.

### Frontend (`index.html`)

**Stat cards row** — add a 5th card "Budget" beside the existing four (Total / Paid / Pending / Unpaid):

- Hidden when the user's project has `budget_amount = null`.
- Shows: spent total, slash, budget total, on a single line. Below: a horizontal progress bar.
- Bar colour:
  - green if `spent / budget < alert_pct/100`
  - amber if `alert_pct/100 ≤ spent / budget < 1.0`
  - red if `spent / budget ≥ 1.0`
- For an **admin viewing all projects**, show summed budget vs summed spent across all projects. Skip null-budget projects from the sum.

**Admin panel → Projects section** — each project row gets two extra inputs and a Save button:

- `Budget` (numeric, blank-allowed for null) and `Alert %` (integer 0–100).
- Save calls `supabase.from('projects').update({ budget_amount, budget_alert_pct }).eq('id', pid)` — RLS handles authorization.

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
  op_type:     'insert' | 'update' | 'delete' | 'upload_receipt',
  client_id:   uuid (for inserts; copied to expenses.client_id when replayed),
  target_id:   uuid | null,        // server PK for update/delete
  payload:     object,             // the row data for insert/update; null for delete
  blob:        Blob | null,        // receipt file bytes for upload_receipt
  mime:        string | null,
  ext:         string | null,
  created_at:  ISO timestamp,
  attempts:    int,
  last_error:  string | null
}
```

Single store keeps it simple. Receipt blobs live inline; browsers comfortably store hundreds of MB in IDB which is more than enough for a few queued receipts on a phone.

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

- **Budget calculation works correctly with offline writes** — the burn-rate card sums whatever is in the local `expenses` array (which includes optimistic offline rows). On replay, realtime fan-out replaces the optimistic rows with the canonical ones; the sum stays consistent. Budget over-shoot from concurrent offline replays (two users push past 100% independently) is **expected and visible**, not blocked.
- **Realtime channel** — already subscribed to `expenses`. After reconnect, Supabase resubscribes the channel automatically; no extra code.

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
| 7 | Single IDB object store, no library | Simplicity; matches no-toolchain ethos |
| 8 | Offline scope = mutations only (no offline catalog read) | Smaller surface; the realtime cache covers the in-session view |

---

## Files touched (anticipated)

- `supabase/migrations/20260430000005_project_budgets.sql` (new)
- `supabase/migrations/20260430000006_expense_client_id.sql` (new)
- `index.html` — new stat card, admin panel inputs, i18n strings, mutation router, IDB wrapper, optimistic UI
- `sw.js` — bump `CACHE` version string so users get the new build
- `SETUP.md` — append "Run migrations 5 and 6" + manual test checklists
- `GUIDE.md` — short FR section explaining the offline indicator and what the queue counter means
- `CLAUDE.md` — note budget calculation logic + offline mutation router as new architectural elements
