-- ============ Welcome trial: 7 days of PRO for every new account ============
-- The post-registration "Week on us" screen (WeekOnUsView) tells the user the
-- trial is already active; this default is what actually activates it.
--
-- Temporary PRO lives in users.pro_until (20260612c_referrals.sql). Both the
-- client (AppUser.isPremium) and check_and_increment_usage already treat a
-- future pro_until as premium, so no other changes are needed. Referral
-- rewards extend from greatest(pro_until, now()) and stack cleanly on top.
--
-- Only affects newly inserted rows; existing users keep their current value.

alter table public.users
  alter column pro_until set default (now() + interval '7 days');
