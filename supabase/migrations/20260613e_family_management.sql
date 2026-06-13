-- Family management RPCs: leave, remove a member, delete the whole family.
-- All validate auth.uid() against the family role and route every write through
-- security definer so RLS stays locked down.
--
-- Note: plan entitlements are per-user (users.plan) and billing is independent
-- of family membership -- leaving/removing only changes the family graph, never
-- a user's subscription.

-- A child leaves their family.
create or replace function public.leave_family()
returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  delete from family_members where child_user_id = v_uid;
  update users set role = 'individual', family_id = null where id = v_uid;
end $$;

grant execute on function public.leave_family() to authenticated;
revoke execute on function public.leave_family() from public, anon;

-- A parent removes one child from their family.
create or replace function public.remove_family_member(p_child uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_family uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select id into v_family from families where parent_user_id = v_uid;
  if not found then raise exception 'not a family parent'; end if;

  -- The child must actually belong to the caller's family.
  if not exists (
    select 1 from family_members
    where family_id = v_family and child_user_id = p_child
  ) then
    raise exception 'member not in your family';
  end if;

  delete from family_members where family_id = v_family and child_user_id = p_child;
  update users set role = 'individual', family_id = null where id = p_child;
end $$;

grant execute on function public.remove_family_member(uuid) to authenticated;
revoke execute on function public.remove_family_member(uuid) from public, anon;

-- A parent deletes their family entirely, detaching every member.
create or replace function public.delete_family()
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_family uuid;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select id into v_family from families where parent_user_id = v_uid;
  if not found then raise exception 'not a family parent'; end if;

  -- Detach all children, then the parent, then drop the family.
  update users set role = 'individual', family_id = null
  where family_id = v_family;

  delete from family_members where family_id = v_family;
  delete from families where id = v_family;
end $$;

grant execute on function public.delete_family() to authenticated;
revoke execute on function public.delete_family() from public, anon;
