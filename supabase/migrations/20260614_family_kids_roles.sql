-- Family kids accounts + mom/dad/child roles.
-- Builds on 20260613e_family_management.sql.
--
-- Adds:
--   * users.display_name      -- shown instead of the synthetic kid email
--   * users.family_role       -- 'mom' | 'dad' | 'child' (display + grouping)
--   * users.is_child_account  -- parent-provisioned PIN account
--   * users.child_login_code  -- short unique code the child signs in with
--   * RLS so any family member can read the other members' profiles
--   * set_family_role() RPC (parent assigns mom/dad/child)

-- 1. New user columns ---------------------------------------------------------
alter table public.users add column if not exists display_name text;
alter table public.users add column if not exists family_role text
  check (family_role in ('mom', 'dad', 'child'));
alter table public.users add column if not exists is_child_account boolean not null default false;
alter table public.users add column if not exists child_login_code text;

create unique index if not exists users_child_login_code_key
  on public.users (child_login_code) where child_login_code is not null;

-- 2. Family-scoped profile reads ---------------------------------------------
-- The base users SELECT policy is self-only. A parent needs to read children's
-- names, and children need to see mom/dad. A SECURITY DEFINER helper returns the
-- caller's family_id WITHOUT re-triggering RLS (avoids recursive policy eval).
create or replace function public.my_family_id()
returns uuid
language sql stable security definer set search_path = public as $$
  select family_id from users where id = auth.uid()
$$;

grant execute on function public.my_family_id() to authenticated;

drop policy if exists "Family members read each other" on public.users;
create policy "Family members read each other" on public.users
  for select using (
    family_id is not null and family_id = public.my_family_id()
  );

-- 3. Assign a member's family role (mom/dad/child). Parent-only. --------------
-- mom/dad map to the 'parent' permission role; child maps to 'child'.
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
