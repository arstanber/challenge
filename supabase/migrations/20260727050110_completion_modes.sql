alter table public.activities
  add column if not exists completion_mode text not null default 'check',
  add column if not exists completion_unit text;

alter table public.activities
  drop constraint if exists activities_completion_mode_check;

alter table public.activities
  add constraint activities_completion_mode_check
  check (completion_mode in ('check', 'counter', 'timer', 'abstinence'));

alter table public.activities
  drop constraint if exists activities_completion_unit_length_check;

alter table public.activities
  add constraint activities_completion_unit_length_check
  check (completion_unit is null or char_length(completion_unit) <= 32);

-- Existing numeric goals already behave as counters. Preserve that behavior
-- while regular tasks and habits keep the simple check mode.
update public.activities
set completion_mode = 'counter'
where goal_target > 0
  and completion_mode = 'check';

comment on column public.activities.completion_mode is
  'How completion is recorded: check, counter, timer, or abstinence.';

comment on column public.activities.completion_unit is
  'Short reader-facing unit for counter/timer progress, for example pages or min.';
