-- Child accounts must set a real email + password on first sign-in.
--
-- Parent-provisioned children start with a synthetic email
-- (kid.<code>@kids.thechallenges.app) and a PIN-derived password. The app now
-- forces the child to register a real email + password the first time they
-- enter the account; the `set-child-credentials` edge function performs the
-- change (admin API, no email confirmation) and flips this flag. Parents can
-- change a child's credentials later through the same function.

alter table public.users
  add column if not exists child_credentials_set boolean not null default false;

-- Existing self-registered (non-child) accounts already have real credentials.
update public.users set child_credentials_set = true where is_child_account is not true;
