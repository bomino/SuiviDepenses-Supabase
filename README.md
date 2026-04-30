# Suivi des Dépenses — Supabase Edition

A bilingual (EN/FR) PWA for tracking construction project expenses, **fully serverless**: the static frontend talks directly to a Supabase Postgres database. No Flask, no Railway, no Python in production.

This is the Tier 3 / "all-in Supabase" sibling of [bomino/SuiviDepenses](https://github.com/bomino/SuiviDepenses) (which uses Flask + Postgres on Railway).

## Why this version exists

Same domain — admins and supervisors logging construction expenses across multiple project sites — but built around what Supabase makes easy:

- **Real-time sync**: a foreman enters an expense on the site; the admin sees it appear on their dashboard a second later, without reloading.
- **Receipt photos**: each expense can have a receipt image attached, stored in Supabase Storage with row-level access control.
- **Email-based auth**: sign-up, password reset, and magic-link login work out of the box. No bcrypt code to maintain.
- **Row-level security**: visibility rules (admin sees all, supervisor sees own) live in Postgres policies, enforced even if a hostile client tries to bypass the UI.

## Stack

| Layer | Tech |
|---|---|
| Frontend | Single static `index.html`, vanilla JS, `@supabase/supabase-js@2` via CDN |
| Auth | Supabase Auth (email/password, magic link, password reset) |
| Database | Supabase Postgres with RLS policies |
| File storage | Supabase Storage bucket `receipts`, private + signed URLs |
| Real-time | Supabase Realtime channel on the `expenses` table |
| Hosting | Any static host: Vercel, Netlify, GitHub Pages, Cloudflare Pages, S3+CloudFront |

> **Documentation index**
> - [`SETUP.md`](./SETUP.md) — step-by-step Supabase project creation, run the SQL migrations, paste your URL/anon key into `index.html`, deploy the static frontend.
> - [`GUIDE.md`](./GUIDE.md) — French user guide for admins and supervisors (login, daily usage, installing on phone, troubleshooting).
> - [`supabase/migrations/`](./supabase/migrations/) — SQL files that build the schema, RLS policies, storage bucket, and admin RPCs.

## Quick start

Five steps to a running deploy. Full detail in [SETUP.md](./SETUP.md).

1. Create a free Supabase project at https://supabase.com.
2. In the SQL editor, run the four files in `supabase/migrations/` in order.
3. Open `index.html` and replace `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY` with your project's values (from Project Settings → API).
4. Push the static files to any host (or just open `index.html` locally during development).
5. Sign up with the first email — the very first user automatically gets admin rights via the `claim_first_admin()` RPC. From there, manage projects and assign users via the in-app **Manage Users** panel.

## File layout

```
SuiviDepenses-Supabase/
├── README.md
├── SETUP.md                 ← Supabase project setup & deployment
├── GUIDE.md                 ← French user guide
├── index.html               ← Single-file PWA (paste URL+key here)
├── manifest.json
├── sw.js
├── icons/                   ← PWA icons (PNG, 32 / 180 / 192 / 512)
├── supabase/
│   └── migrations/
│       ├── 20260101000001_schema.sql       ← tables + triggers + Realtime
│       ├── 20260101000002_rls.sql          ← row-level security policies
│       ├── 20260101000003_storage.sql      ← receipts bucket + storage RLS
│       └── 20260101000004_admin_helpers.sql ← admin-only RPCs (set_user_admin, etc.)
└── .gitignore
```

## What's NOT here (compared to Tier 2)

- No `server.py`, no `requirements.txt`, no `gunicorn`, no `Procfile`, no Railway config — this version has no backend code.
- No `scripts/add_user.py` — users sign themselves up via the login screen; admins assign them via the panel.
- No `INITIAL_USERNAME` / `INITIAL_PASSWORD` env vars — the first user to sign up auto-promotes to admin via `claim_first_admin()`.

## License

Same as upstream: MIT (assumed; add an explicit LICENSE file if you publish).
