# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Bilingual (EN/FR) PWA for tracking construction-site expenses, **fully serverless**. A single static `index.html` talks directly to Supabase (Auth, Postgres, Storage, Realtime). There is no backend service — no Flask, no Node server, no API layer to deploy.

This is the "Tier 3 / all-in Supabase" sibling of the Flask+Postgres edition at `bomino/SuiviDepenses`.

## Common commands

There is **no build, no bundler, no test runner, no linter** in this repo. It ships as plain files.

```bash
# Run locally (any static server works; ESM imports require http://, not file://)
python -m http.server 8000
# or
npx serve .

# Deploy = push the static files to any host (Vercel, Netlify, GH Pages, Cloudflare Pages).
# No build step.
```

**Wiring the frontend to a Supabase project** (one-time): edit `index.html` and replace
`SUPABASE_URL` / `SUPABASE_ANON` near the top of the `<script type="module">` block (around line 407)
with the values from the Supabase dashboard → Project Settings → API.

**Applying migrations**: open the Supabase SQL editor and paste each `supabase/migrations/*.sql` file in filename order. There is no `supabase` CLI workflow here. Migrations are idempotent (`if not exists`, `on conflict`, `drop policy if exists`) so re-running is safe.

**Pushing a new frontend version to clients**: handled automatically. The `.github/workflows/deploy.yml` workflow runs on every push to `main`, replaces the `__VERSION__` placeholder in `sw.js` with the short Git SHA, and deploys to GitHub Pages at `https://bomino.github.io/SuiviDepenses-Supabase/`. Returning users get the new build on next visit because the cache key changed. **Do not hardcode a real value into `sw.js`** — keep the `__VERSION__` placeholder; CI substitutes at deploy time. For local dev (`http.server` etc.) the placeholder is fine as a literal — it just acts as a stable cache key.

## Architecture (the bits that span files)

### Trust boundary lives in Postgres, not in JS

The anon key in `index.html` is **public by design**. Every meaningful authorization rule is a Row-Level Security policy in `supabase/migrations/20260101000002_rls.sql` plus the storage policies in `..._storage.sql`. When adding a feature that reads or writes data, the right question is "what RLS policy makes this safe?", not "what client-side check do I add?".

**Never put the `service_role` key into `index.html`** — it bypasses RLS entirely. If a feature needs privileged work, add a `SECURITY DEFINER` SQL function (see `_admin_helpers.sql`) and call it via `supabase.rpc(...)`.

### Three-table data model

- `profiles` — 1-to-1 with `auth.users`. Auto-created by the `handle_new_user` trigger on sign-up. Holds `is_admin` and `project_id` (a supervisor's assigned site).
- `projects` — one row per construction site.
- `expenses` — the transactional table. Has `user_id`, `project_id`, and an optional `receipt_path` pointing into the `receipts` storage bucket.

Authorization model used by RLS: **admin sees/mutates everything; supervisor only sees rows where `user_id = auth.uid()` AND `project_id = their profile.project_id`**. This same shape is repeated in select/insert/update/delete policies — when modifying one, modify the matching siblings.

### Admin operations go through RPCs, not direct table writes

Admin-only mutations (promote/demote a user, assign a user to a project) are implemented as `SECURITY DEFINER` functions in `_admin_helpers.sql` and called via `supabase.rpc('set_user_admin', ...)` / `supabase.rpc('assign_user_project', ...)`. The functions check `is_admin(auth.uid())` themselves. Don't try to replicate these by direct UPDATEs on `profiles` from the client — RLS will (correctly) reject them.

### First-admin bootstrap is silent and idempotent

On every successful login, the frontend calls `supabase.rpc('claim_first_admin')`. The function promotes the caller **only if zero admins exist**, otherwise returns false. This avoids a chicken-and-egg setup step but is safe to leave in production. If you change auth/login flow, keep this call (search for `claim_first_admin` in `index.html`).

### Receipt storage path is load-bearing

Every receipt must be uploaded to `receipts/<user_id>/<expense_id>.<ext>`. The storage RLS policy (`_storage.sql`) gates access on `(storage.foldername(name))[1] = auth.uid()::text` — i.e. the first path segment must equal the caller's UUID. **Changing the path format without updating the storage policy will break uploads.** The frontend builds the path in `uploadReceipt` (around `index.html:953`).

Receipts are private; the UI fetches them with `createSignedUrl(path, 60)` (60-second URL).

### Realtime sync is a single channel with client-side reconciliation

`subscribeRealtime()` in `index.html` opens one channel on `public.expenses`, and a single `postgres_changes` handler dispatches INSERT/UPDATE/DELETE into the local `expenses` array. RLS already filters what the channel delivers, so the handler doesn't re-check authorization. If you add a new table that needs live updates, you must also add `alter publication supabase_realtime add table public.<name>;` (mirrors the line at the bottom of `_schema.sql`).

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
- **Don't import bundlers or a build step.** The "no toolchain" property is a feature of this edition; adding webpack/vite would change the deploy story for every downstream user.
- **Don't introduce a backend service** for features that can be done with RLS + an RPC. The whole point of the Tier 3 edition is no server.
