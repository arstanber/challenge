-- Duel commitments are deliberately separate from the canonical streak.
-- The wallet is server-owned; clients can only use the narrow RPCs below.

alter table public.duels
  add column if not exists commitment_kind text not null default 'none'
    check (commitment_kind in ('none', 'days', 'social_forfeit')),
  add column if not exists stake_days smallint
    check (stake_days between 1 and 3),
  add column if not exists forfeit_text text,
  add column if not exists commitment_settled_at timestamptz;

create table if not exists public.commitment_day_accounts (
  user_id uuid primary key references public.users(id) on delete cascade,
  available_days int not null check (available_days >= 1),
  updated_at timestamptz not null default now()
);

create table if not exists public.commitment_day_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  duel_id uuid references public.duels(id) on delete cascade,
  delta int not null check (delta <> 0),
  reason text not null check (reason in ('reserve', 'refund', 'result')),
  idempotency_key text not null unique,
  created_at timestamptz not null default now()
);

alter table public.commitment_day_accounts enable row level security;
alter table public.commitment_day_ledger enable row level security;
create policy "read own commitment account" on public.commitment_day_accounts
  for select to authenticated using (user_id = auth.uid());
create policy "read own commitment ledger" on public.commitment_day_ledger
  for select to authenticated using (user_id = auth.uid());

create or replace function public.my_commitment_days()
returns int language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_days int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  insert into commitment_day_accounts(user_id, available_days)
  values (v_uid, greatest(1, coalesce((select max(streak_current) from activities where user_id=v_uid), 1)))
  on conflict (user_id) do nothing;
  select available_days into v_days from commitment_day_accounts where user_id=v_uid;
  return v_days;
end $$;

create or replace function public.create_duel_commitment(
  p_days int default 7, p_kind text default 'none', p_stake_days int default null,
  p_forfeit_text text default null)
returns public.duels language plpgsql security definer set search_path = public as $$
declare v_row public.duels; v_balance int;
begin
  if p_kind not in ('none','days','social_forfeit') then raise exception 'invalid commitment'; end if;
  perform public.my_commitment_days();
  if p_kind = 'days' then
    v_balance := public.my_commitment_days();
    if p_stake_days is null or p_stake_days > least(3, v_balance - 1) then
      raise exception 'stake exceeds protected balance';
    end if;
  elsif p_kind = 'social_forfeit' then
    if length(trim(coalesce(p_forfeit_text,''))) not between 3 and 160 then raise exception 'invalid forfeit'; end if;
  end if;
  v_row := public.create_duel(p_days);
  update duels set commitment_kind=p_kind,
    stake_days=case when p_kind='days' then p_stake_days end,
    forfeit_text=case when p_kind='social_forfeit' then trim(p_forfeit_text) end
  where id=v_row.id returning * into v_row;
  return v_row;
end $$;

create or replace function public.join_duel_commitment(p_code text)
returns public.duels language plpgsql security definer set search_path = public as $$
declare v_row public.duels; v_balance int; v_uid uuid:=auth.uid();
begin
  select * into v_row from duels where invite_code=upper(trim(p_code)) for update;
  if not found or v_row.status <> 'pending' then raise exception 'duel not available'; end if;
  if v_row.commitment_kind='days' then
    v_balance := public.my_commitment_days();
    if v_row.stake_days > least(3, v_balance-1) then raise exception 'not enough commitment days'; end if;
    insert into commitment_day_accounts(user_id,available_days)
      values(v_row.challenger_id,greatest(1,coalesce((select max(streak_current) from activities where user_id=v_row.challenger_id),1)))
      on conflict(user_id) do nothing;
    update commitment_day_accounts set available_days=available_days-v_row.stake_days, updated_at=now()
      where user_id in (v_row.challenger_id, v_uid) and available_days-v_row.stake_days >= 1;
    if not found then raise exception 'not enough commitment days'; end if;
    insert into commitment_day_ledger(user_id,duel_id,delta,reason,idempotency_key)
    values (v_row.challenger_id,v_row.id,-v_row.stake_days,'reserve',v_row.id||':reserve:c'),
           (v_uid,v_row.id,-v_row.stake_days,'reserve',v_row.id||':reserve:o');
  end if;
  return public.join_duel(p_code);
end $$;

create or replace function public.settle_duel_commitment(p_duel_id uuid)
returns public.duels language plpgsql security definer set search_path = public as $$
declare v_row public.duels; v_recipient uuid; v_delta int;
begin
  v_row := public.finish_duel_if_due(p_duel_id);
  if v_row.status <> 'finished' or v_row.commitment_settled_at is not null then return v_row; end if;
  if v_row.commitment_kind='days' then
    if v_row.winner_id is null then
      insert into commitment_day_ledger(user_id,duel_id,delta,reason,idempotency_key)
      values (v_row.challenger_id,v_row.id,v_row.stake_days,'refund',v_row.id||':refund:c'),
             (v_row.opponent_id,v_row.id,v_row.stake_days,'refund',v_row.id||':refund:o');
      update commitment_day_accounts set available_days=available_days+v_row.stake_days,updated_at=now()
        where user_id in (v_row.challenger_id,v_row.opponent_id);
    else
      v_recipient:=v_row.winner_id; v_delta:=v_row.stake_days*2;
      insert into commitment_day_ledger(user_id,duel_id,delta,reason,idempotency_key)
      values(v_recipient,v_row.id,v_delta,'result',v_row.id||':result');
      update commitment_day_accounts set available_days=available_days+v_delta,updated_at=now() where user_id=v_recipient;
    end if;
  elsif v_row.commitment_kind='social_forfeit' and v_row.winner_id is not null then
    insert into activities(user_id,title,description,type,condition,frequency,deadline,status,category)
    values(case when v_row.winner_id=v_row.challenger_id then v_row.opponent_id else v_row.challenger_id end,
      'Выполни фант',v_row.forfeit_text,'challenge',v_row.forfeit_text,'once',now()+interval '3 days','active','duel_forfeit');
  end if;
  update duels set commitment_settled_at=now() where id=v_row.id returning * into v_row;
  return v_row;
end $$;

grant execute on function public.my_commitment_days() to authenticated;
grant execute on function public.create_duel_commitment(int,text,int,text) to authenticated;
grant execute on function public.join_duel_commitment(text) to authenticated;
grant execute on function public.settle_duel_commitment(uuid) to authenticated;
revoke all on function public.my_commitment_days() from public,anon;
revoke all on function public.create_duel_commitment(int,text,int,text) from public,anon;
revoke all on function public.join_duel_commitment(text) from public,anon;
revoke all on function public.settle_duel_commitment(uuid) from public,anon;
