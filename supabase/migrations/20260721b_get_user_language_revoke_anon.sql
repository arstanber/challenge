-- get_user_language was reachable by anon over /rest/v1/rpc, letting anyone
-- resolve any user's language from their UUID without signing in.
--
-- Postgres grants EXECUTE to PUBLIC by default on new functions, so the
-- explicit `grant ... to authenticated` in 20260721_user_language_all_locales
-- added nothing and removed nothing -- anon kept access through PUBLIC.
-- Caught by the Supabase linter (0028_anon_security_definer_function_executable).
--
-- The function stays SECURITY DEFINER on purpose: a signed-in client must be
-- able to resolve ANOTHER user's language (a duel opponent, for a cross-user
-- push) and users RLS only exposes family members. It returns the language code
-- and nothing else from the row.

revoke execute on function public.get_user_language(uuid) from public;
revoke execute on function public.get_user_language(uuid) from anon;
grant execute on function public.get_user_language(uuid) to authenticated;
