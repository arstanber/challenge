-- Both participants must be charged in the same transaction. If either wallet
-- can no longer preserve its protected final day, the whole join rolls back.
create or replace function public.join_duel_commitment(p_code text)
returns public.duels language plpgsql security definer set search_path = public as $$
declare
  v_row public.duels;
  v_balance int;
  v_uid uuid := auth.uid();
  v_updated int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select * into v_row
  from duels
  where invite_code = upper(trim(p_code))
  for update;

  if not found or v_row.status <> 'pending' then
    raise exception 'duel not available';
  end if;
  if v_row.challenger_id = v_uid then raise exception 'cannot join own duel'; end if;

  if v_row.commitment_kind = 'days' then
    v_balance := public.my_commitment_days();
    if v_row.stake_days > least(3, v_balance - 1) then
      raise exception 'not enough commitment days';
    end if;

    insert into commitment_day_accounts(user_id, available_days)
    values (
      v_row.challenger_id,
      greatest(1, coalesce((select max(streak_current) from activities where user_id = v_row.challenger_id), 1))
    )
    on conflict(user_id) do nothing;

    update commitment_day_accounts
    set available_days = available_days - v_row.stake_days,
        updated_at = now()
    where user_id in (v_row.challenger_id, v_uid)
      and available_days - v_row.stake_days >= 1;
    get diagnostics v_updated = row_count;
    if v_updated <> 2 then raise exception 'not enough commitment days'; end if;

    insert into commitment_day_ledger(user_id, duel_id, delta, reason, idempotency_key)
    values
      (v_row.challenger_id, v_row.id, -v_row.stake_days, 'reserve', v_row.id || ':reserve:c'),
      (v_uid, v_row.id, -v_row.stake_days, 'reserve', v_row.id || ':reserve:o');
  end if;

  return public.join_duel(p_code);
end $$;

grant execute on function public.join_duel_commitment(text) to authenticated;
revoke all on function public.join_duel_commitment(text) from public, anon;
