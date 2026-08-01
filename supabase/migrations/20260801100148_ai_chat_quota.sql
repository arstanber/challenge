-- Add a dedicated monthly quota for conversational AI messages.
-- Limits mirror AIFeature.limit(for:) in the iOS client.

create or replace function public.check_and_increment_usage(
  p_user_id uuid,
  p_feature text,
  p_month text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan text;
  v_limit int;
  v_count int;
begin
  select case when plan = 'free' and pro_until > now() then 'premium' else plan end
  into v_plan
  from users
  where id = p_user_id;

  if not found then
    return jsonb_build_object('allowed', false, 'remaining', 0, 'limit', 0);
  end if;

  v_limit := case p_feature
    when 'verify-report' then
      case v_plan when 'free' then 5 when 'premium' then 30 when 'family' then 30 when 'max' then 100 else 0 end
    when 'parse-tasks-group' then
      case v_plan when 'free' then 1 when 'premium' then 10 when 'family' then 10 when 'max' then 30 else 0 end
    when 'coach-group' then
      case v_plan when 'free' then 1 when 'premium' then 10 when 'family' then 10 when 'max' then 30 else 0 end
    when 'plan-goal' then
      case v_plan when 'free' then 3 when 'premium' then 15 when 'family' then 15 when 'max' then 50 else 0 end
    when 'suggest-condition' then
      case v_plan when 'free' then 10 when 'premium' then 50 when 'family' then 50 when 'max' then 150 else 0 end
    when 'ai-chat' then
      case v_plan when 'free' then 10 when 'premium' then 100 when 'family' then 100 when 'max' then 300 else 0 end
    else 0
  end;

  if v_limit <= 0 then
    return jsonb_build_object('allowed', false, 'remaining', 0, 'limit', v_limit);
  end if;

  insert into ai_usage(user_id, feature, month, count)
    values (p_user_id, p_feature, p_month, 1)
  on conflict (user_id, feature, month)
    do update set count = ai_usage.count + 1
    where ai_usage.count < v_limit
  returning count into v_count;

  if v_count is null then
    return jsonb_build_object('allowed', false, 'remaining', 0, 'limit', v_limit);
  end if;

  return jsonb_build_object('allowed', true, 'remaining', v_limit - v_count, 'limit', v_limit);
end;
$$;

revoke all on function public.check_and_increment_usage(uuid, text, text) from public;
revoke execute on function public.check_and_increment_usage(uuid, text, text) from anon, authenticated;
grant execute on function public.check_and_increment_usage(uuid, text, text) to service_role;
