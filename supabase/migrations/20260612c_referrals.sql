-- Referral program: invite friends, earn PRO time or streak freezes.
--
-- Mechanics:
--   * every user gets a 6-char referral code (generated lazily by
--     get_referral_info);
--   * a new user redeems a code once (users.referred_by is the one-shot
--     guard) and gets a 3-day PRO welcome bonus themselves;
--   * the referrer gets one unclaimed reward per referral, claimable as
--     either 3 days of PRO or 1 streak freeze (claim_referral_reward);
--   * every 10th referral automatically grants the referrer 30 days of PRO
--     on top (milestone_granted marks the row that triggered it).
--
-- Temporary PRO lives in users.pro_until; check_and_increment_usage is
-- updated so referral PRO lifts the server-side AI quotas exactly like a
-- paid premium plan. Freezes live in users.bonus_freezes and are added to
-- the client-side freeze wallet.

alter table public.users add column if not exists referral_code text unique;
alter table public.users add column if not exists referred_by uuid references public.users(id);
alter table public.users add column if not exists pro_until timestamptz;
alter table public.users add column if not exists bonus_freezes int not null default 0;

create table if not exists public.referrals (
  id                uuid primary key default uuid_generate_v4(),
  referrer_id       uuid not null references public.users(id) on delete cascade,
  referred_id       uuid not null unique references public.users(id) on delete cascade,
  reward            text check (reward in ('pro3d', 'freeze')),   -- null = unclaimed
  milestone_granted boolean not null default false,
  created_at        timestamptz not null default now()
);

alter table public.referrals enable row level security;

drop policy if exists "Referrer can read own referrals" on public.referrals;
create policy "Referrer can read own referrals"
  on public.referrals for select
  using (auth.uid() = referrer_id);

create index if not exists idx_referrals_referrer on public.referrals (referrer_id);

-- ============ helpers ============

-- Extend temporary PRO: stack on top of whatever is left, never shorten.
create or replace function public.grant_pro_days(p_user uuid, p_days int)
returns void
language sql security definer set search_path = public as $$
  update users
  set pro_until = greatest(coalesce(pro_until, now()), now()) + make_interval(days => p_days)
  where id = p_user;
$$;

revoke execute on function public.grant_pro_days(uuid, int) from public, anon, authenticated;

-- ============ RPCs ============

-- My code (generated on first call), totals and unclaimed rewards.
create or replace function public.get_referral_info()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_total int;
  v_freezes int;
  v_unclaimed jsonb;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select referral_code, bonus_freezes into v_code, v_freezes from users where id = v_uid;
  if v_code is null then
    loop
      v_code := upper(substr(md5(random()::text), 1, 6));
      exit when not exists (select 1 from users where referral_code = v_code);
    end loop;
    update users set referral_code = v_code where id = v_uid;
  end if;

  select count(*)::int into v_total from referrals where referrer_id = v_uid;
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'created_at', created_at)
                            order by created_at), '[]'::jsonb)
  into v_unclaimed
  from referrals where referrer_id = v_uid and reward is null;

  return jsonb_build_object(
    'code',           v_code,
    'total',          v_total,
    'bonus_freezes',  v_freezes,
    'unclaimed',      v_unclaimed);
end $$;

grant execute on function public.get_referral_info() to authenticated;
revoke execute on function public.get_referral_info() from public, anon;

-- One-shot redemption by the invited user. Grants them 3 days of PRO and
-- creates an unclaimed reward for the referrer; every 10th referral grants
-- the referrer 30 bonus days automatically.
create or replace function public.redeem_referral_code(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_referrer uuid;
  v_total int;
  v_milestone boolean := false;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select id into v_referrer from users
  where referral_code = upper(trim(p_code));
  if not found then raise exception 'code not found'; end if;
  if v_referrer = v_uid then raise exception 'cannot redeem own code'; end if;

  -- One-shot guard: only flips when referred_by is still null.
  update users set referred_by = v_referrer
  where id = v_uid and referred_by is null;
  if not found then raise exception 'already redeemed'; end if;

  insert into referrals (referrer_id, referred_id) values (v_referrer, v_uid);

  -- Welcome bonus for the invited user.
  perform grant_pro_days(v_uid, 3);

  select count(*)::int into v_total from referrals where referrer_id = v_referrer;
  if v_total % 10 = 0 then
    perform grant_pro_days(v_referrer, 30);
    update referrals set milestone_granted = true where referred_id = v_uid;
    v_milestone := true;
  end if;

  return jsonb_build_object(
    'referrer_id', v_referrer,
    'total',       v_total,
    'milestone',   v_milestone);
end $$;

grant execute on function public.redeem_referral_code(text) to authenticated;
revoke execute on function public.redeem_referral_code(text) from public, anon;

-- Referrer picks the reward for one referral: 3 days of PRO or 1 freeze.
create or replace function public.claim_referral_reward(p_referral_id uuid, p_reward text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_reward not in ('pro3d', 'freeze') then raise exception 'unknown reward'; end if;

  update referrals set reward = p_reward
  where id = p_referral_id and referrer_id = v_uid and reward is null;
  if not found then raise exception 'reward not found or already claimed'; end if;

  if p_reward = 'pro3d' then
    perform grant_pro_days(v_uid, 3);
  else
    update users set bonus_freezes = bonus_freezes + 1 where id = v_uid;
  end if;

  return (select jsonb_build_object('pro_until', pro_until, 'bonus_freezes', bonus_freezes)
          from users where id = v_uid);
end $$;

grant execute on function public.claim_referral_reward(uuid, text) to authenticated;
revoke execute on function public.claim_referral_reward(uuid, text) from public, anon;

-- ============ AI quotas honor temporary PRO ============
-- Same body as before, but the plan used for limits is upgraded to
-- 'premium' while users.pro_until is in the future.

create or replace function public.check_and_increment_usage(p_user_id uuid, p_feature text, p_month text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_plan    text;
  v_limit   int;
  v_count   int;
begin
  select case when plan = 'free' and pro_until > now() then 'premium' else plan end
  into v_plan from users where id = p_user_id;
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
    else 0
  end;

  select coalesce(count, 0) into v_count
  from ai_usage
  where user_id = p_user_id and feature = p_feature and month = p_month;

  if v_count >= v_limit then
    return jsonb_build_object('allowed', false, 'remaining', 0, 'limit', v_limit);
  end if;

  insert into ai_usage(user_id, feature, month, count)
    values (p_user_id, p_feature, p_month, 1)
  on conflict (user_id, feature, month)
  do update set count = ai_usage.count + 1;

  return jsonb_build_object('allowed', true, 'remaining', v_limit - v_count - 1, 'limit', v_limit);
end $$;
