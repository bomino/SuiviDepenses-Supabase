-- Admin user directory RPC.
-- Returns one row per profile, joined with auth.users email + sign-in/invite
-- timestamps so the admin panel can show emails (not just truncated UUIDs)
-- and distinguish accepted users from pending invites.
--
-- SECURITY DEFINER because auth.users is locked down by default (no RLS path
-- for non-admins). Authorization is enforced inside the function — only
-- admins get rows; everyone else gets an empty result.
--
-- Apply AFTER 20260430000006_expense_client_id.sql.
-- Idempotent: safe to re-run.

create or replace function public.get_user_directory()
returns table (
    id                uuid,
    email             text,
    full_name         text,
    is_admin          boolean,
    project_id        uuid,
    project_name      text,
    invited_at        timestamptz,
    last_sign_in_at   timestamptz,
    created_at        timestamptz
)
language sql stable security definer set search_path = public as $$
    select
        p.id,
        u.email::text,
        p.full_name,
        p.is_admin,
        p.project_id,
        pr.name as project_name,
        u.invited_at,
        u.last_sign_in_at,
        u.created_at
    from public.profiles p
    join auth.users u on u.id = p.id
    left join public.projects pr on pr.id = p.project_id
    where public.is_admin(auth.uid())
    order by u.created_at;
$$;

revoke execute on function public.get_user_directory() from public;
grant execute on function public.get_user_directory() to authenticated;
