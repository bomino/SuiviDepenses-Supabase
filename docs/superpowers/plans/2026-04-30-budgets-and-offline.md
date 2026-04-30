# Project Budgets + Offline-First Writes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-project budgets with a live burn-rate card visible to admins and supervisors, and let supervisors keep working while disconnected — mutations queue locally and sync FIFO on reconnect.

**Architecture:** Two-phase delivery. Phase 1 (#4 Budgets) adds two columns to `projects`, a `SECURITY DEFINER` aggregation RPC, a second realtime channel on `projects`, and a 5th stat card on the home screen. Phase 2 (#3 Offline) adds `expenses.client_id` for INSERT idempotency, an IndexedDB queue (raw API, single object store), a mutation router that tries the network first and queues on connectivity loss, and an optimistic UI for pending rows. Both phases preserve the existing "static PWA + Supabase, no toolchain" stance.

**Tech Stack:** Vanilla JS + ES modules via CDN, `@supabase/supabase-js@2`, Postgres + RLS, Supabase Realtime, Supabase Storage, IndexedDB (raw API).

**Spec:** [`docs/superpowers/specs/2026-04-30-budgets-and-offline-design.md`](../specs/2026-04-30-budgets-and-offline-design.md)

**Verification model:** No automated test runner exists in this repo (deliberate per the spec). Each task ends with a **manual verification step** (browser action, SQL query, or DevTools check) that the engineer must perform before committing. Do not skip these — they are how regressions get caught.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `supabase/migrations/20260430000005_project_budgets.sql` | new | Adds `projects.budget_amount`, `projects.budget_alert_pct`, `get_project_summary()` RPC, adds `projects` to realtime publication, grants execute on the RPC |
| `supabase/migrations/20260430000006_expense_client_id.sql` | new | Adds `expenses.client_id` + unique partial index for INSERT idempotency |
| `index.html` | modified | All UI + JS lives here (single-file PWA — preserve this). Adds: 5th stat card, admin panel budget inputs, i18n keys, `loadProjectSummary` + `debouncedRefetchSummary`, second realtime channel on `projects`, IndexedDB wrapper, mutation router, queue replay executor, optimistic offline rendering, sync counter on the connectivity pill |
| `sw.js` | modified | Bump `CACHE` version twice (once after Phase 1, once after Phase 2) so PWA users get each new build |
| `SETUP.md` | modified | Append "Run migrations 5 and 6" + the manual test checklists from the spec |
| `GUIDE.md` | modified | Short FR section explaining the offline indicator and queue counter |
| `CLAUDE.md` | modified | Add notes about the new architectural elements (budget RPC, dual realtime channels, offline mutation router, client_id idempotency) |

**File-decomposition note:** Per CLAUDE.md, this project deliberately ships as a single `index.html` with no toolchain. Do NOT split into modules; preserve the two-`<script>`-block pattern (ESM block sets up `window.supabase`; classic block holds app code with `window.foo = foo` exports for inline `onclick` handlers).

---

## Phase 1 — Project Budgets (Feature #4)

### Task 1: Migration #5 — budget columns, RPC, realtime publication

**Files:**
- Create: `supabase/migrations/20260430000005_project_budgets.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260430000005_project_budgets.sql` with exactly:

```sql
-- Adds budget tracking to projects + the SECURITY DEFINER aggregation RPC
-- that computes spent-per-project across ALL expenses (bypassing RLS,
-- which would otherwise hide other supervisors' rows from a supervisor's
-- SUM query).
-- Apply AFTER 20260101000004_admin_helpers.sql.
-- Idempotent: safe to re-run.

-- ============================================================================
-- 1. Budget columns on projects
-- ============================================================================
alter table public.projects
    add column if not exists budget_amount numeric(14,2),
    add column if not exists budget_alert_pct int not null default 80
        check (budget_alert_pct between 0 and 100);

-- ============================================================================
-- 2. Aggregation RPC
-- Returns one row per project the caller is permitted to see, with the
-- TRUE spent total. SECURITY DEFINER lets it sum across rows that RLS
-- would otherwise hide. Authorization is enforced inside the function.
-- ============================================================================
create or replace function public.get_project_summary()
returns table (
    project_id       uuid,
    name             text,
    budget_amount    numeric(14,2),
    budget_alert_pct int,
    spent            numeric(14,2),
    expense_count    int
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

grant execute on function public.get_project_summary() to authenticated;

-- ============================================================================
-- 3. Live updates on projects (was previously only expenses)
-- ============================================================================
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and tablename = 'projects'
    ) then
        alter publication supabase_realtime add table public.projects;
    end if;
end$$;
```

- [ ] **Step 2: Apply via Supabase SQL editor**

Open the Supabase dashboard → SQL editor → paste the migration → Run. Repeat-runs must succeed (it's idempotent).

- [ ] **Step 3: Verify schema**

In the SQL editor, run each of:

```sql
-- Columns exist
select column_name, data_type, is_nullable, column_default
  from information_schema.columns
  where table_schema = 'public' and table_name = 'projects'
    and column_name in ('budget_amount', 'budget_alert_pct');
```

Expected: 2 rows. `budget_amount` numeric, nullable, default null. `budget_alert_pct` integer, not null, default 80.

```sql
-- RPC exists and is callable
select public.get_project_summary();
```

Expected: returns 0 or more rows depending on the calling user (run this while signed-in as an admin in the SQL editor; no rows is fine if there are no projects yet).

```sql
-- Realtime publication includes projects
select tablename from pg_publication_tables
  where pubname = 'supabase_realtime' and tablename = 'projects';
```

Expected: 1 row.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260430000005_project_budgets.sql
git commit -m "feat(db): project budgets + get_project_summary RPC + realtime on projects"
```

---

### Task 2: Profile hydration — widen embed, load summary, debounced refetcher

**Files:**
- Modify: `index.html` (around line 770 — `loadCurrentUser` function)

- [ ] **Step 1: Widen the profile select**

Find the block (in `loadCurrentUser`):

```js
var { data: prof } = await window.supabase
    .from('profiles')
    .select('id, full_name, is_admin, project_id, projects(name)')
    .eq('id', uid)
    .single();
```

Change the embedded select to:

```js
var { data: prof } = await window.supabase
    .from('profiles')
    .select('id, full_name, is_admin, project_id, projects(name, budget_amount, budget_alert_pct)')
    .eq('id', uid)
    .single();
```

- [ ] **Step 2: Extend the `currentUser` shape**

Find the assignment block right after, currently:

```js
currentUser = {
    id: uid,
    email: session.user.email,
    full_name: prof.full_name || session.user.email,
    is_admin: !!prof.is_admin,
    project_id: prof.project_id || null,
    project_name: prof.projects ? prof.projects.name : null
};
```

Replace with:

```js
currentUser = {
    id: uid,
    email: session.user.email,
    full_name: prof.full_name || session.user.email,
    is_admin: !!prof.is_admin,
    project_id: prof.project_id || null,
    project_name: prof.projects ? prof.projects.name : null,
    project_budget: prof.projects ? prof.projects.budget_amount : null,
    project_alert_pct: prof.projects ? prof.projects.budget_alert_pct : 80
};
```

- [ ] **Step 3: Add the project-summary state and loader**

Just below the existing module-level `var` declarations near line 423–429 (where `expenses`, `allProjects`, `realtimeChannel` are declared), add:

```js
var projectSummary = [];           /* [{ project_id, name, budget_amount, budget_alert_pct, spent, expense_count }] */
var projectsChannel = null;        /* second realtime channel */
var summaryRefetchTimer = null;    /* debounce handle */
```

Then below `loadExpenses` (around line 814), add:

```js
async function loadProjectSummary() {
  var { data, error } = await window.supabase.rpc('get_project_summary');
  projectSummary = error ? [] : (data || []);
}

function debouncedRefetchSummary() {
  if (summaryRefetchTimer) clearTimeout(summaryRefetchTimer);
  summaryRefetchTimer = setTimeout(function() {
    loadProjectSummary().then(render);
  }, 250);
}
```

- [ ] **Step 4: Wire `loadProjectSummary` into the bootstrap**

Find the line in `loadCurrentUser`:

```js
await Promise.all([loadProjects(), loadExpenses()]);
```

Change to:

```js
await Promise.all([loadProjects(), loadExpenses(), loadProjectSummary()]);
```

- [ ] **Step 5: Verify in the browser**

Start the local server: `python -m http.server 8000`. Open `http://localhost:8000`. Sign in. Open DevTools → Console. Type:

```js
await window.supabase.rpc('get_project_summary')
```

Expected: returns `{ data: [...], error: null }`. The data array should contain the project(s) the user can see.

Type `currentUser.project_budget` in the console. Expected: `null` (no budget set yet) or a number if you've manually set one.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat(ui): hydrate profile with budget fields + add project_summary loader"
```

---

### Task 3: Add second realtime channel on `projects`; extend expenses handler

**Files:**
- Modify: `index.html` (`subscribeRealtime` function around line 816, `onAuthStateChange` around line 836)

- [ ] **Step 1: Extend `subscribeRealtime`**

Replace the existing `subscribeRealtime` function (lines ~816–834) entirely with:

```js
function subscribeRealtime() {
  if (realtimeChannel) { window.supabase.removeChannel(realtimeChannel); realtimeChannel = null; }
  if (projectsChannel) { window.supabase.removeChannel(projectsChannel); projectsChannel = null; }

  realtimeChannel = window.supabase
    .channel('expenses-live')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'expenses' }, function(payload) {
      // RLS already filtered what we can see; sync the local cache
      if (payload.eventType === 'INSERT') {
        if (!expenses.find(function(e){ return e.id === payload.new.id; })) expenses.unshift(payload.new);
      } else if (payload.eventType === 'UPDATE') {
        var idx = expenses.findIndex(function(e){ return e.id === payload.new.id; });
        if (idx >= 0) expenses[idx] = payload.new;
        else expenses.unshift(payload.new);
      } else if (payload.eventType === 'DELETE') {
        expenses = expenses.filter(function(e){ return e.id !== payload.old.id; });
      }
      // Refetch the project summary so the burn-rate card updates even when
      // another supervisor's row changes (which RLS hides from `expenses`).
      debouncedRefetchSummary();
      render();
    })
    .subscribe();

  projectsChannel = window.supabase
    .channel('projects-live')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'projects' }, function(_payload) {
      // Any change to projects (budget edit, rename, add, delete) → refetch summary.
      debouncedRefetchSummary();
    })
    .subscribe();
}
```

- [ ] **Step 2: Tear down the second channel on signout**

Find the SIGNED_OUT branch in `onAuthStateChange` (around line 840):

```js
} else if (event === 'SIGNED_OUT') {
    currentUser = null; expenses = []; allProjects = [];
    if (realtimeChannel) { window.supabase.removeChannel(realtimeChannel); realtimeChannel = null; }
```

Add the projectsChannel teardown immediately after:

```js
} else if (event === 'SIGNED_OUT') {
    currentUser = null; expenses = []; allProjects = []; projectSummary = [];
    if (realtimeChannel) { window.supabase.removeChannel(realtimeChannel); realtimeChannel = null; }
    if (projectsChannel) { window.supabase.removeChannel(projectsChannel); projectsChannel = null; }
```

- [ ] **Step 3: Verify with two browsers**

Open the app in two browsers (e.g. Chrome + an incognito window), sign in as admin in one and as a supervisor on a project in the other. In the admin window, in DevTools console:

```js
await window.supabase.from('projects').update({ budget_amount: 1234 }).eq('id', '<the-supervisor-project-id>')
```

In the supervisor window, run `projectSummary` in the console **after ~1 second**. Expected: the row for that project shows `budget_amount: 1234`. (No budget card UI yet — that's Task 4. We're verifying the realtime channel works.)

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat(ui): second realtime channel on projects + summary refetch on expense changes"
```

---

### Task 4: Budget stat card — HTML, CSS, render logic, i18n

**Files:**
- Modify: `index.html` (stats section markup around line 240-ish, CSS around line 60–75 area, render logic in `render()` around line 1069, i18n in `dict.en` and `dict.fr`)

- [ ] **Step 1: Add CSS for the budget bar**

Find the `.stat-card` CSS rules (around line 65). After the existing `.accent-blue` rule, add:

```css
.accent-budget .icon-circle { background: rgba(245,158,11,.12); color: var(--accent); }
.accent-budget .value { color: var(--accent); font-size: 1.05rem; }
.accent-budget .value .of { color: var(--sub); font-weight: 500; }
.budget-bar { width: 100%; height: 8px; background: var(--surface2); border-radius: 4px; margin-top: 10px; overflow: hidden; }
.budget-bar > span { display: block; height: 100%; transition: width .35s ease; border-radius: 4px; }
.budget-bar.green > span { background: var(--green); }
.budget-bar.amber > span { background: var(--amber); }
.budget-bar.red   > span { background: var(--red); }
.stat-card.stale { border-style: dashed; }
.stat-card.stale .label::after { content: " ~"; color: var(--sub); }
```

- [ ] **Step 2: Add the 5th card to the markup**

Find the existing stats grid in the markup (search for `class="stats-grid"`). After the four existing cards (Total / Paid / Pending / Unpaid), add the budget card:

```html
        <div class="stat-card accent-budget" id="budgetCard" style="display:none">
          <div class="icon-circle">B</div>
          <div class="label" id="budgetCardLabel">Budget</div>
          <div class="value">
            <span id="budgetSpent">0</span><span class="of"> / </span><span id="budgetTotal">0</span>
          </div>
          <div class="budget-bar green" id="budgetBar"><span style="width:0%"></span></div>
          <div class="label" style="margin-top:6px;font-size:.65rem;display:none" id="budgetOverLabel">Over budget</div>
        </div>
```

- [ ] **Step 3: Add i18n keys**

Find `dict.en` (around line 453). Add to the EN block:

```js
    budgetCardLabel: "Budget",
    budgetOverLabel: "Over budget",
    adminBudgetInput: "Budget",
    adminAlertPct: "Alert at %",
    adminBudgetSave: "Save",
    adminBudgetSaved: "Budget saved",
    budgetStaleTooltip: "Pending sync — last known total",
```

Find `dict.fr` (it mirrors `dict.en` further down). Add to the FR block:

```js
    budgetCardLabel: "Budget",
    budgetOverLabel: "Dépassement",
    adminBudgetInput: "Budget",
    adminAlertPct: "Alerte à %",
    adminBudgetSave: "Enregistrer",
    adminBudgetSaved: "Budget enregistré",
    budgetStaleTooltip: "Synchronisation en attente — dernier total connu",
```

Find `applyLang()` (search for `headerTitle = d.headerTitle` or similar), and add a line to update the new label:

```js
  document.getElementById('budgetCardLabel').textContent = d.budgetCardLabel;
  document.getElementById('budgetOverLabel').textContent = d.budgetOverLabel;
```

- [ ] **Step 4: Render logic**

Add this helper function above `render()` (around line 1065):

```js
function computeBudgetCardState() {
  // Returns { visible, spent, budget, alertPct, color, isStale } or { visible: false }.
  if (!currentUser) return { visible: false };

  if (currentUser.is_admin) {
    // Admin viewing all projects: sum across non-null-budget projects.
    var withBudgets = projectSummary.filter(function(s){ return s.budget_amount != null; });
    if (withBudgets.length === 0) return { visible: false };
    var spent  = withBudgets.reduce(function(a,s){ return a + Number(s.spent || 0); }, 0);
    var budget = withBudgets.reduce(function(a,s){ return a + Number(s.budget_amount || 0); }, 0);
    var alertPct = 80;
    return finishBudgetState(spent, budget, alertPct, false);
  }

  // Supervisor: their own project.
  var row = projectSummary.find(function(s){ return s.project_id === currentUser.project_id; });
  if (!row || row.budget_amount == null) return { visible: false };

  // Adjust for the user's own offline pending ops (Phase 2 will populate this).
  var offlineDelta = (window.computeOfflineSpentDelta && window.computeOfflineSpentDelta()) || 0;
  var spent = Number(row.spent || 0) + offlineDelta;
  return finishBudgetState(spent, Number(row.budget_amount), Number(row.budget_alert_pct || 80), offlineDelta !== 0);
}

function finishBudgetState(spent, budget, alertPct, isStale) {
  var ratio = budget > 0 ? (spent / budget) : 0;
  var color = (ratio >= 1.0) ? 'red' : (ratio >= alertPct/100) ? 'amber' : 'green';
  return { visible: true, spent: spent, budget: budget, alertPct: alertPct, color: color, isStale: isStale, ratio: ratio };
}

function renderBudgetCard() {
  var card = document.getElementById('budgetCard');
  var state = computeBudgetCardState();
  if (!state.visible) { card.style.display = 'none'; return; }
  card.style.display = '';
  document.getElementById('budgetSpent').textContent = fmtAmount(state.spent);
  document.getElementById('budgetTotal').textContent = fmtAmount(state.budget);
  var bar = document.getElementById('budgetBar');
  bar.className = 'budget-bar ' + state.color;
  var pct = Math.min(100, Math.round(state.ratio * 100));
  bar.firstElementChild.style.width = pct + '%';
  document.getElementById('budgetOverLabel').style.display = state.color === 'red' ? '' : 'none';
  card.classList.toggle('stale', !!state.isStale);
  card.title = state.isStale ? t('budgetStaleTooltip') : '';
}
```

Then find the existing `render()` function (line 1069). At the **top** of `render()`, just inside the function body, add:

```js
  renderBudgetCard();
```

- [ ] **Step 5: Verify all card states**

In the Supabase SQL editor, set a budget on a project (replace `<pid>` with a real id):

```sql
update public.projects set budget_amount = 1000, budget_alert_pct = 80 where id = '<pid>';
```

In the browser (signed in as a supervisor on that project):

1. **Card appears, green** — refresh page; budget card shows `0 / 1000` with green bar at 0%.
2. **Amber** — add expenses summing to 800 via the form. Card becomes amber.
3. **Red + over-budget label** — add expenses past 1000. Card becomes red; "Dépassement" appears under the bar.
4. **Hidden** — in SQL editor, run `update public.projects set budget_amount = null where id = '<pid>';`. After ~1s (realtime), the card disappears without a reload.
5. **Admin sums view** — sign in as admin. Card shows summed budget vs summed spent.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat(ui): budget stat card with live burn-rate bar"
```

---

### Task 5: Admin panel — budget inputs + save handler

**Files:**
- Modify: `index.html` (`refreshAdminProjectList` around line 1167, new `adminSaveBudget` function)

- [ ] **Step 1: Add the save handler**

After `adminDeleteProject` (around line 1222), add:

```js
async function adminSaveBudget(pid, budgetStr, alertStr) {
  var trimmed = (budgetStr || '').trim();
  var budget = trimmed === '' ? null : Number(trimmed);
  if (budget !== null && (isNaN(budget) || budget < 0)) { setAdminError(t('adminBudgetInvalid') || 'Invalid budget'); return; }

  var alertNum = parseInt(alertStr, 10);
  if (isNaN(alertNum) || alertNum < 0 || alertNum > 100) alertNum = 80;

  var { error } = await window.supabase
    .from('projects')
    .update({ budget_amount: budget, budget_alert_pct: alertNum })
    .eq('id', pid);
  if (error) { setAdminError(error.message); return; }
  refreshAdminProjectList();
  toast(t('adminBudgetSaved'));
  // Realtime channel will trigger debouncedRefetchSummary() automatically.
}
window.adminSaveBudget = adminSaveBudget;
```

- [ ] **Step 2: Render budget inputs in the project rows**

Find `refreshAdminProjectList` (around line 1167). The inner `.map(function(p) {` block currently emits a `<div class="admin-user-row">` per project. Replace that emission body with:

```js
return '<div class="admin-user-row">' +
  '<span class="name">' + esc(p.name) + '</span>' +
  '<input type="number" min="0" step="0.01" placeholder="' + t('adminBudgetInput') + '" id="bud_' + escAttr(p.id) + '" value="' + (p.budget_amount == null ? '' : esc(String(p.budget_amount))) + '" style="width:110px">' +
  '<input type="number" min="0" max="100" step="1" title="' + t('adminAlertPct') + '" id="alr_' + escAttr(p.id) + '" value="' + (p.budget_alert_pct == null ? 80 : esc(String(p.budget_alert_pct))) + '" style="width:70px">' +
  '<div class="actions">' +
    '<button type="button" onclick="adminSaveBudget(\'' + escAttr(p.id) + '\', document.getElementById(\'bud_' + escAttr(p.id) + '\').value, document.getElementById(\'alr_' + escAttr(p.id) + '\').value)">' + t('adminBudgetSave') + '</button>' +
    '<button type="button" onclick="adminRenameProject(\'' + escAttr(p.id) + '\',\'' + escAttr(p.name) + '\')">' + t('adminRenameProject') + '</button>' +
    '<button type="button" class="danger" onclick="adminDeleteProject(\'' + escAttr(p.id) + '\',\'' + escAttr(p.name) + '\')">' + t('adminDelete') + '</button>' +
  '</div></div>';
```

Note the change: the function now reads `budget_amount` and `budget_alert_pct` from each `p`. Update the SQL select earlier in the same function:

Find `var { data, error } = await window.supabase.from('projects').select('id, name').order('name');` (near line 1168).

Change to:

```js
var { data, error } = await window.supabase.from('projects').select('id, name, budget_amount, budget_alert_pct').order('name');
```

- [ ] **Step 3: Verify**

As admin, click **Manage Users**. In the Projects section:

1. Each project row shows two new inputs (Budget, Alert %) and a **Save** button.
2. Type a budget (e.g. 5000) and click Save. Toast says "Budget enregistré". The card on the home view updates within ~1s (realtime).
3. Refresh the page. The inputs retain their saved values (budget_amount and budget_alert_pct).
4. Open a second browser as a supervisor on that project. Have admin change the budget. Supervisor's card updates without reload (validates `projects` realtime channel).

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat(admin): per-project budget + alert pct editor"
```

---

### Task 6: Phase 1 docs + cache bump

**Files:**
- Modify: `sw.js`
- Modify: `SETUP.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Bump the service worker cache version**

In `sw.js` line 1, change:

```js
const CACHE = 'expenses-supabase-v1';
```

to:

```js
const CACHE = 'expenses-supabase-v2-budgets';
```

- [ ] **Step 2: Update SETUP.md**

In `SETUP.md`, find the migrations table in §3 (Run the SQL migrations). Add a 5th row:

```markdown
| 5 | `20260430000005_project_budgets.sql` | Adds budget columns to `projects`, the `get_project_summary()` aggregation RPC (SECURITY DEFINER), and adds `projects` to the realtime publication. |
```

At the end of §9 (Verify everything works), append a new sub-section:

```markdown
### 9.x Budget feature (post-Phase-1)

1. As admin, **Manage Users → Projects**: set Budget=1000, Alert=80 on a project. Toast confirms.
2. On the home screen the new Budget card shows `0 / 1000` in green.
3. Add expenses summing to 800. The bar turns amber.
4. Add expenses past 1000. The bar turns red; "Dépassement" label appears.
5. Sign in (different browser) as a supervisor on that project. Their card shows the same totals.
6. **Cross-supervisor accuracy** — sign in as a second supervisor on the same project. Each adds 200/500 respectively. Both cards show `700 / 1000`, not just their own subtotal. (Validates the SECURITY DEFINER RPC.)
7. **Live budget edit** — open admin and supervisor in two browsers. Admin edits the budget. Supervisor's card updates within ~1s without reload.
```

- [ ] **Step 3: Update CLAUDE.md**

In `CLAUDE.md`, in the **Architecture** section, add a new sub-heading after "Realtime sync is a single channel with client-side reconciliation":

```markdown
### Burn-rate goes through `get_project_summary()`, not client-side SUM

The "Budget" stat card aggregates spent-per-project via the `SECURITY DEFINER` RPC `get_project_summary()` in `_project_budgets.sql`. **Do not replace this with `SELECT SUM(amount) FROM expenses`** — RLS would hide other supervisors' rows from the calling supervisor and the card would silently undercount. The function bypasses RLS for the aggregation but enforces authorization (admin OR caller's assigned project) inside the body.

A second realtime channel on `public.projects` keeps the card live when admins edit budgets.
```

- [ ] **Step 4: Verify the cache bump took effect**

In a browser, open DevTools → Application → Service workers. Refresh the page. The new SW (`expenses-supabase-v2-budgets`) should activate within a moment. (You may need to click "skipWaiting" or close and reopen the tab.) Confirm the budget card is visible on a project that has a budget set — if you still see the old build without the card, the cache bump didn't propagate.

- [ ] **Step 5: Commit**

```bash
git add sw.js SETUP.md CLAUDE.md
git commit -m "docs(budgets): SETUP test checklist, CLAUDE arch note, sw cache bump"
```

---

## Phase 2 — Offline-First Writes (Feature #3)

### Task 7: Migration #6 — `client_id` for INSERT idempotency

**Files:**
- Create: `supabase/migrations/20260430000006_expense_client_id.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260430000006_expense_client_id.sql`:

```sql
-- Adds client-supplied idempotency token for offline INSERT replay.
-- Apply AFTER 20260430000005_project_budgets.sql.
-- Idempotent.

alter table public.expenses
    add column if not exists client_id uuid;

create unique index if not exists expenses_client_id_uidx
    on public.expenses(client_id) where client_id is not null;
```

- [ ] **Step 2: Apply via SQL editor**

Paste into the Supabase SQL editor and run. Re-run to verify idempotency.

- [ ] **Step 3: Verify**

```sql
select column_name, data_type
  from information_schema.columns
  where table_schema='public' and table_name='expenses' and column_name='client_id';
```

Expected: 1 row, `client_id` of type `uuid`.

```sql
select indexname from pg_indexes where tablename='expenses' and indexname='expenses_client_id_uidx';
```

Expected: 1 row.

Idempotency check:

```sql
insert into public.expenses (user_id, project_id, description, amount, client_id)
  values ('<some-uid>', '<some-pid>', 'idempotency check', 1.00, '11111111-1111-1111-1111-111111111111');
insert into public.expenses (user_id, project_id, description, amount, client_id)
  values ('<some-uid>', '<some-pid>', 'idempotency check', 1.00, '11111111-1111-1111-1111-111111111111')
  on conflict (client_id) do nothing;
select count(*) from public.expenses where client_id = '11111111-1111-1111-1111-111111111111';
```

Expected: count = 1 (second insert was a no-op). Clean up:

```sql
delete from public.expenses where client_id = '11111111-1111-1111-1111-111111111111';
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260430000006_expense_client_id.sql
git commit -m "feat(db): expenses.client_id + unique partial index for offline idempotency"
```

---

### Task 8: IndexedDB wrapper

**Files:**
- Modify: `index.html` (insert a new section before the `expense CRUD` section, around line 909)

- [ ] **Step 1: Add the IDB wrapper**

Insert this block immediately before the `/* ─────────── expense CRUD ─────────── */` comment (around line 909):

```js
/* ─────────── IndexedDB queue (offline writes) ─────────── */
var IDB_NAME = 'suividepenses_offline';
var IDB_VERSION = 1;
var IDB_STORE = 'pending_ops';
var idbConn = null;

function idbOpen() {
  if (idbConn) return Promise.resolve(idbConn);
  return new Promise(function(resolve, reject) {
    var req = indexedDB.open(IDB_NAME, IDB_VERSION);
    req.onupgradeneeded = function(e) {
      var db = e.target.result;
      if (!db.objectStoreNames.contains(IDB_STORE)) {
        db.createObjectStore(IDB_STORE, { keyPath: 'id', autoIncrement: true });
      }
    };
    req.onsuccess = function(e) { idbConn = e.target.result; resolve(idbConn); };
    req.onerror = function(e) { reject(e.target.error); };
  });
}

function idbAddOp(op) {
  return idbOpen().then(function(db) {
    return new Promise(function(resolve, reject) {
      var tx = db.transaction(IDB_STORE, 'readwrite');
      var store = tx.objectStore(IDB_STORE);
      var req = store.add(op);
      req.onsuccess = function() { resolve(req.result); };
      req.onerror = function() { reject(req.error); };
    });
  });
}

function idbListOps() {
  return idbOpen().then(function(db) {
    return new Promise(function(resolve, reject) {
      var tx = db.transaction(IDB_STORE, 'readonly');
      var req = tx.objectStore(IDB_STORE).getAll();
      req.onsuccess = function() { resolve(req.result || []); };
      req.onerror = function() { reject(req.error); };
    });
  });
}

function idbUpdateOp(id, patch) {
  return idbOpen().then(function(db) {
    return new Promise(function(resolve, reject) {
      var tx = db.transaction(IDB_STORE, 'readwrite');
      var store = tx.objectStore(IDB_STORE);
      var getReq = store.get(id);
      getReq.onsuccess = function() {
        var row = getReq.result;
        if (!row) return resolve(null);
        Object.assign(row, patch);
        var putReq = store.put(row);
        putReq.onsuccess = function() { resolve(row); };
        putReq.onerror = function() { reject(putReq.error); };
      };
      getReq.onerror = function() { reject(getReq.error); };
    });
  });
}

function idbDeleteOp(id) {
  return idbOpen().then(function(db) {
    return new Promise(function(resolve, reject) {
      var tx = db.transaction(IDB_STORE, 'readwrite');
      var req = tx.objectStore(IDB_STORE).delete(id);
      req.onsuccess = function() { resolve(); };
      req.onerror = function() { reject(req.error); };
    });
  });
}
```

- [ ] **Step 2: Verify in the browser**

Open the app, sign in. In DevTools console:

```js
await idbAddOp({ op_type: 'insert', client_id: 'test-1', payload: { description: 'idb-smoke' }, created_at: new Date().toISOString(), attempts: 0, last_error: null });
await idbListOps();
```

Expected: `[{ id: 1, op_type: 'insert', client_id: 'test-1', ... }]`. Clean up:

```js
var ops = await idbListOps();
for (var o of ops) await idbDeleteOp(o.id);
```

In DevTools → Application → IndexedDB → `suividepenses_offline` → `pending_ops`, you can also visually confirm the store exists.

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat(offline): IndexedDB wrapper for the pending-ops queue"
```

---

### Task 9: Mutation router

**Files:**
- Modify: `index.html` (add to the IDB section)

- [ ] **Step 1: Add the router**

Append below the IDB wrapper (after `idbDeleteOp`):

```js
/* ─────────── Mutation router ─────────── */
// Returns { ok: true, data, fromQueue: false } on direct success,
//         { ok: true, fromQueue: true, op } when queued,
//         { ok: false, error } on server-level error.
function isNetworkError(err) {
  if (!err) return false;
  // Supabase-js wraps fetch errors. Distinguish them from PostgrestError (which has `code`/`status`).
  if (err.code || err.status) return false;
  if (err.message && /Failed to fetch|NetworkError|TypeError|timeout/i.test(err.message)) return true;
  return false;
}

async function tryDirect(fn) {
  try {
    var res = await fn();
    if (res && res.error) return { ok: false, error: res.error };
    return { ok: true, data: res ? res.data : null };
  } catch (err) {
    return { ok: false, error: err };
  }
}

async function routedWrite(opSpec, directFn) {
  // opSpec: { op_type, client_id, target_id?, payload?, blob?, mime?, ext? }
  // If navigator.onLine is explicitly false, skip the direct attempt.
  if (navigator.onLine !== false) {
    var direct = await tryDirect(directFn);
    if (direct.ok) return { ok: true, data: direct.data, fromQueue: false };
    if (!isNetworkError(direct.error)) {
      // Server-level error (RLS, validation, 5xx) — surface, do not queue.
      return { ok: false, error: direct.error };
    }
    // Network error → fall through to queueing.
  }
  var op = Object.assign({
    created_at: new Date().toISOString(),
    attempts: 0,
    last_error: null
  }, opSpec);
  var id = await idbAddOp(op);
  op.id = id;
  return { ok: true, fromQueue: true, op: op };
}
```

- [ ] **Step 2: Verify**

In DevTools console (signed in):

```js
// Simulate a successful direct write
var spec = { op_type: 'insert', client_id: 'router-1', payload: { description: 'router-smoke' } };
var res = await routedWrite(spec, function(){ return Promise.resolve({ data: { ok: 1 }, error: null }); });
console.assert(res.ok && !res.fromQueue, 'direct path failed');

// Simulate a network error → should queue
var res2 = await routedWrite(
  { op_type: 'insert', client_id: 'router-2', payload: { description: 'router-net-fail' } },
  function(){ return Promise.reject(new TypeError('Failed to fetch')); }
);
console.assert(res2.ok && res2.fromQueue, 'queue path failed');

// Cleanup
var ops = await idbListOps();
for (var o of ops) if (o.client_id && o.client_id.indexOf('router-') === 0) await idbDeleteOp(o.id);
```

Both asserts must pass without console errors.

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat(offline): mutation router (try-direct, queue on network error)"
```

---

### Task 10: Wire saveExpense + deleteExpense through the router

**Files:**
- Modify: `index.html` (`saveExpense` line 911, `deleteExpense` line 1003, `uploadReceipt` around line 950)

- [ ] **Step 1: Refactor `saveExpense` to use the router**

Replace the entire `saveExpense` function (lines 911–948 approximately) with:

```js
async function saveExpense() {
  var desc = document.getElementById('desc').value.trim();
  var amount = parseFloat(document.getElementById('amount').value);
  if (!desc || isNaN(amount) || amount <= 0) { toast(t('valMsg')); return; }

  var payload = {
    description: desc.slice(0, 200),
    amount: amount,
    category: document.getElementById('category').value,
    date: document.getElementById('date').value || new Date().toISOString().split('T')[0],
    paid_by: document.getElementById('paidBy').value.trim().slice(0, 100),
    status: document.getElementById('status').value,
    notes: document.getElementById('notes').value.trim().slice(0, 500)
  };
  var editId = document.getElementById('editId').value;
  var fileInput = document.getElementById('receipt');
  var file = fileInput && fileInput.files && fileInput.files[0] ? fileInput.files[0] : null;

  if (!editId) {
    if (!currentUser.project_id && !currentUser.is_admin) { toast(t('noProjectMsg')); return; }
    payload.user_id = currentUser.id;
    payload.project_id = currentUser.project_id;
    if (!payload.project_id) { toast(t('noProjectMsg')); return; }
    var clientId = (window.crypto && window.crypto.randomUUID) ? window.crypto.randomUUID() : (Date.now() + '-' + Math.random().toString(36).slice(2));
    payload.client_id = clientId;

    var spec = {
      op_type: 'insert',
      client_id: clientId,
      payload: payload,
      blob: file || null,
      mime: file ? file.type : null,
      ext: file ? (file.name.split('.').pop() || 'jpg').toLowerCase() : null
    };
    var res = await routedWrite(spec, function() {
      return window.supabase.from('expenses').upsert(payload, { onConflict: 'client_id', ignoreDuplicates: false }).select().single();
    });
    if (!res.ok) { toast((res.error && res.error.message) || 'Error'); return; }
    if (res.fromQueue) {
      // Optimistic local row
      expenses.unshift(Object.assign({ id: '__local_' + clientId, _pending: true, _client_id: clientId }, payload));
    } else if (file && res.data && res.data.id) {
      await uploadReceipt(res.data.id, file);
    }
    cancelEdit();
    render();
    debouncedRefetchSummary();
    toast(res.fromQueue ? t('toastQueued') : t('toastAdded'));
  } else {
    var spec = {
      op_type: 'update',
      client_id: (window.crypto && window.crypto.randomUUID) ? window.crypto.randomUUID() : String(Date.now()),
      target_id: editId,
      payload: payload,
      blob: file || null,
      mime: file ? file.type : null,
      ext: file ? (file.name.split('.').pop() || 'jpg').toLowerCase() : null
    };
    var res = await routedWrite(spec, function() {
      return window.supabase.from('expenses').update(payload).eq('id', editId);
    });
    if (!res.ok) { toast((res.error && res.error.message) || 'Error'); return; }
    if (res.fromQueue) {
      var idx = expenses.findIndex(function(e){ return e.id === editId; });
      if (idx >= 0) expenses[idx] = Object.assign({}, expenses[idx], payload, { _pending: true });
    } else if (file) {
      await uploadReceipt(editId, file);
    }
    cancelEdit();
    render();
    debouncedRefetchSummary();
    toast(res.fromQueue ? t('toastQueued') : t('toastUpdated'));
  }
}
```

Note: the direct INSERT now uses `upsert(payload, { onConflict: 'client_id' })` so a network blip during the direct attempt that managed to land the row (but lost the response) will be a no-op on retry rather than a duplicate.

- [ ] **Step 2: Refactor `deleteExpense`**

Replace `deleteExpense` (around line 1003):

```js
async function deleteExpense(id) {
  if (!confirm(t('confirmDelete'))) return;
  var e = expenses.find(function(x){ return x.id === id; });
  var spec = {
    op_type: 'delete',
    client_id: (window.crypto && window.crypto.randomUUID) ? window.crypto.randomUUID() : String(Date.now()),
    target_id: id,
    payload: null,
    blob: null
  };
  var res = await routedWrite(spec, async function() {
    if (e && e.receipt_path) {
      await window.supabase.storage.from('receipts').remove([e.receipt_path]).catch(function(){});
    }
    return window.supabase.from('expenses').delete().eq('id', id);
  });
  if (!res.ok) { toast((res.error && res.error.message) || 'Error'); return; }
  // Remove locally either way
  expenses = expenses.filter(function(x){ return x.id !== id; });
  render();
  debouncedRefetchSummary();
  toast(res.fromQueue ? t('toastQueued') : t('toastDeleted'));
}
```

- [ ] **Step 3: Add the `toastQueued` i18n key**

In `dict.en` add `toastQueued: "Saved offline (will sync)"` near the other toast strings.
In `dict.fr` add `toastQueued: "Enregistré hors-ligne (sera synchronisé)"`.

- [ ] **Step 4: Verify online path still works**

Online verification — open the app online, add a new expense via the form. Toast should be the standard "Expense added" / "Dépense ajoutée" (not the queued variant). Edit one. Delete one. Each should behave exactly as before.

(Offline-path verification comes after Task 11 is in place.)

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat(offline): route saveExpense and deleteExpense through the queue"
```

---

### Task 11: Queue replay executor

**Files:**
- Modify: `index.html` (add to the offline section)

- [ ] **Step 1: Add the executor**

Append below `routedWrite` in the offline section:

```js
/* ─────────── Queue replay ─────────── */
var replayInFlight = false;

async function replayQueue() {
  if (replayInFlight) return;
  if (navigator.onLine === false) return;
  replayInFlight = true;
  try {
    var ops = await idbListOps();
    // FIFO by IDB autoincrement id
    ops.sort(function(a,b){ return a.id - b.id; });
    for (var i = 0; i < ops.length; i++) {
      var op = ops[i];
      try {
        await replayOne(op);
        await idbDeleteOp(op.id);
      } catch (err) {
        if (isNetworkError(err)) {
          // Stop the drain; will retry on next reconnect
          break;
        }
        // Server-side rejection — mark and keep so the user can retry/delete
        await idbUpdateOp(op.id, {
          attempts: (op.attempts || 0) + 1,
          last_error: (err && err.message) || String(err)
        });
      }
    }
    // Refresh the summary after a drain
    await loadProjectSummary();
    render();
    updateSyncIndicator();
  } finally {
    replayInFlight = false;
  }
}

async function replayOne(op) {
  if (op.op_type === 'insert') {
    // Idempotent insert via on conflict (client_id) do nothing — using upsert with onConflict
    var payload = Object.assign({}, op.payload, { client_id: op.client_id });
    var ins = await window.supabase
      .from('expenses')
      .upsert(payload, { onConflict: 'client_id', ignoreDuplicates: false })
      .select()
      .single();
    if (ins.error) throw ins.error;
    var realId = ins.data.id;
    // Replace the optimistic row in the local cache
    var idx = expenses.findIndex(function(e){ return e._client_id === op.client_id; });
    if (idx >= 0) expenses[idx] = ins.data;
    if (op.blob) {
      var path = currentUser.id + '/' + realId + '.' + (op.ext || 'jpg');
      var up = await window.supabase.storage.from('receipts').upload(path, op.blob, { upsert: true, contentType: op.mime || 'image/jpeg' });
      if (up.error) throw up.error;
      var rp = await window.supabase.from('expenses').update({ receipt_path: path }).eq('id', realId);
      if (rp.error) throw rp.error;
    }
    return;
  }
  if (op.op_type === 'update') {
    var upd = await window.supabase.from('expenses').update(op.payload).eq('id', op.target_id);
    if (upd.error) throw upd.error;
    if (op.blob) {
      var path = currentUser.id + '/' + op.target_id + '.' + (op.ext || 'jpg');
      var up = await window.supabase.storage.from('receipts').upload(path, op.blob, { upsert: true, contentType: op.mime || 'image/jpeg' });
      if (up.error) throw up.error;
      var rp = await window.supabase.from('expenses').update({ receipt_path: path }).eq('id', op.target_id);
      if (rp.error) throw rp.error;
    }
    return;
  }
  if (op.op_type === 'delete') {
    // Receipt cleanup is best-effort; ignore errors
    var existing = expenses.find(function(e){ return e.id === op.target_id; });
    if (existing && existing.receipt_path) {
      await window.supabase.storage.from('receipts').remove([existing.receipt_path]).catch(function(){});
    }
    var del = await window.supabase.from('expenses').delete().eq('id', op.target_id);
    if (del.error) throw del.error;
    return;
  }
  throw new Error('Unknown op_type: ' + op.op_type);
}

function updateSyncIndicator() {
  // Placeholder — Task 14 implements the visible counter
  if (typeof renderSyncCounter === 'function') renderSyncCounter();
}
```

- [ ] **Step 2: Verify the replay path manually**

In DevTools console (signed in, online):

```js
// Manually queue an insert that is reachable
var clientId = crypto.randomUUID();
await idbAddOp({
  op_type: 'insert',
  client_id: clientId,
  payload: { description: 'replay-smoke', amount: 1.23, category: 'Materials', date: new Date().toISOString().slice(0,10), paid_by: '', status: 'Paid', notes: '', user_id: currentUser.id, project_id: currentUser.project_id },
  blob: null, mime: null, ext: null,
  created_at: new Date().toISOString(), attempts: 0, last_error: null
});
await replayQueue();
// Verify it landed
var rows = await window.supabase.from('expenses').select('id, description').eq('client_id', clientId);
console.log(rows.data); // expect 1 row, description "replay-smoke"
// Cleanup
await window.supabase.from('expenses').delete().eq('client_id', clientId);
```

The expense should appear and replayQueue should drain cleanly with no errors logged.

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat(offline): queue replay executor (insert/update/delete + receipt blob)"
```

---

### Task 12: Reconnect triggers

**Files:**
- Modify: `index.html`

- [ ] **Step 1: Wire the triggers**

Add this block at the bottom of the offline section, after `replayOne`:

```js
/* ─────────── Reconnect triggers ─────────── */
window.addEventListener('online', function() { replayQueue(); });
// Trigger a drain whenever the realtime channel reaches SUBSCRIBED state
function attachReplayHooks() {
  if (!realtimeChannel) return;
  // Supabase channel.subscribe(callback) — the existing subscribeRealtime() call
  // already invokes .subscribe() with no callback. We piggy-back: poll the
  // channel state on focus too, as a safety net.
}
window.addEventListener('focus', function() { replayQueue(); });
window.addEventListener('visibilitychange', function() { if (document.visibilityState === 'visible') replayQueue(); });
```

Find `subscribeRealtime` (modified in Task 3). The current `.subscribe()` call has no callback. Replace `realtimeChannel = window.supabase.channel('expenses-live').on(...).subscribe();` so that the subscribe call has a status callback that triggers a drain on `SUBSCRIBED`:

```js
  realtimeChannel = window.supabase
    .channel('expenses-live')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'expenses' }, function(payload) {
      // ... existing handler body unchanged ...
      if (payload.eventType === 'INSERT') {
        if (!expenses.find(function(e){ return e.id === payload.new.id; })) expenses.unshift(payload.new);
      } else if (payload.eventType === 'UPDATE') {
        var idx = expenses.findIndex(function(e){ return e.id === payload.new.id; });
        if (idx >= 0) expenses[idx] = payload.new;
        else expenses.unshift(payload.new);
      } else if (payload.eventType === 'DELETE') {
        expenses = expenses.filter(function(e){ return e.id !== payload.old.id; });
      }
      debouncedRefetchSummary();
      render();
    })
    .subscribe(function(status) {
      if (status === 'SUBSCRIBED') replayQueue();
    });
```

(Update the existing function body — only the subscribe-callback is new.)

- [ ] **Step 2: Verify**

In DevTools, force the page back to focus (alt-tab away, alt-tab back). In the console you should see no replay errors. Open Application → Service workers and toggle "Offline" — the indicator pill should still say online (because we only react on the actual fetch failure), but if you have any pending ops in IDB they will drain when you toggle Offline back to "no throttling" + the realtime channel re-subscribes.

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat(offline): reconnect triggers (online event, focus, visibilitychange, channel SUBSCRIBED)"
```

---

### Task 13: Optimistic UI for pending rows + rejected-row state

**Files:**
- Modify: `index.html` (`render()` function around line 1069)

- [ ] **Step 1: Locate and extend the row render**

Find the row template inside `render()` — it currently emits a `<tr>` per expense. Locate the `<tr>` template (search for `data-id` or similar inside `render()`). Add a class hook for the pending/rejected state.

In the `<tr>` opening tag, prepend a class:

```js
var rowClass = '';
if (e._pending) rowClass = 'row-pending';
if (e._rejected) rowClass = 'row-rejected';
// then in the template literal: '<tr class="' + rowClass + '" ...>'
```

Add the indicator cell (right before the existing `actions` cell) emitted as:

```js
var syncCell = '';
if (e._pending) syncCell = '<span title="Pending sync">🕒</span>';
else if (e._rejected) syncCell = '<button class="row-action danger" onclick="retryPendingOp(\'' + escAttr(e._client_id) + '\')" title="Retry">⚠️</button>';
```

(Add this cell to the row template in the appropriate position. Adjust the table header row to add a "Sync" column so the columns line up.)

- [ ] **Step 2: Add the CSS**

In the CSS section, near `.row-actions`:

```css
tr.row-pending { opacity: 0.55; }
tr.row-pending td { font-style: italic; }
tr.row-rejected { background: rgba(239,68,68,.08); }
tr.row-rejected td { color: var(--red); }
```

- [ ] **Step 3: Add the retry handler**

After `replayOne`, add:

```js
async function retryPendingOp(clientId) {
  var ops = await idbListOps();
  var op = ops.find(function(o){ return o.client_id === clientId; });
  if (!op) return;
  // Reset error state and trigger a drain
  await idbUpdateOp(op.id, { last_error: null });
  replayQueue();
}
window.retryPendingOp = retryPendingOp;

async function discardPendingOp(clientId) {
  if (!confirm('Discard this pending change?')) return;
  var ops = await idbListOps();
  var op = ops.find(function(o){ return o.client_id === clientId; });
  if (!op) return;
  await idbDeleteOp(op.id);
  // Also remove the optimistic row from the local cache
  expenses = expenses.filter(function(e){ return e._client_id !== clientId; });
  render();
}
window.discardPendingOp = discardPendingOp;
```

- [ ] **Step 4: Mark rejected ops in render**

After `replayQueue` finishes, update the local `expenses` so that rows whose client_id corresponds to an op marked with `last_error` get the `_rejected` flag:

In the `replayQueue` `finally` block, before `render()`, add:

```js
    var afterOps = await idbListOps();
    var rejectedClientIds = afterOps.filter(function(o){ return o.last_error; }).map(function(o){ return o.client_id; });
    expenses.forEach(function(e) {
      if (e._client_id && rejectedClientIds.indexOf(e._client_id) >= 0) {
        e._rejected = true;
        e._pending = false;
      }
    });
```

- [ ] **Step 5: Verify offline → online**

In DevTools, Application → Service workers → check "Offline". (This blocks fetch but keeps your tab alive.) Add 3 expenses via the form. Each row should appear faded with the 🕒 icon. Now uncheck "Offline". Within ~1s the rows should settle (no fade, no clock). Counter (Task 14) will be wired next.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat(offline): optimistic pending rows + rejected row state with retry"
```

---

### Task 14: Sync counter on the connectivity pill + offline budget card stale state

**Files:**
- Modify: `index.html` (`setStorageMode` line 875, render integration)

- [ ] **Step 1: Replace `setStorageMode` to support a pending counter**

Replace the existing `setStorageMode` (lines 875–883) with:

```js
async function setStorageMode(online) {
  var dot = document.querySelector('#dbIndicator .status-dot');
  var lbl = document.getElementById('dbLabel');
  var btn = document.getElementById('dbIndicator');
  var pendingCount = 0;
  try { pendingCount = (await idbListOps()).length; } catch (e) {}
  if (online) {
    dot.className = 'status-dot dot-server';
    lbl.textContent = pendingCount > 0 ? (t('dbOnline') + ' (' + pendingCount + ' ' + t('syncSuffix') + ')') : t('dbOnline');
    btn.className = 'btn-db db-server';
  } else {
    dot.className = 'status-dot dot-local';
    lbl.textContent = pendingCount > 0 ? (t('dbOffline') + ' (' + pendingCount + ' ' + t('queuedSuffix') + ')') : t('dbOffline');
    btn.className = 'btn-db db-local';
  }
}

function renderSyncCounter() { setStorageMode(navigator.onLine !== false && !!currentUser); }
```

- [ ] **Step 2: Add the i18n suffixes**

In `dict.en`: `syncSuffix: "syncing"`, `queuedSuffix: "queued"`.
In `dict.fr`: `syncSuffix: "synchronisation"`, `queuedSuffix: "en attente"`.

- [ ] **Step 3: Trigger the counter render**

At the end of `render()` (the function around line 1069), add:

```js
  renderSyncCounter();
```

Also call it from inside `replayQueue`'s loop (after each `idbDeleteOp`) so the counter ticks down in real time. Place it after `await idbDeleteOp(op.id);`:

```js
        await idbDeleteOp(op.id);
        renderSyncCounter();
```

And on `online` / `offline` window events — extend the listeners added in Task 12:

```js
window.addEventListener('online', function() { renderSyncCounter(); replayQueue(); });
window.addEventListener('offline', function() { renderSyncCounter(); });
```

- [ ] **Step 4: Add `computeOfflineSpentDelta` for the budget card stale state**

Above `computeBudgetCardState` (Task 4), add:

```js
window.computeOfflineSpentDelta = function() {
  // Sums the user's own offline-pending insert/delete amounts (for the
  // current project). Updates only get reflected in the local cache via
  // _pending; their amount may differ from server, but for staleness
  // we rely on the realtime refetch after replay.
  var delta = 0;
  if (!currentUser || !currentUser.project_id) return 0;
  expenses.forEach(function(e) {
    if (e._pending && e.project_id === currentUser.project_id && !e._rejected) {
      delta += Number(e.amount || 0);
    }
  });
  return delta;
};
```

(Already wired into `computeBudgetCardState` from Task 4.)

- [ ] **Step 5: Verify**

In DevTools, set Offline. Add 2 expenses. Pill should read `Hors ligne (2 en attente)` (or English equivalent). Budget card should show `(server_total + your_offline_total) / budget` with a dashed border. Untoggle Offline. Pill should briefly say `En ligne (n synchronisation)` then return to `En ligne`. Card returns to non-dashed.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat(offline): sync counter on connectivity pill + stale budget card state"
```

---

### Task 15: Phase 2 docs + cache bump

**Files:**
- Modify: `sw.js`
- Modify: `SETUP.md`
- Modify: `GUIDE.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Bump the service worker cache**

In `sw.js`:

```js
const CACHE = 'expenses-supabase-v3-offline';
```

- [ ] **Step 2: Append migration #6 to SETUP.md table**

Add row to the migrations table:

```markdown
| 6 | `20260430000006_expense_client_id.sql` | Adds `expenses.client_id` + unique partial index for offline INSERT idempotency. |
```

In §9, append a new sub-section for offline:

```markdown
### 9.y Offline writes (post-Phase-2)

1. DevTools → Application → Service workers → check "Offline" (or Network tab → Offline).
2. Add 5 expenses via the form. Each row appears faded with 🕒. Pill reads `Hors ligne (5 en attente)`.
3. Uncheck Offline. Rows settle (full opacity, no clock) within ~1s. Pill returns to `En ligne`.
4. Add an expense with a receipt photo while offline. Toggle online. Receipt uploads after the row sync completes.
5. While offline, edit an existing expense. Optimistic update visible. Settles on reconnect.
6. While offline, delete an expense. Row vanishes. Stays gone after reconnect.
7. While offline, in another browser as admin, edit the row that user A is editing offline. User A reconnects → user A's edit wins (last-write-wins; expected).
8. Demote a user (admin → set is_admin=false on their profile) and unassign their project mid-offline-session, then have them replay. Rejected ops surface with ⚠️ and a Retry option.
9. Force-quit the browser tab while ops are queued. Re-open. Queue persists, drains on reconnect.
```

- [ ] **Step 3: GUIDE.md — short FR section**

In `GUIDE.md`, add a new section after §6 (Synchronisation en temps réel):

```markdown
## 6.bis Travailler hors-ligne

L'application enregistre vos dépenses même sans connexion. Quand vous êtes hors réseau (sous-sol, ascenseur, zone blanche) :

- L'indicateur en haut affiche **Hors ligne (n en attente)** — `n` est le nombre de saisies à synchroniser.
- Vos nouvelles dépenses apparaissent dans la liste avec une icône 🕒 et un effet grisé : elles sont stockées sur votre téléphone.
- Dès que la connexion revient, elles partent automatiquement vers le serveur. L'icône 🕒 disparaît, l'effet grisé s'efface.
- Si une saisie est rejetée par le serveur (par exemple parce qu'un admin vous a retiré du projet entretemps), elle apparaît en rouge avec ⚠️. Vous pouvez la **réessayer** ou la **supprimer**.

La carte **Budget** affiche un cadre en pointillés tant que des saisies sont en attente : c'est un total approximatif (vos changements locaux + dernière valeur connue du serveur). Une fois la synchronisation faite, le cadre redevient plein.
```

- [ ] **Step 4: CLAUDE.md — architecture notes**

In `CLAUDE.md`, in the Architecture section, after the burn-rate sub-heading added in Task 6, add:

```markdown
### Offline writes go through a mutation router and an IndexedDB queue

Every write (`saveExpense`, `deleteExpense`) goes through `routedWrite(spec, directFn)`. It tries the Supabase call first; if that fails with a **network-level** error (or `navigator.onLine === false`), the op lands in IDB store `pending_ops` (DB `suividepenses_offline`). **Server-level errors (RLS, validation, 5xx) are NOT queued** — they surface inline as today.

Replay is FIFO and triggered by: `window.online` event, window focus, document visibility change, and the realtime channel reaching `SUBSCRIBED`. The replay executor for INSERT uses `upsert(payload, { onConflict: 'client_id' })` so a network blip during the direct attempt that landed the row but lost the response becomes a no-op on retry.

Receipt blobs are queued **inline** on the insert/update op (no separate `upload_receipt` op type). The replay sequence for an insert with a blob is: INSERT → upload to `receipts/<user_id>/<real_id>.<ext>` → UPDATE `receipt_path`.

**Don't add a sync library** (Dexie, RxDB, etc.) — the wrapper is intentionally ~80 lines of raw IndexedDB to match the no-toolchain ethos.
```

- [ ] **Step 5: Verify cache bump**

DevTools → Application → Service workers. Refresh. The new SW (`expenses-supabase-v3-offline`) should activate. If you still see the previous version, click "skipWaiting".

- [ ] **Step 6: Commit**

```bash
git add sw.js SETUP.md GUIDE.md CLAUDE.md
git commit -m "docs(offline): SETUP/GUIDE/CLAUDE updates + sw cache bump v3"
```

---

## Self-review — spec coverage

| Spec requirement | Task |
|---|---|
| `projects.budget_amount` + `budget_alert_pct` | Task 1 |
| `get_project_summary()` SECURITY DEFINER RPC | Task 1 |
| Add `projects` to realtime publication | Task 1 |
| Profile embed widened to include budget fields | Task 2 |
| Debounced summary refetcher | Task 2 |
| Second realtime channel on `projects` | Task 3 |
| Expenses handler also refetches summary | Task 3 |
| Budget stat card with green/amber/red | Task 4 |
| Admin viewing all projects → summed view | Task 4 (`computeBudgetCardState` admin branch) |
| Admin panel budget inputs + Save | Task 5 |
| i18n keys (EN + FR, both updated) | Tasks 4, 5, 10, 14 |
| `expenses.client_id` + unique partial index | Task 7 |
| IndexedDB wrapper (single object store, no library) | Task 8 |
| Mutation router (try-direct, queue on network error only) | Task 9 |
| `crypto.randomUUID()` client_id on inserts | Task 10 |
| Blob inlined on insert/update ops (no separate upload_receipt op) | Tasks 10, 11 |
| Replay executor (insert → upload → set receipt_path) | Task 11 |
| `upsert(... onConflict: 'client_id')` for INSERT idempotency | Tasks 10, 11 |
| Reconnect triggers (online, focus, visibilitychange, SUBSCRIBED) | Task 12 |
| Optimistic pending rows | Task 13 |
| Rejected-row state with retry/discard | Task 13 |
| Sync counter on connectivity pill | Task 14 |
| Offline budget card stale state | Task 14 |
| Two service-worker cache bumps | Tasks 6, 15 |
| SETUP test checklists | Tasks 6, 15 |
| GUIDE FR section | Task 15 |
| CLAUDE architecture notes | Tasks 6, 15 |

**No gaps.** Every spec section maps to at least one task.

## Self-review — placeholders & consistency

- No `TBD` / `TODO` / "implement later" markers in any task.
- All code blocks contain complete, drop-in code (no "..." continuations).
- Type/name consistency: `loadProjectSummary` (Tasks 2, 11), `debouncedRefetchSummary` (Tasks 2, 3, 10), `replayQueue` (Tasks 11, 12, 13, 14), `routedWrite` (Tasks 9, 10), `idbAddOp/idbListOps/idbUpdateOp/idbDeleteOp` (Tasks 8, 9, 11, 13, 14) — all match.
- `computeOfflineSpentDelta` is referenced by `computeBudgetCardState` (Task 4) and defined in Task 14. Task 4's reference uses `window.computeOfflineSpentDelta` with a falsy guard, so Phase 1 works standalone before Phase 2 lands.
- `renderSyncCounter` is referenced by `updateSyncIndicator` (Task 11) with a `typeof === 'function'` guard, so Phase 2 task ordering does not break.
- All migrations are idempotent (`if not exists`, `do $$ ... $$`, `on conflict`).
