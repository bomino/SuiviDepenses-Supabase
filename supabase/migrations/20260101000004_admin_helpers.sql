-- Admin-only RPCs (callable from the frontend via supabase.rpc()).
-- Apply AFTER 20260101000003_storage.sql.
--
-- Without these, the admin panel would have to either expose the service-role
-- key (very bad — bypasses RLS) or call multiple individual queries. RPCs
-- bundle the operation server-side and let RLS enforce who can call them.

-- ============================================================================
-- promote_user / demote_user / assign_user_to_project / set_first_admin
-- All check the caller is an admin via is_admin(auth.uid()).
-- ============================================================================

-- Promote / demote a user (toggles is_admin)
create or replace function public.set_user_admin(target uuid, make_admin boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
    if not public.is_admin(auth.uid()) then
        raise exception 'Only admins can change roles';
    end if;
    if target = auth.uid() and make_admin = false then
        raise exception 'Cannot remove your own admin role';
    end if;
    update public.profiles set is_admin = make_admin where id = target;
end$$;

-- Assign a user to a project (or unassign with project = null)
create or replace function public.assign_user_project(target uuid, project uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
    if not public.is_admin(auth.uid()) then
        raise exception 'Only admins can assign projects';
    end if;
    if project is not null and not exists (select 1 from public.projects where id = project) then
        raise exception 'Project not found';
    end if;
    update public.profiles set project_id = project where id = target;
end$$;

-- ============================================================================
-- Bootstrap helper: claim_first_admin()
-- The very first user that signs up can call this to make themselves admin.
-- After at least one admin exists, this becomes a no-op (returns false).
-- This avoids the chicken-and-egg of "you need an admin to make you admin".
-- ============================================================================
create or replace function public.claim_first_admin()
returns boolean language plpgsql security definer set search_path = public as $$
declare
    has_admin boolean;
begin
    select exists (select 1 from public.profiles where is_admin = true) into has_admin;
    if has_admin then
        return false;
    end if;
    update public.profiles set is_admin = true where id = auth.uid();
    return true;
end$$;
