-- Assignment groups: link the per-child activity rows a parent creates in one
-- "assign task" action so the app can show, per assignment, which children have
-- completed it. When a parent assigns a task to one or several children, every
-- resulting activities row shares the same assignment_group_id.
--
-- Backward compatible: existing assignments have a NULL group id and are treated
-- as a single-row group by the client (keyed on the activity id).

alter table public.activities
  add column if not exists assignment_group_id uuid;

create index if not exists idx_activities_assignment_group
  on public.activities (assignment_group_id)
  where assignment_group_id is not null;
