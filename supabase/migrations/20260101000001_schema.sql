-- Schema for SuiviDepenses (Supabase / Tier 3 edition).
-- Apply in the Supabase SQL editor (Dashboard -> SQL -> New query).
-- Idempotent: safe to re-run.

-- ============================================================================
-- profiles: per-user metadata, mirrors auth.users 1-to-1.
-- Created automatically by the trigger below when a user signs up.
-- ============================================================================
create table if not exists public.profiles (
    id          uuid        primary key references auth.users(id) on delete cascade,
    full_name   text,
    is_admin    boolean     not null default false,
    project_id  uuid,                                       -- FK added below (FK created after projects table exists)
    created_at  timestamptz not null default now()
);

-- ============================================================================
-- projects: each project = one construction site.
-- ============================================================================
create table if not exists public.projects (
    id          uuid        primary key default gen_random_uuid(),
    name        text        unique not null,
    created_at  timestamptz not null default now(),
    created_by  uuid        references auth.users(id) on delete set null
);

-- Wire profiles.project_id to projects (created in two steps so the order works on a fresh DB)
do $$
begin
    if not exists (
        select 1 from information_schema.table_constraints
        where constraint_name = 'profiles_project_id_fkey'
          and table_name = 'profiles'
    ) then
        alter table public.profiles
            add constraint profiles_project_id_fkey
            foreign key (project_id) references public.projects(id) on delete set null;
    end if;
end$$;

-- ============================================================================
-- expenses: the main transactional table.
-- ============================================================================
create table if not exists public.expenses (
    id          uuid        primary key default gen_random_uuid(),
    user_id     uuid        not null references auth.users(id) on delete cascade,
    project_id  uuid        not null references public.projects(id) on delete cascade,
    description text        not null check (length(description) between 1 and 200),
    amount      numeric(14,2) not null check (amount > 0),
    category    text        not null default 'Materials' check (category in (
                  'Materials','Labor','Equipment','Permits','Subcontractors','Transport','Utilities','Misc'
                )),
    date        date        not null default current_date,
    paid_by     text        default '' check (length(paid_by) <= 100),
    status      text        not null default 'Paid' check (status in ('Paid','Pending','Unpaid')),
    notes       text        default '' check (length(notes) <= 500),
    receipt_path text,                                       -- path inside the 'receipts' storage bucket; null = no receipt
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

create index if not exists expenses_user_idx    on public.expenses(user_id);
create index if not exists expenses_project_idx on public.expenses(project_id);
create index if not exists expenses_date_idx    on public.expenses(date desc);

-- Auto-bump updated_at on every UPDATE
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end$$;

drop trigger if exists trg_expenses_touch on public.expenses;
create trigger trg_expenses_touch
    before update on public.expenses
    for each row execute function public.touch_updated_at();

-- ============================================================================
-- Auto-create a profile row whenever a user signs up via Supabase Auth.
-- ============================================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    insert into public.profiles (id, full_name)
    values (new.id, new.raw_user_meta_data->>'full_name')
    on conflict (id) do nothing;
    return new;
end$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ============================================================================
-- Helper: is_admin(uid) - used by RLS policies to keep them readable.
-- SECURITY DEFINER so policy checks can read profiles even when RLS would
-- otherwise hide rows from the calling user.
-- ============================================================================
create or replace function public.is_admin(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
    select coalesce((select is_admin from public.profiles where id = uid), false);
$$;

-- ============================================================================
-- Enable Realtime on expenses so the frontend can subscribe to live changes.
-- ============================================================================
alter publication supabase_realtime add table public.expenses;
