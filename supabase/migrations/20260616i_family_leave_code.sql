-- Code-gated family leave for children.
--
-- A child can no longer leave the family unilaterally. Instead:
--   1) the child requests to leave -> the `family-leave-request` edge function
--      generates a 6-digit code, stores it here, and PUSHES it to the parent
--      (the code is never returned to the child);
--   2) the parent reads the code from the push and tells it to the child;
--   3) the child enters the code -> leave_family_with_code() validates it and
--      performs the leave.
--
-- The plain leave_family() is now reserved for non-child family members
-- (e.g. a second parent); children must go through the code flow.

create table if not exists public.family_leave_requests (
  child_user_id uuid primary key references public.users(id) on delete cascade,
  code          text not null,
  created_at    timestamptz not null default now()
);

alter table public.family_leave_requests enable row level security;
-- No direct client access: the edge function writes with the service role and
-- leave_family_with_code() (security definer) reads. Children must not read the
-- code, so there is intentionally NO select policy.

-- Validate the parent-issued code and perform the leave atomically.
create or replace function public.leave_family_with_code(p_code text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_req record;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_req from family_leave_requests
  where child_user_id = v_uid for update;
  if not found then raise exception 'no leave request -- request a code first'; end if;

  -- Codes expire after 30 minutes; force a fresh request after that.
  if v_req.created_at < now() - interval '30 minutes' then
    delete from family_leave_requests where child_user_id = v_uid;
    raise exception 'code expired -- request a new one';
  end if;

  if upper(trim(p_code)) <> upper(v_req.code) then
    raise exception 'invalid code';
  end if;

  delete from family_members where child_user_id = v_uid;
  update users set role = 'individual', family_id = null, family_role = null
   where id = v_uid;
  delete from family_leave_requests where child_user_id = v_uid;
end $$;

grant execute on function public.leave_family_with_code(text) to authenticated;
revoke execute on function public.leave_family_with_code(text) from public, anon;
