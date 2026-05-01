# Suivi des Dépenses — Supabase Edition

A bilingual (EN/FR) PWA for tracking construction project expenses, **fully serverless**: a single static `index.html` talks directly to Supabase. No Flask, no Railway, no Python in production. The only server-side code is two small Supabase Edge Functions for privileged admin operations.

This is the Tier 3 / "all-in Supabase" sibling of [bomino/SuiviDepenses](https://github.com/bomino/SuiviDepenses) (which uses Flask + Postgres on Railway).

## Why this version exists

Same domain — admins and supervisors logging construction expenses across multiple project sites — but built around what Supabase makes easy:

- **Real-time sync**: a foreman enters an expense on the site; the admin sees it appear on their dashboard a second later, without reloading.
- **Receipt photos**: each expense can have a receipt image attached, stored in Supabase Storage with row-level access control.
- **Project budgets + burn-rate dashboard**: admins set a budget per project; everyone sees a live `spent / budget` card with a green / amber / red progress bar.
- **Offline-first writes**: supervisors can keep working in dead zones (basements, ascenseurs, zones blanches). Mutations queue locally in IndexedDB and sync FIFO on reconnect, with optimistic UI for pending rows.
- **Admin-invite-only access**: new accounts come from an in-app "Invite by email" flow that wraps Supabase's magic-link invite. Admins also delete users (and their data) from the same panel.
- **Row-level security**: visibility rules (admin sees all, supervisor sees own) live in Postgres policies, enforced even if a hostile client tries to bypass the UI.

## Stack

| Layer | Tech |
|---|---|
| Frontend | Single static `index.html`, vanilla JS, `@supabase/supabase-js@2` via CDN |
| Auth | Supabase Auth (password + admin-issued invites; magic link disabled by default) |
| Database | Supabase Postgres with RLS policies and `SECURITY DEFINER` RPCs |
| File storage | Supabase Storage bucket `receipts`, private + signed URLs |
| Real-time | Supabase Realtime channels on `expenses` and `projects` |
| Privileged admin ops | Two Supabase Edge Functions (Deno): `invite-user`, `delete-user` |
| Offline queue | IndexedDB (raw API, no library), idempotent INSERT replay via `client_id` |
| Hosting | GitHub Pages with auto-deploy via the included GitHub Actions workflow |

> **Documentation index**
> - [`SETUP.md`](./SETUP.md) — step-by-step Supabase project creation, migrations, Edge Function deploys, Pages auto-deploy, lockdown checklist.
> - [`GUIDE.md`](./GUIDE.md) — French user guide for admins and supervisors (sign-in, invite acceptance, daily usage, installing on phone, troubleshooting).
> - [`CLAUDE.md`](./CLAUDE.md) — architectural notes for AI coding assistants and contributors. Captures the load-bearing conventions that span files (RLS as trust boundary, redirect-URL convention, Edge Function pattern, etc.).
> - [`supabase/migrations/`](./supabase/migrations/) — SQL files that build the schema, RLS policies, storage bucket, admin RPCs, budget RPC, offline idempotency column, and user-directory RPC.
> - [`supabase/functions/`](./supabase/functions/) — Edge Function source for `invite-user` and `delete-user`.

## Quick start

Six steps to a running deploy. Full detail in [SETUP.md](./SETUP.md).

1. Create a free Supabase project at https://supabase.com.
2. In the SQL editor, run the seven files in `supabase/migrations/` in order.
3. Open `index.html` and replace `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY` with your project's values (from Project Settings → API).
4. Push the repo to GitHub. The included `.github/workflows/deploy.yml` auto-publishes to GitHub Pages on every push to `main`.
5. Bootstrap the first admin (one-time, with **Confirm email** temporarily off in Supabase). Once the first user signs up and `claim_first_admin()` promotes them, **disable user signups** in the Supabase dashboard. From then on, new accounts arrive via the in-app **Manage Users → Invite by email** flow.
6. Deploy the two Edge Functions (`invite-user`, `delete-user`) via the Supabase CLI or dashboard. Required for the in-app invite/delete features.

## File layout

```
SuiviDepenses-Supabase/
├── README.md
├── SETUP.md                 ← Supabase setup & deployment walkthrough
├── GUIDE.md                 ← French end-user guide
├── CLAUDE.md                ← architectural notes for contributors / AI assistants
├── index.html               ← single-file PWA (paste URL+key here)
├── manifest.json
├── sw.js                    ← service worker (CACHE version auto-injected at deploy)
├── icons/                   ← PWA icons
├── .github/workflows/
│   └── deploy.yml           ← GitHub Pages auto-deploy + cache-version injection
├── supabase/
│   ├── migrations/
│   │   ├── 20260101000001_schema.sql
│   │   ├── 20260101000002_rls.sql
│   │   ├── 20260101000003_storage.sql
│   │   ├── 20260101000004_admin_helpers.sql
│   │   ├── 20260430000005_project_budgets.sql        ← budgets + RPC + projects realtime
│   │   ├── 20260430000006_expense_client_id.sql      ← offline INSERT idempotency
│   │   └── 20260430000007_user_directory.sql         ← admin user-list RPC
│   └── functions/
│       ├── invite-user/index.ts                       ← admin-only invite-by-email
│       └── delete-user/index.ts                       ← admin-only user deletion
├── docs/
│   └── superpowers/                                   ← design specs and implementation plans
└── .gitignore
```

## What's NOT here (compared to Tier 2)

- No `server.py`, no `requirements.txt`, no `gunicorn`, no `Procfile`, no Railway config — this version has no traditional backend service.
- No `scripts/add_user.py` — admin invites users from inside the app via the `invite-user` Edge Function.
- No `INITIAL_USERNAME` / `INITIAL_PASSWORD` env vars — the very first user to sign up auto-promotes to admin via `claim_first_admin()`, then signups are disabled.

## License

MIT (assumed; add an explicit LICENSE file if you publish).
