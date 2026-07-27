-- Photo-backed reports and AI-required activity types must never count before
-- the verify-report edge function writes a final verdict. The existing streak
-- engines already exclude rejected rows, so rejected is the safe initial state.

create or replace function public.protect_ai_verdict()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activity_type text;
begin
  if coalesce(auth.role(), '') = 'service_role'
     or session_user in ('postgres', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    select a.type::text
      into v_activity_type
      from public.activities a
     where a.id = new.activity_id
       and a.user_id = auth.uid();

    if not found then
      raise exception 'Activity not found';
    end if;

    if new.photo_url is not null
       or v_activity_type in ('challenge', 'assignment') then
      new.ai_result := 'rejected';
      new.ai_explanation := null;
    elsif new.ai_result is distinct from 'not_applicable' then
      raise exception 'Plain check-ins must use not_applicable';
    end if;
  elsif tg_op = 'UPDATE' then
    if new.ai_result is distinct from old.ai_result
       or new.ai_explanation is distinct from old.ai_explanation then
      raise exception 'AI verdict fields are read-only for clients';
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.protect_ai_verdict()
  from public, anon, authenticated;
