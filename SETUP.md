# Setup Guide — Supabase Edition

End-to-end walkthrough for getting this app live. Total time: ~30 minutes the first time.

---

## Table of contents

1. [Prerequisites](#1-prerequisites)
2. [Create the Supabase project](#2-create-the-supabase-project)
3. [Run the SQL migrations](#3-run-the-sql-migrations)
4. [Configure auth (URLs and email)](#4-configure-auth-urls-and-email)
5. [Wire the frontend to the project](#5-wire-the-frontend-to-the-project)
6. [Run locally](#6-run-locally)
7. [Deploy as a static site](#7-deploy-as-a-static-site)
7.5. [Deploy the Edge Functions](#75-deploy-the-edge-functions)
8. [Bootstrap the first admin and lock down signups](#8-bootstrap-the-first-admin-and-lock-down-signups)
9. [Verify everything works](#9-verify-everything-works)
10. [Updating the schema later](#10-updating-the-schema-later)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Prerequisites

- A Supabase account (https://supabase.com — free tier is plenty: 500 MB DB, 1 GB storage, 50 K monthly active users).
- A GitHub account if you'll use the included Pages auto-deploy (recommended). The repo's `.github/workflows/deploy.yml` does the rest.
- Node.js installed locally **only if** you'll deploy Edge Functions via `npx supabase` (Step 7.5). Not needed for the static site.

You do **not** need Python, build tooling, or any framework — `index.html` ships ready to run.

---

## 2. Create the Supabase project

1. https://supabase.com/dashboard → **New project**.
2. Pick a name (e.g. `suivi-depenses`), pick a strong DB password (you won't usually use it directly), pick a region close to your users.
3. Wait ~2 minutes for provisioning. The dashboard shows a green dot when ready.

When it's up, note these two values from **Project Settings → API**:

- **Project URL** — looks like `https://abcdefghijkl.supabase.co`
- **anon public key** — a long JWT string starting with `eyJ...`

Both go into `index.html` later (Step 5). They are safe to commit because Row-Level Security policies (Step 3) protect the data, not the keys.

> ⚠️ Do **NOT** put the **service_role** key into `index.html`. That key bypasses RLS entirely. The two Edge Functions get it via Supabase env vars at runtime — that's the only place it should ever appear.

---

## 3. Run the SQL migrations

Open the **SQL editor** in the Supabase dashboard. For each file under `supabase/migrations/`, copy the full contents into a new query and click **Run**. Run them in filename order:

| Order | File | What it does |
|---|---|---|
| 1 | `20260101000001_schema.sql` | Creates `profiles`, `projects`, `expenses`. Wires triggers (auto-create profile on sign-up, auto-bump `updated_at`). Enables Realtime on `expenses`. |
| 2 | `20260101000002_rls.sql` | Enables RLS on every table and installs the policies (admins see all, supervisors see only their own project's rows). |
| 3 | `20260101000003_storage.sql` | Creates the `receipts` storage bucket and its RLS policies (a supervisor can only put/get files under their own UUID prefix). |
| 4 | `20260101000004_admin_helpers.sql` | Installs `set_user_admin`, `assign_user_project`, `claim_first_admin` RPCs that the admin panel calls. |
| 5 | `20260430000005_project_budgets.sql` | Adds budget columns to `projects`, the `get_project_summary()` aggregation RPC (SECURITY DEFINER), and adds `projects` to the realtime publication. |
| 6 | `20260430000006_expense_client_id.sql` | Adds `expenses.client_id` + unique partial index for offline INSERT idempotency. |
| 7 | `20260430000007_user_directory.sql` | Adds the `get_user_directory()` SECURITY DEFINER RPC the admin panel uses to show user emails + pending-invite status. |

Each migration is **idempotent** (uses `if not exists`, `on conflict`, `do $$ ... if not exists ... end$$`), so re-running them is safe.

After they're applied, check **Table editor** — you should see `profiles`, `projects`, `expenses` (all empty) and **Storage → Buckets** should list `receipts`.

---

## 4. Configure auth (URLs and email)

The app is **invite-only** in steady state. The flow below sets up the URL allowlist correctly the first time, then Step 8 hands over to the long-term lockdown configuration.

### Authentication → URL Configuration

- **Site URL**: where the app will be hosted, e.g. `https://your-username.github.io/SuiviDepenses-Supabase/` (with the trailing slash and the project subpath).
- **Redirect URLs**: add the same URL plus any localhost variants you'll use for development (`http://localhost:8000`, `http://localhost:5173`, etc.). All email-based auth flows (invite, password-reset, recovery) check this allowlist.

> The frontend always passes an explicit `redirectTo` derived from `window.location.origin + window.location.pathname` (per CLAUDE.md), so the Site URL fallback is rarely used in practice — but the allowlist above is still required.

### Authentication → Providers → Email

- **Enable email provider**: ON.
- **Confirm email**:
  - **Temporarily OFF** during the bootstrap (Step 8). Lets you sign up the first admin without an inbox round-trip.
  - **Optionally back ON** afterwards if you want extra security. Invited users still go through the magic-link flow regardless of this toggle.
- **Enable user signups**: ON for now. You'll flip this OFF in Step 8 once the first admin exists.

### Authentication → Email Templates (optional)

You can customize the FR text of the invite, password-reset, and recovery emails to match your team's language. Default English templates work fine if you skip this.

### Email rate limits (heads-up)

Supabase's built-in SMTP caps at ~3 emails/hour on the free tier. If you'll onboard more than a handful of users at once, configure custom SMTP under **Project Settings → SMTP Settings**. [Resend](https://resend.com) has a generous free tier and is the easiest plug-in.

---

## 5. Wire the frontend to the project

Open `index.html`. Find these two lines near the top of the `<script type="module">` block (around line 430):

```js
const SUPABASE_URL  = 'YOUR_SUPABASE_URL';
const SUPABASE_ANON = 'YOUR_SUPABASE_ANON_KEY';
```

Replace both with your project's values from Step 2. Commit and push.

> **Don't worry about leaking the anon key.** It's designed to be public — RLS policies are the real security. Anyone reading the key can only do what RLS allows for unauthenticated or authenticated users.

---

## 6. Run locally

A static file server is enough:

```bash
# Python 3 (built-in)
python -m http.server 8000

# Node (npx)
npx serve .
```

Open http://localhost:8000. The login overlay should appear. Most errors at this stage are typos in the URL/anon key from Step 5.

> **Auth redirects from email links won't land on localhost** unless `http://localhost:8000` is in the Redirect URLs allowlist (Step 4).

---

## 7. Deploy as a static site

### GitHub Pages (recommended — automated via Actions)

The repo includes `.github/workflows/deploy.yml`. On every push to `main`, the workflow:
1. Stages the runtime files (`index.html`, `manifest.json`, `sw.js`, `icons/`) into a `dist/` directory.
2. Replaces the `__VERSION__` placeholder in `sw.js` with the short Git SHA, so returning users automatically get the new build via the service-worker cache key change.
3. Auto-enables Pages with **Source: GitHub Actions** on first run (no manual UI step).
4. Uploads + deploys.

Steps:
1. Push the repo to a GitHub repository (public for free Pages, paid for private).
2. The first push to `main` runs the workflow.
3. Site URL becomes `https://<your-username>.github.io/<repo-name>/`. Add it to **Auth → URL Configuration → Site URL** and **Redirect URLs**.

> Do **not** edit the `__VERSION__` placeholder in `sw.js` — leave it as-is. CI substitutes at deploy time. The placeholder also works fine for local dev (acts as a stable cache key).

### Vercel / Netlify (alternative)

```bash
# Vercel — Import Git Repository, no build command, deploy.
# Netlify
npx netlify deploy --prod --dir=.
```

Whichever host you pick, **add the production URL to Supabase Auth → URL Configuration**.

---

## 7.5 Deploy the Edge Functions

The admin panel's "Invite by email" and "Delete user" features rely on two Supabase Edge Functions that wrap privileged GoTrue admin calls. Source lives at `supabase/functions/invite-user/index.ts` and `supabase/functions/delete-user/index.ts`.

Both follow the same pattern: CORS preflight → JWT verify → admin check via `profiles.is_admin` → service-role admin call. Self-protection (admins can't delete themselves) is enforced inside the function, not just the UI.

### Recommended: Supabase CLI (one command per function)

```bash
# One-time browser auth:
npx supabase@latest login

# Deploy both:
npx supabase@latest functions deploy invite-user --project-ref <your-project-ref>
npx supabase@latest functions deploy delete-user --project-ref <your-project-ref>
```

The CLI uploads the file directly off disk — no copy-paste, no editor truncation. The dashboard's paste-into-editor flow has historically caused subtle compile errors that the CLI avoids.

### Smoke test

```bash
# OPTIONS preflight should return 200 OK
curl -i -X OPTIONS https://<your-ref>.supabase.co/functions/v1/invite-user \
  -H "Origin: https://<your-domain>" -H "Access-Control-Request-Method: POST"

# Anonymous POST should return 401, NOT 500
curl -i -X POST https://<your-ref>.supabase.co/functions/v1/invite-user \
  -H "Content-Type: application/json" -d '{}'
```

If both pass for both functions, you're set.

### Troubleshooting

- **403 "Admin role required"** → the calling user isn't admin (Step 8 below).
- **400 "User already registered"** (invite) → that email is already in `auth.users`. Inspect with `select email from auth.users;`.
- **400 "Cannot delete your own account"** (delete) → self-protection. Switch to a different admin or do it via SQL.
- **OPTIONS|500 with "Unexpected end of JSON input"** → you deployed via the dashboard editor and it stripped or mangled the source. Redeploy via CLI.

The function logs at **Edge Functions → invite-user → Logs** show the actual GoTrue response for invite failures.

---

## 8. Bootstrap the first admin and lock down signups

### 8.1 Bootstrap (one-time)

1. Confirm **Auth → Providers → Email → Enable user signups** is **ON** (Step 4).
2. **Temporarily** turn off **Confirm email** (so the first signup doesn't need an inbox click).
3. Open the deployed app. The login screen has email + password + "Forgot password?" — sign-up isn't a tab anymore. To do the one-time bootstrap, run this from your browser DevTools console while on the login page:

   ```js
   await window.supabase.auth.signUp({ email: 'you@example.com', password: 'choose-a-strong-one' })
   ```

   The frontend's `claim_first_admin()` RPC fires on every login; since there are zero admins, it promotes you immediately.

4. Refresh the page. Sign in with the credentials you just set. The **Manage Users** button should appear in the header.

### 8.2 Lock down (mandatory)

Right after the first sign-in succeeds:

1. **Auth → Providers → Email → Enable user signups → OFF**. Critical: without this, anyone with the anon key can still call `auth.signUp()` from DevTools. UI removal alone is not security.
2. Optionally re-enable **Confirm email** if you want extra rigor.

From now on, `claim_first_admin()` is a no-op (returns false unless zero admins exist), and new accounts arrive only via **Manage Users → Invite by email**. Safe to leave both knobs in production permanently.

---

## 9. Verify everything works

Run through these checklists as the first admin.

### 9.1 Core flow

1. **Manage Users → Projects** → add a project (e.g. "Villa Tower"). Set Budget = 1000 / Alert = 80, Save.
2. The project name appears in the header (admin's project dropdown auto-assigns themselves to the only project).
3. Add an expense via the form. It shows up in the list immediately.
4. Attach a receipt photo (any image ≤5 MB). Click the 📎 icon to verify it opens.
5. **Invite a second user** via Manage Users → Invite by email. Recipient gets a magic-link email; they click → "Welcome — choose your password" overlay → set password → enter the app. The Users list now shows them with a **Pending** badge until first sign-in.
6. Assign the new user to the project via the dropdown.
7. As that supervisor, add an expense. **In the admin's still-open browser**, the new row appears within ~1 second without a reload — that's Realtime working.
8. As the supervisor, try to access another project's data via DevTools → Network: the response is empty (RLS blocks it).

### 9.2 Budget feature

1. As admin, on the home screen the **Budget** card shows `0 / 1000` in green.
2. Add expenses summing to 800 → bar turns amber.
3. Add expenses past 1000 → bar turns red, "Dépassement" / "Over budget" label appears.
4. **Cross-supervisor accuracy** — sign in as a second supervisor on the same project. Each adds 200/500 respectively. Both cards show `700 / 1000`, not just their own subtotal. (Validates the SECURITY DEFINER RPC.)
5. **Live budget edit** — open admin and supervisor in two browsers. Admin edits the budget. Supervisor's card updates within ~1s without reload.

### 9.3 Offline writes

1. DevTools → **Application → Service workers → Offline** (or Network tab → Offline).
2. Add 5 expenses via the form. Each row appears faded with 🕒. Pill reads `Hors ligne (5 en attente)`.
3. Uncheck Offline. Rows settle (full opacity, no clock) within ~1s. Pill returns to `En ligne`.
4. Add an expense with a receipt photo while offline. Toggle online. Receipt uploads after the row sync.
5. While offline, edit / delete an existing expense. Optimistic update visible. Settles on reconnect.
6. Demote a user mid-offline-session, then have them replay. Rejected ops surface with ⚠️ and a Retry option.
7. Force-quit the browser tab while ops are queued. Re-open. Queue persists, drains on reconnect.

### 9.4 Admin user management

1. **Invite by email** with a fresh address → recipient receives email → clicks link → sets password → lands in app. Confirms `invite-user` Edge Function works end-to-end.
2. **Delete a user** from the Users list. Confirmation prompt mentions their email. Confirms `delete-user` Edge Function works; their expenses + receipts are removed.
3. Try to delete yourself → button is disabled. Try via DevTools (`supabase.functions.invoke('delete-user', { body: { user_id: '<your-id>' } })`) → 400 "Cannot delete your own account". Self-protection works at both layers.

### 9.5 Password recovery

1. Sign out. Click **Forgot password?** with your email. Email arrives.
2. Click the link → lands on app with the **"Set a new password"** overlay (NOT signed in normally).
3. Set a new password → toast confirms → you're signed in normally.

If all five sections pass, you're production-ready.

---

## 10. Updating the schema later

When you change something:

1. Add a new file under `supabase/migrations/` named `YYYYMMDDHHMMSS_what_changed.sql`. Use `if not exists` / `on conflict` / `do $$ ... if not exists ... end$$` patterns to keep it idempotent.
2. Apply it via the SQL editor (or `npx supabase db push` if you've linked the project).
3. Commit the file alongside any frontend changes.

For Edge Function changes, redeploy via `npx supabase functions deploy <name>`. The Pages workflow auto-deploys frontend changes on every push to `main`.

For schema breakages or destructive changes, use Supabase's **Database → Backups** to take a snapshot first. Free-tier backups are point-in-time recovery for 7 days.

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Login screen says "Configuration missing" | You didn't replace `YOUR_SUPABASE_URL` / `YOUR_SUPABASE_ANON_KEY` | Step 5 above. |
| Email link redirects to bare origin (e.g. `bomino.github.io/` instead of `bomino.github.io/SuiviDepenses-Supabase/`) | The link was generated before the Site URL config was saved, OR a code call dropped the `redirectTo`. | Save the correct Site URL + Redirect URLs (Step 4), then resend the email. The frontend already passes explicit `redirectTo` everywhere — see CLAUDE.md "Auth email redirects" for the convention. |
| Email rate limit exceeded | Supabase built-in SMTP caps at ~3/hour on free tier | Wait an hour, or configure custom SMTP (Resend, etc.) under **Project Settings → SMTP Settings**. |
| Manage Users button never appears for the first admin | `claim_first_admin()` didn't fire | Re-apply migration #4. Or in SQL editor: `update profiles set is_admin = true where id = (select id from auth.users where email = '...');`. |
| Inserting an expense returns 403 / "new row violates RLS" | You're a supervisor without a project assignment | Have an admin assign you to a project via the panel. |
| Receipt upload fails with 403 | Storage RLS rejected the path | Make sure migration #3 was applied. The frontend builds the path correctly automatically. |
| `expenses` Realtime not firing | Realtime not enabled on the table | Migration #1 must have run `alter publication supabase_realtime add table public.expenses;`. Migration #5 does the same for `projects`. |
| Live budget edits don't propagate | `projects` not in the realtime publication | Re-apply migration #5; verify with `select tablename from pg_publication_tables where pubname='supabase_realtime';`. |
| Edge Function returns OPTIONS\|500 with "Unexpected end of JSON input" | Function source got truncated by a paste into the dashboard editor | Redeploy via `npx supabase functions deploy <name>`. |
| Edge Function logs show "Admin role required" | The caller isn't admin in `profiles` | `update public.profiles set is_admin = true where id = '<user-uuid>';` for legitimate admins. |
| Local `file://` open shows blank page | Browsers refuse to load ES modules from `file://` | Use `python -m http.server 8000` (or any static server). |
| Production deploy works on desktop but mobile is stuck on old version | Service worker cache | Should not happen if Pages auto-deploy is in use (CI bumps `__VERSION__` per commit). If it does, force-clear: DevTools → Application → Storage → Clear site data, then reload. |

For anything not in this matrix, **Edge Functions → Logs** and **Logs → API / Auth** in the Supabase dashboard usually show the exact reason a request was rejected.
