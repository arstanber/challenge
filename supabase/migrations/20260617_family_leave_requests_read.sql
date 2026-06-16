-- Let a parent read pending leave-request codes for their family in-app, so the
-- flow doesn't depend on the push actually arriving. Child still can't read the
-- code (no select policy on the table); only this parent-scoped RPC exposes it.

create or replace function public.get_family_leave_requests()
returns table (child_user_id uuid, child_name text, code text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_family uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select id into v_family from families where parent_user_id = v_uid;
  if not found then return; end if;
  return query
  select r.child_user_id,
         coalesce(nullif(u.display_name, ''), split_part(u.email, '@', 1)) as child_name,
         r.code, r.created_at
  from family_leave_requests r
  join family_members fm on fm.child_user_id = r.child_user_id and fm.family_id = v_family
  join users u on u.id = r.child_user_id
  where r.created_at > now() - interval '30 minutes'
  order by r.created_at desc;
end $$;

grant execute on function public.get_family_leave_requests() to authenticated;
revoke execute on function public.get_family_leave_requests() from public, anon;
