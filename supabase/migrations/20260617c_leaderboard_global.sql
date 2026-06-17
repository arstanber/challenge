-- Leaderboard goes global. Previously get_leaderboard only ranked the caller's
-- own family, so a user with no family saw only themselves -- which contradicts
-- the in-app reward copy ("Топ-3 среди всех пользователей получают PRO дни").
--
-- This version ranks ALL users by current streak, returns the global top 50,
-- and always appends the caller's own row if they fall outside the top 50.
--
-- Privacy: a global board must not leak emails to strangers. The email column is
-- returned only for the caller's own row (null otherwise), and the display name
-- falls back to a generic label ("Пользователь") for other users who have not
-- set a display_name -- never to their email local part.
--
-- Return shape is identical to 20260617b_leaderboard_names_avatars.sql.

drop function if exists get_leaderboard(uuid);

create function get_leaderboard(p_user_id uuid)
returns table (
    rank            bigint,
    user_id         uuid,
    email           text,
    display_name    text,
    avatar_url      text,
    streak_current  int,
    streak_best     int,
    total_completed bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
    -- Authorization: callers may only request their own leaderboard view.
    if p_user_id is distinct from auth.uid() then
        raise exception 'not authorized';
    end if;

    return query
    with streak_data as (
        -- Streak + best for every user. compute_user_streak runs per user; fine
        -- at the current user scale. The p_min arg (3) is legacy and ignored.
        select u.id as uid,
               s.current_streak,
               greatest(
                 s.best_streak,
                 coalesce((select max(act.streak_best) from activities act
                           where act.user_id = u.id), 0)
               ) as best_streak
        from users u
        cross join lateral compute_user_streak(u.id, 3) s
    ),
    completed as (
        select a.user_id as uid, count(*) as total_completed
        from activities a
        where a.status = 'completed'
        group by a.user_id
    ),
    ranked as (
        select
            rank() over (order by coalesce(s.current_streak, 0) desc,
                                  coalesce(c.total_completed, 0) desc)::bigint as rnk,
            u.id as uid,
            u.email,
            u.display_name as raw_display_name,
            u.avatar_url,
            coalesce(s.current_streak, 0)::int as streak_current,
            coalesce(s.best_streak, 0)::int as streak_best,
            coalesce(c.total_completed, 0) as total_completed
        from users u
        left join streak_data s on s.uid = u.id
        left join completed c on c.uid = u.id
    )
    select
        r.rnk,
        r.uid,
        case when r.uid = p_user_id then r.email end as email,
        coalesce(
            nullif(r.raw_display_name, ''),
            case when r.uid = p_user_id
                 then split_part(r.email, '@', 1)
                 else 'Пользователь' end
        ) as display_name,
        r.avatar_url,
        r.streak_current,
        r.streak_best,
        r.total_completed
    from ranked r
    -- Global top 50, plus the caller's own row if they rank lower.
    where r.rnk <= 50 or r.uid = p_user_id
    order by r.rnk, r.total_completed desc, display_name;
end;
$$;

grant execute on function get_leaderboard(uuid) to authenticated;
revoke execute on function get_leaderboard(uuid) from public, anon;
