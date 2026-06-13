-- Codify columns the app has long written to activities but that never had a
-- migration (they were added ad hoc on the live DB). This file is idempotent
-- and a no-op on the production database; its purpose is fresh-DB parity so a
-- rebuild from migrations matches production, plus an index for subtask reads.
--
--   parent_id    -- subtasks point at their goal parent (3.3 depends on this)
--   sort_order   -- manual home-screen ordering (ReorderSheet / persistOrder)
--   plan_id      -- groups activities created from one AI goal plan
--   plan_title   -- denormalized plan name for display
--   workspace_id -- optional workspace container
--   category     -- optional free-text category tag

alter table public.activities add column if not exists parent_id uuid;
alter table public.activities add column if not exists sort_order int not null default 0;
alter table public.activities add column if not exists plan_id uuid;
alter table public.activities add column if not exists plan_title text;
alter table public.activities add column if not exists workspace_id uuid;
alter table public.activities add column if not exists category text;

-- Foreign keys (guarded so re-running / live DB is untouched).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'activities_parent_id_fkey'
  ) then
    alter table public.activities
      add constraint activities_parent_id_fkey
      foreign key (parent_id) references public.activities(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'activities_workspace_id_fkey'
  ) then
    alter table public.activities
      add constraint activities_workspace_id_fkey
      foreign key (workspace_id) references public.workspaces(id) on delete set null;
  end if;
end $$;

create index if not exists idx_activities_parent on public.activities (parent_id);
