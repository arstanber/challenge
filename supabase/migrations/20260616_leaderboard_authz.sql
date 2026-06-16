-- Security fix: get_leaderboard was security definer but accepted an arbitrary
-- p_user_id with no authorization check, letting any authenticated user read
-- another family's emails + streaks by passing someone else's UUID.
--
-- Replace the function with an identical body, guarded so the caller can only
-- query their own leaderboard (p_user_id must equal auth.uid()). Body is
-- otherwise unchanged from 20260605_leaderboard.sql.

create or replace function get_leaderboard(p_user_id uuid)
returns table (
    rank            bigint,
    user_id         uuid,
    email           text,
    streak_current  int,
    streak_best     int,
    total_completed bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_family_id uuid;
begin
    -- Authorization: callers may only read their own family's leaderboard.
    if p_user_id is distinct from auth.uid() then
        raise exception 'not authorized';
    end if;

    -- Lookup caller's family
    select family_id into v_family_id from users where id = p_user_id;

    return query
    with candidate_ids as (
        -- Family members (if any), always include the caller
        select u.id
        from   users u
        where  (v_family_id is not null and u.family_id = v_family_id)
           or  u.id = p_user_id

        union  -- also include family member records stored in family_members table
        select fm.child_user_id
        from   family_members fm
        where  v_family_id is not null and fm.family_id = v_family_id
    ),
    streak_data as (
        -- compute current streak per user from their activity reports
        select
            a.user_id,
            -- streak = consecutive qualifying days ending today/yesterday
            coalesce(
                (
                    with day_counts as (
                        select
                            date_trunc('day', r.created_at at time zone 'utc') as day,
                            count(*) as cnt
                        from reports r
                        join activities act on act.id = r.activity_id
                        where act.user_id = a.user_id
                        group by 1
                        having count(*) >= 3   -- minDailyActivitiesForStreak
                    ),
                    ranked as (
                        select day,
                               row_number() over (order by day desc) as rn
                        from day_counts
                        where day >= current_date - interval '200 days'
                    ),
                    consecutive as (
                        select day, rn,
                               (day + (rn * interval '1 day'))::date as grp
                        from ranked
                    )
                    select count(*)
                    from consecutive
                    where grp = (
                        select min(grp) from consecutive
                        where day >= current_date - interval '1 day'
                    )
                ),
                0
            ) as streak_current,
            coalesce(a.streak_best, 0) as streak_best
        from (
            select distinct user_id, max(streak_best) as streak_best
            from activities
            where user_id in (select id from candidate_ids)
            group by user_id
        ) a
    ),
    completed as (
        select user_id, count(*) as total_completed
        from activities
        where status = 'completed'
          and user_id in (select id from candidate_ids)
        group by user_id
    )
    select
        rank() over (order by coalesce(s.streak_current, 0) desc, coalesce(c.total_completed, 0) desc)::bigint,
        u.id,
        u.email,
        coalesce(s.streak_current, 0)::int,
        coalesce(s.streak_best, 0)::int,
        coalesce(c.total_completed, 0)
    from candidate_ids ci
    join users u on u.id = ci.id
    left join streak_data s on s.user_id = ci.id
    left join completed c on c.user_id = ci.id
    order by 1
    limit 50;
end;
$$;

grant execute on function get_leaderboard(uuid) to authenticated;
