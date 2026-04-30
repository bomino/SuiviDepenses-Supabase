-- Row-Level Security policies for SuiviDepenses (Supabase edition).
-- Apply AFTER 20260101000001_schema.sql.
--
-- Authorization model (matches Tier 2 of the Flask version):
--   admin       -> sees & mutates everything
--   supervisor  -> sees & mutates only their own rows within their assigned project

-- ============================================================================
-- Enable RLS on every public table.
-- ============================================================================
alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.expenses enable row level security;

-- ============================================================================
-- profiles
--   - everyone authenticated can read profiles (so admins can populate user
--     dropdowns; supervisors can see their own assignment)
--   - admins can update any profile (assign project, toggle admin)
--   - users can update their own full_name
--   - inserts only via the auth trigger (security definer); no direct policy needed
--   - deletes cascade from auth.users.delete
-- ============================================================================
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
    for select to authenticated
    using (true);

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
    for update to authenticated
    using (id = auth.uid())
    with check (id = auth.uid() and is_admin = (select is_admin from public.profiles where id = auth.uid()));

drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin on public.profiles
    for update to authenticated
    using (public.is_admin(auth.uid()))
    with check (public.is_admin(auth.uid()));

-- ============================================================================
-- projects
--   - everyone authenticated can read projects (workers need to know their own)
--   - only admins can insert/update/delete
-- ============================================================================
drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects
    for select to authenticated
    using (true);

drop policy if exists projects_insert_admin on public.projects;
create policy projects_insert_admin on public.projects
    for insert to authenticated
    with check (public.is_admin(auth.uid()));

drop policy if exists projects_update_admin on public.projects;
create policy projects_update_admin on public.projects
    for update to authenticated
    using (public.is_admin(auth.uid()))
    with check (public.is_admin(auth.uid()));

drop policy if exists projects_delete_admin on public.projects;
create policy projects_delete_admin on public.projects
    for delete to authenticated
    using (public.is_admin(auth.uid()));

-- ============================================================================
-- expenses
--   - admins: full access
--   - supervisors: only rows where user_id = auth.uid() AND project_id matches
--                  their profile.project_id
--   - inserts must stamp user_id = auth.uid() and a project_id the user is on
-- ============================================================================
drop policy if exists expenses_select on public.expenses;
create policy expenses_select on public.expenses
    for select to authenticated
    using (
        public.is_admin(auth.uid())
        or (
            user_id = auth.uid()
            and project_id = (select project_id from public.profiles where id = auth.uid())
        )
    );

drop policy if exists expenses_insert on public.expenses;
create policy expenses_insert on public.expenses
    for insert to authenticated
    with check (
        public.is_admin(auth.uid())
        or (
            user_id = auth.uid()
            and project_id = (select project_id from public.profiles where id = auth.uid())
        )
    );

drop policy if exists expenses_update on public.expenses;
create policy expenses_update on public.expenses
    for update to authenticated
    using (
        public.is_admin(auth.uid())
        or (
            user_id = auth.uid()
            and project_id = (select project_id from public.profiles where id = auth.uid())
        )
    )
    with check (
        public.is_admin(auth.uid())
        or (
            user_id = auth.uid()
            and project_id = (select project_id from public.profiles where id = auth.uid())
        )
    );

drop policy if exists expenses_delete on public.expenses;
create policy expenses_delete on public.expenses
    for delete to authenticated
    using (
        public.is_admin(auth.uid())
        or (
            user_id = auth.uid()
            and project_id = (select project_id from public.profiles where id = auth.uid())
        )
    );
