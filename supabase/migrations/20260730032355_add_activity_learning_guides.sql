create table public.activity_learning_guides (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.activities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  language text not null check (language in ('en', 'ru', 'de', 'kk', 'fr', 'ar')),
  source_fingerprint text not null,
  guide jsonb not null,
  generated_at timestamptz not null default now(),
  unique (activity_id, language)
);

create index activity_learning_guides_user_id_idx
  on public.activity_learning_guides(user_id);

alter table public.activity_learning_guides enable row level security;

create policy "Users can read their own learning guides"
  on public.activity_learning_guides
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

grant select on table public.activity_learning_guides to authenticated;
revoke insert, update, delete on table public.activity_learning_guides from anon, authenticated;

comment on table public.activity_learning_guides is
  'Server-generated Perplexity learning guides cached per activity and language.';
