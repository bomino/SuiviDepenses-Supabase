# Setup Guide — Supabase Edition

End-to-end walkthrough for getting this app live. Total time: ~20 minutes the first time.

---

## Table of contents

1. [Prerequisites](#1-prerequisites)
2. [Create the Supabase project](#2-create-the-supabase-project)
3. [Run the SQL migrations](#3-run-the-sql-migrations)
4. [Configure auth (URLs and email)](#4-configure-auth-urls-and-email)
5. [Wire the frontend to the project](#5-wire-the-frontend-to-the-project)
6. [Run locally](#6-run-locally)
7. [Deploy as a static site](#7-deploy-as-a-static-site)
8. [Bootstrap the first admin](#8-bootstrap-the-first-admin)
9. [Verify everything works](#9-verify-everything-works)
10. [Updating the schema later](#10-updating-the-schema-later)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Prerequisites

- A Supabase account (https://supabase.com — free tier is plenty: 500 MB DB, 1 GB storage, 50 K monthly active users).
- A way to host static files. Any of these work and are free:
  - **Vercel** (`vercel deploy`) — drag-and-drop or CLI
  - **Netlify** (`netlify deploy`)
  - **GitHub Pages** (push to a `gh-pages` branch or `docs/` folder)
  - **Cloudflare Pages**
- Git installed (to clone/manage this repo).

You do **not** need Python, Node, or any build tooling — `index.html` ships ready to run.

---

## 2. Create the Supabase project

1. https://supabase.com/dashboard → **New project**.
2. Pick a name (e.g. `suivi-depenses`), pick a strong DB password (you won't usually use it directly — Supabase generates connection strings for you), pick a region close to your users.
3. Wait ~2 minutes for provisioning. The dashboard shows a green dot when ready.

When it's up, note these two values from **Project Settings → API**:

- **Project URL** — looks like `https://abcdefghijkl.supabase.co`
- **anon public key** — a long JWT string starting with `eyJ...`

Both of these go into `index.html` later (Step 5). They are safe to commit to a public repo because Row-Level Security policies (installed in Step 3) are what actually protect the data.

> ⚠️ Do **NOT** put the **service_role** key into `index.html`. That key bypasses RLS entirely. Keep it server-side only (you don't need it for this app).

---

## 3. Run the SQL migrations

Open **SQL editor** in the Supabase dashboard (lightning-bolt icon). For each file under `supabase/migrations/`, copy the full contents into a new query and click **Run**. Run them in order:

| Order | File | What it does |
|---|---|---|
| 1 | `20260101000001_schema.sql` | Creates `profiles`, `projects`, `expenses`. Wires triggers (auto-create profile on sign-up, auto-bump `updated_at`). Enables Realtime on `expenses`. |
| 2 | `20260101000002_rls.sql` | Enables RLS on every table and installs the policies (admins see all, supervisors see only their own project's rows). |
| 3 | `20260101000003_storage.sql` | Creates the `receipts` storage bucket and its RLS policies (a supervisor can only put/get files under their own UUID prefix). |
| 4 | `20260101000004_admin_helpers.sql` | Installs `set_user_admin`, `assign_user_project`, `claim_first_admin` RPCs that the admin panel calls. |
| 5 | `20260430000005_project_budgets.sql` | Adds budget columns to `projects`, the `get_project_summary()` aggregation RPC (SECURITY DEFINER), and adds `projects` to the realtime publication. |

Each migration is **idempotent** (uses `if not exists` and `on conflict`), so re-running them is safe.

After they're applied, check **Table editor** — you should see `profiles`, `projects`, `expenses` (all empty) and **Storage → Buckets** should list `receipts`.

---

## 4. Configure auth (URLs and email)

In the dashboard:

### Authentication → URL Configuration

- **Site URL**: where the app will be hosted, e.g. `https://expenses.yoursite.com` or `https://your-username.github.io/SuiviDepenses-Supabase`. For local dev, `http://localhost:8000` is fine.
- **Redirect URLs**: add the same URL plus any localhost variants you'll use for development (`http://localhost:8000`, `http://localhost:5173`, etc.). Magic-link and password-reset emails are only allowed to redirect to URLs in this list.

### Authentication → Providers → Email

- **Enable email provider**: ON.
- **Confirm email**: your call.
  - **ON** (recommended for production): users must click the link in their inbox before they can sign in. More secure, but adds friction for a small construction crew.
  - **OFF** (recommended for fast iteration): users can sign in immediately after sign-up. Fine for a closed deploy where you trust the email list.

### Authentication → Email Templates (optional)

You can customize the FR text of the confirmation, magic-link, and password-reset emails to match your team's language. Default English templates work fine if you skip this.

---

## 5. Wire the frontend to the project

Open `index.html`. Find these two lines near the top of the `<script type="module">` block:

```js
const SUPABASE_URL  = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON = 'YOUR_SUPABASE_ANON_KEY';
```

Replace both with your project's values from Step 2.

> **Don't worry about leaking the anon key.** It's designed to be public — RLS policies are the real security. Anyone reading the key can only do what RLS allows for unauthenticated or authenticated users.

---

## 6. Run locally

A static file server is enough. Pick whichever you prefer:

```bash
# Python 3 (built-in)
python -m http.server 8000

# Node (npx)
npx serve .

# Or just open index.html in a browser — but auth redirects work better with a real server
```

Open http://localhost:8000. The login overlay should appear. If not, check the browser console — most errors at this stage are typos in the URL/anon key from Step 5.

---

## 7. Deploy as a static site

Pick the host you prefer. All of these are free.

### GitHub Pages (zero config)

1. Push the repo to a public GitHub repository.
2. Repo → **Settings → Pages** → Source: **Deploy from a branch**, branch: `main`, folder: `/ (root)` → **Save**.
3. URL becomes `https://<your-username>.github.io/<repo-name>/`. Add it to Supabase **Auth → URL Configuration → Site URL & Redirect URLs**.

### Vercel (drag-and-drop)

1. https://vercel.com/new → **Import Git Repository** → pick this repo.
2. No build command (it's static) → **Deploy**.
3. URL: `<project>.vercel.app`. Add to Supabase **Auth → URL Configuration**.

### Netlify

```bash
npx netlify deploy --prod --dir=.
```

Whichever host you pick, **update the Site URL and Redirect URLs in Supabase** to include the production domain — otherwise email links won't redirect correctly.

---

## 8. Bootstrap the first admin

There's no manual setup step — the very first sign-up auto-promotes:

1. Open the deployed app.
2. On the login screen, click **Sign up**, enter your email + a password, submit.
3. (If "Confirm email" is on, click the verification link in your inbox.)
4. Sign in with the same credentials.
5. The frontend silently calls the `claim_first_admin()` RPC on every login. Since there are zero admins in the DB, that RPC promotes you on the spot.

You'll see the **Manage Users** button appear in the header.

From now on, `claim_first_admin()` is a no-op for everyone else (it returns false unless zero admins exist). That makes the bootstrap safe to leave in production.

---

## 9. Verify everything works

Run through this checklist as the first admin:

1. **Manage Users → Projects** → add a project (e.g. "Villa Tower").
2. **Manage Users → Users** → assign yourself to the project via the dropdown.
3. The project name appears in the header.
4. Add an expense via the form. It shows up in the list immediately.
5. Attach a receipt photo (any image ≤5 MB). Click the 📎 icon in the row to verify it opens.
6. **In a different browser** (or incognito), sign up a second account. The admin panel should now list two users; assign the new one as a worker on the same project.
7. As that supervisor, add an expense. **In the admin's still-open browser**, the new row should appear within ~1 second without a reload — that's Realtime working.
8. As the supervisor, try to access another project's data via DevTools → Network: the response should be empty (RLS blocks it).

If all 8 pass, you're production-ready.

### 9.x Budget feature (post-Phase-1)

1. As admin, **Manage Users → Projects**: set Budget=1000, Alert=80 on a project. Toast confirms.
2. On the home screen the new Budget card shows `0 / 1000` in green.
3. Add expenses summing to 800. The bar turns amber.
4. Add expenses past 1000. The bar turns red; "Dépassement" label appears.
5. Sign in (different browser) as a supervisor on that project. Their card shows the same totals.
6. **Cross-supervisor accuracy** — sign in as a second supervisor on the same project. Each adds 200/500 respectively. Both cards show `700 / 1000`, not just their own subtotal. (Validates the SECURITY DEFINER RPC.)
7. **Live budget edit** — open admin and supervisor in two browsers. Admin edits the budget. Supervisor's card updates within ~1s without reload.

---

## 10. Updating the schema later

When you change something:

1. Add a new file under `supabase/migrations/` named `YYYYMMDDHHMMSS_what_changed.sql`. Use `if not exists` / `on conflict` patterns to keep it idempotent.
2. Apply it via the SQL editor, exactly like Step 3.
3. Commit the file alongside any frontend changes.

For schema breakages or destructive changes, use Supabase's **Database → Backups** to take a snapshot first. Free-tier backups are point-in-time recovery for 7 days.

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Login screen says "Configuration missing" | You didn't replace `YOUR_SUPABASE_URL` / `YOUR_SUPABASE_ANON_KEY` | Step 5 above. |
| Sign-up succeeds but sign-in fails immediately | "Confirm email" is on, you haven't clicked the link | Check your inbox; or turn confirmation off in **Auth → Providers → Email**. |
| Magic-link email arrives but clicking it lands on an error page | Site URL or Redirect URL not configured | **Auth → URL Configuration** — add your origin. |
| Manage Users button never appears for the first admin | `claim_first_admin()` didn't fire (e.g. RPC blocked or migration #4 not applied) | Re-apply migration #4. Or in SQL editor: `update profiles set is_admin = true where id = (select id from auth.users where email = '...');`. |
| Inserting an expense returns 403 / "new row violates RLS" | You're a supervisor without a project assignment, or your project_id doesn't match the row's | Have an admin assign you to a project via the panel. |
| Receipt upload fails with 403 | Storage RLS rejected the path. Each receipt must live under your own UUID prefix | Make sure migration #3 was applied. The frontend builds the path correctly automatically. |
| `expenses` Realtime not firing | Realtime not enabled on the table | Check that migration #1 ran the line `alter publication supabase_realtime add table public.expenses;`. |
| Local file:// open shows blank page | Browsers refuse to load ES modules from `file://` | Use `python -m http.server 8000` (or any static server). |
| Production deploy works on desktop but mobile is stuck on old version | Service worker cache | Bump `CACHE = 'expenses-supabase-v1'` in `sw.js` to v2 (or any new value), redeploy. Users will get the new version on next visit. |

For anything not in this matrix, the Supabase **Logs** panel (Logs → API or Auth) usually shows the exact reason a request was rejected.
