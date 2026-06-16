-- Two family-graph integrity guards.
--
-- 1) leave_family(): a parent calling it would clear their own role/family_id
--    while the families row and the children still pointed at them, orphaning
--    the family. Parents must use delete_family() instead.
-- 2) set_family_role(): a parent could set their OWN role to 'child' while
--    remaining families.parent_user_id, leaving the family without a usable
--    parent. Reject that case.

create or replace function public.leave_family()
returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  -- A parent must not orphan their own family via leave_family().
  if exists (select 1 from families where parent_user_id = v_uid) then
    raise exception 'parents must use delete_family()';
  end if;

  delete from family_members where child_user_id = v_uid;
  update users set role = 'individual', family_id = null where id = v_uid;
end $$;

grant execute on function public.leave_family() to authenticated;
revoke execute on function public.leave_family() from public, anon;

create or replace function public.set_family_role(p_member uuid, p_role text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_family uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_role not in ('mom', 'dad', 'child') then raise exception 'invalid role'; end if;

  select id into v_family from families where parent_user_id = v_uid;
  if not found then raise exception 'not a family parent'; end if;

  -- The parent cannot demote themselves to a child while still owning the family.
  if p_member = v_uid and p_role = 'child' then
    raise exception 'parent cannot be assigned the child role';
  end if;

  -- Target must be the caller or a member of the caller's family.
  if p_member <> v_uid and not exists (
    select 1 from family_members
    where family_id = v_family and child_user_id = p_member
  ) then
    raise exception 'member not in your family';
  end if;

  update users
     set family_role = p_role,
         role = case when p_role = 'child' then 'child' else 'parent' end
   where id = p_member;
end $$;

grant execute on function public.set_family_role(uuid, text) to authenticated;
revoke execute on function public.set_family_role(uuid, text) from public, anon;
