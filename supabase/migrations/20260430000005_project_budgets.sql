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

revoke execute on function public.get_project_summary() from public;
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
