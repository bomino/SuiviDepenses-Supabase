# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Bilingual (EN/FR) PWA for tracking construction-site expenses, **fully serverless**. A single static `index.html` talks directly to Supabase (Auth, Postgres, Storage, Realtime). The only server-side code is two small Supabase Edge Functions (`invite-user`, `delete-user`) that wrap GoTrue admin endpoints — there is no traditional backend service to deploy or maintain.

This is the "Tier 3 / all-in Supabase" sibling of the Flask+Postgres edition at `bomino/SuiviDepenses`.

## Common commands

There is **no build, no bundler, no test runner, no linter** for the runtime app. It ships as plain files. The only tool used in development is the `supabase` CLI (via `npx`) for deploying Edge Functions — not required for the static frontend.

```bash
# Run locally (any static server works; ESM imports require http://, not file://)
python -m http.server 8000
# or
npx serve .

# Deploy frontend = push to main; .github/workflows/deploy.yml handles the rest.

# Deploy Edge Functions (one-time login, then per function):
npx supabase@latest login
npx supabase@latest functions deploy invite-user --project-ref <ref>
npx supabase@latest functions deploy delete-user --project-ref <ref>
```

**Wiring the frontend to a Supabase project** (one-time): edit `index.html` and replace
`SUPABASE_URL` / `SUPABASE_ANON` near the top of the `<script type="module">` block (around line 430)
with the values from the Supabase dashboard → Project Settings → API.

**Applying migrations**: open the Supabase SQL editor and paste each `supabase/migrations/*.sql` file in filename order. (Or `npx supabase db push` if you've linked the project.) Migrations are idempotent (`if not exists`, `on conflict`, `do $$ ... if not exists ... end$$`) so re-running is safe.

**Pushing a new frontend version to clients**: handled automatically. The `.github/workflows/deploy.yml` workflow runs on every push to `main`, replaces the `__VERSION__` placeholder in `sw.js` with the short Git SHA, and deploys to GitHub Pages. Returning users get the new build on next visit because the service-worker cache key changed. **Do not hardcode a real value into `sw.js`** — keep the `__VERSION__` placeholder; CI substitutes at deploy time. For local dev the placeholder is fine as a literal (it acts as a stable cache key).

## Architecture (the bits that span files)

### Trust boundary lives in Postgres, not in JS

The anon key in `index.html` is **public by design**. Every meaningful authorization rule is a Row-Level Security policy in `supabase/migrations/20260101000002_rls.sql` plus the storage policies in `..._storage.sql`. When adding a feature that reads or writes data, the right question is "what RLS policy makes this safe?", not "what client-side check do I add?".

**Never put the `service_role` key into `index.html`** — it bypasses RLS entirely. If a feature needs privileged work, two options in order of preference:
1. **`SECURITY DEFINER` SQL function** (see `_admin_helpers.sql`, `_project_budgets.sql`, `_user_directory.sql`) called via `supabase.rpc(...)`. The function checks `is_admin(auth.uid())` itself.
2. **Edge Function** (see `supabase/functions/invite-user`, `supabase/functions/delete-user`) when you need to call the GoTrue admin HTTP API or another service that PL/pgSQL can't reach. The function gets the service-role key via Supabase env vars at runtime — it never touches the browser.

### Three-table data model

- `profiles` — 1-to-1 with `auth.users`. Auto-created by the `handle_new_user` trigger on sign-up. Holds `is_admin` and `project_id` (a supervisor's assigned site).
- `projects` — one row per construction site.
- `expenses` — the transactional table. Has `user_id`, `project_id`, and an optional `receipt_path` pointing into the `receipts` storage bucket.

Authorization model used by RLS: **admin sees/mutates everything; supervisor only sees rows where `user_id = auth.uid()` AND `project_id = their profile.project_id`**. This same shape is repeated in select/insert/update/delete policies — when modifying one, modify the matching siblings.

### Admin operations go through RPCs, not direct table writes

Admin-only mutations (promote/demote a user, assign a user to a project) are implemented as `SECURITY DEFINER` functions in `_admin_helpers.sql` and called via `supabase.rpc('set_user_admin', ...)` / `supabase.rpc('assign_user_project', ...)`. The functions check `is_admin(auth.uid())` themselves. Don't try to replicate these by direct UPDATEs on `profiles` from the client — RLS will (correctly) reject them.

**User-management operations that need service-role privilege live in Edge Functions** because the GoTrue admin API (invite, delete, etc.) is HTTPS-only — Postgres functions can't reach it. There are currently two:

- `supabase/functions/invite-user/index.ts` — sends a magic-link invite via `/auth/v1/invite`.
- `supabase/functions/delete-user/index.ts` — best-effort cleanup of the target's storage objects under `receipts/<user_id>/`, then `DELETE /auth/v1/admin/users/<id>`. The cascade FKs on `profiles.id → auth.users(id)` and `expenses.user_id → auth.users(id)` handle the DB rows; storage isn't FK-tied so the function lists+deletes manually.

Both follow the same skeleton: CORS preflight first, parse JSON body, verify the caller's JWT against `/auth/v1/user`, look up `profiles.is_admin` via PostgREST scoped by the JWT, then perform the admin operation with the service-role key. Frontend calls via `supabase.functions.invoke('<name>', { body: {...} })`. Self-protection (caller can't delete or demote themselves) lives inside the function, not just the UI.

If you add another admin operation that requires service-role, follow this skeleton — don't put service-role anywhere else, and don't refactor the two functions into a shared module until there are at least three (premature DRY).

### First-admin bootstrap and the invite-only access model

The app is invite-only in steady state — the login overlay only offers email + password sign-in, no signup tab. The bootstrap path for a fresh install is:

1. Operator temporarily flips **Auth → Providers → Email → Enable user signups** ON in the Supabase dashboard.
2. Operator runs `await window.supabase.auth.signUp(...)` from DevTools console on the deployed login page.
3. On the next sign-in the frontend silently calls `supabase.rpc('claim_first_admin')`. With zero admins in the DB, the RPC promotes the caller. From then on, the RPC is a no-op (returns false unless zero admins exist) and is safe to leave in production.
4. Operator flips signups back OFF. New accounts now arrive via the in-app **Manage Users → Invite by email** flow (which uses the `invite-user` Edge Function).

If you change auth/login flow, **keep the `claim_first_admin` call** (search for it in `index.html`) — it's harmless once an admin exists and load-bearing for new installs.

### Receipt storage path is load-bearing

Every receipt must be uploaded to `receipts/<user_id>/<expense_id>.<ext>`. The storage RLS policy (`_storage.sql`) gates access on `(storage.foldername(name))[1] = auth.uid()::text` — i.e. the first path segment must equal the caller's UUID. **Changing the path format without updating the storage policy will break uploads.** The frontend builds the path in `uploadReceipt` (around `index.html:953`).

Receipts are private; the UI fetches them with `createSignedUrl(path, 60)` (60-second URL).

### Auth email redirects: ALWAYS pass `redirectTo` from `appBaseUrl()`, never rely on Site URL

Every Supabase auth call that triggers an email with a redirect link (sign-up, magic-link, password-reset, invite, email-change) MUST pass `redirectTo` / `emailRedirectTo` explicitly, computed from the helper `appBaseUrl()` (returns `window.location.origin + window.location.pathname`). Don't rely on the Site URL fallback configured in the Supabase dashboard — its handling of the path component is inconsistent (sometimes treated as origin-only) and lands users at bare origin → 404 on subpath deploys like GitHub Pages.

Authoritative call sites in the current app:
- `auth.resetPasswordForEmail(email, { redirectTo: appBaseUrl() })` (forgot-password flow)
- `invite-user` Edge Function — frontend sends `redirectTo` in the body; the function appends it as a `redirect_to` query parameter to `/auth/v1/invite`
- *(If you ever re-enable signup or magic-link, re-add `options: { emailRedirectTo: appBaseUrl() }` to those calls too.)*

The redirect URL must also be present in **Supabase → Auth → URL Configuration → Redirect URLs** allowlist or GoTrue rejects the redirect. The current allowlist must contain the deployed Pages URL with the project subpath (e.g. `https://bomino.github.io/SuiviDepenses-Supabase/`) and any localhost variants used for dev.

### Password recovery and invite-acceptance share an overlay

`onAuthStateChange` distinguishes three "must set a password" cases from a normal sign-in:

- `PASSWORD_RECOVERY` event — fired by Supabase when a recovery token is in the URL. The session is restricted to `auth.updateUser()` only — calling `loadCurrentUser()` would put the user in a half-broken state.
- First `SIGNED_IN` after an admin invite — detected via `initialHashParams.type === 'invite'` (the URL hash is captured in a module-level snapshot before the deferred Supabase module clears it). The user has a session but no password yet; if we just signed them in, they couldn't log back in next time without a Forgot Password.

Both reuse the dedicated `#recoveryOverlay` modal with different copy ("Set a new password" vs "Welcome — choose your password"). On submit, `auth.updateUser({ password })` upgrades the session, then `loadCurrentUser()` runs normally.

### Realtime sync uses two channels with client-side reconciliation

`subscribeRealtime()` in `index.html` opens two channels:
- `expenses-live` — INSERT/UPDATE/DELETE on `public.expenses`. The handler reconciles into the local `expenses` array, **dedupes by `_client_id`** to avoid duplicate rows when an offline INSERT replay races with the realtime fan-out, and triggers a debounced `get_project_summary` refetch so the burn-rate card stays accurate even when other supervisors' rows change (which RLS hides from the local cache).
- `projects-live` — any change on `public.projects`. The handler refetches `get_project_summary` (debounced 250ms) so admin budget edits propagate to every supervisor live.

The expenses channel's `.subscribe(status => ...)` callback also fires `replayQueue()` on `SUBSCRIBED` to drain the offline queue on reconnect.

If you add a new table that needs live updates, also add `alter publication supabase_realtime add table public.<name>;` to a migration (mirrors the lines in `_schema.sql` and `_project_budgets.sql`).

### Burn-rate goes through `get_project_summary()`, not client-side SUM

The "Budget" stat card aggregates spent-per-project via the `SECURITY DEFINER` RPC `get_project_summary()` in `_project_budgets.sql`. **Do not replace this with `SELECT SUM(amount) FROM expenses`** — RLS would hide other supervisors' rows from the calling supervisor and the card would silently undercount. The function bypasses RLS for the aggregation but enforces authorization (admin OR caller's assigned project) inside the body.

A second realtime channel on `public.projects` keeps the card live when admins edit budgets.

### Offline writes go through a mutation router and an IndexedDB queue

Every write (`saveExpense`, `deleteExpense`) goes through `routedWrite(spec, directFn)`. It tries the Supabase call first; if that fails with a **network-level** error (or `navigator.onLine === false`), the op lands in IDB store `pending_ops` (DB `suividepenses_offline`). **Server-level errors (RLS, validation, 5xx) are NOT queued** — they surface inline as today.

Replay is FIFO and triggered by: `window.online` event, window focus, document visibility change, and the realtime channel reaching `SUBSCRIBED`. The replay executor for INSERT uses `upsert(payload, { onConflict: 'client_id' })` so a network blip during the direct attempt that landed the row but lost the response becomes a no-op on retry.

Receipt blobs are queued **inline** on the insert/update op (no separate `upload_receipt` op type). The replay sequence for an insert with a blob is: INSERT → upload to `receipts/<user_id>/<real_id>.<ext>` → UPDATE `receipt_path`.

**Don't add a sync library** (Dexie, RxDB, etc.) — the wrapper is intentionally ~80 lines of raw IndexedDB to match the no-toolchain ethos.

**Known limitation:** offline DELETE removes the row locally immediately for good UX. If the replay is later rejected (RLS, e.g. user demoted mid-session), the rejected op stays in IDB but there's no UI affordance to surface it — the user can only see it via DevTools. Future fix is mark-and-hide instead of removal. See `// TODO(offline)` in `deleteExpense`.

### `index.html` has two `<script>` blocks on purpose

- `<script type="module">` (around line 400) — only sets up the Supabase client and exposes it as `window.supabase` so the classic script can use it.
- `<script>` (classic, runs after) — all app code. Inline `onclick="..."` handlers in the markup require their functions to be on `window` (see the many `window.foo = foo` lines throughout). When adding a new handler invoked from inline HTML, **assign it to `window`** or it will silently break.

**Critical timing rule:** module scripts are *deferred* (run AFTER the classic script). The classic script therefore must NOT touch `window.supabase` at the top level — `window.supabase` is undefined when the classic script executes. App startup that needs Supabase (e.g. `onAuthStateChange` registration) lives inside `function __startApp()` exposed on `window`; the module calls `window.__startApp()` after setting `window.supabase`. New top-level code in the classic script must follow the same pattern, or be inside a function called later.

State is held in module-level `var` globals (`currentUser`, `expenses`, `allProjects`, `realtimeChannel`). There's no framework, no virtual DOM, no router — `render()` rebuilds the table HTML from the current `expenses` array and the active filters.

### i18n

`dict.en` / `dict.fr` in `index.html` plus a `t(key)` helper. UI strings should go through `t()`, and **both languages must be updated together** — there's no fallback if a key is missing in one locale. The active language is persisted in `localStorage`.

## Conventions worth respecting

- **New migrations**: `YYYYMMDDHHMMSS_what_changed.sql` under `supabase/migrations/`. Idempotent. Reference earlier objects assuming they exist (migrations run in filename order).
- **Don't import bundlers or a build step** for the runtime app. The "no toolchain" property is a feature of this edition; adding webpack/vite would change the deploy story for every downstream user. (The CI workflow uses Node only for the `actions/upload-pages-artifact` step and `sed`; the served code is hand-written.)
- **Don't add a third Edge Function until you've reviewed the existing two.** They share a CORS + JWT-verify + admin-check skeleton on purpose — duplicate it for the third one too. Refactor into a shared module only at the fourth (premature DRY).
- **Don't introduce a third-party backend service** for features that can be done with RLS + an RPC + the existing Edge Function pattern. The whole point of the Tier 3 edition is to keep ops surface tiny.
