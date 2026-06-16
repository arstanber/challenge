-- Bind a data connector to a task at creation time.
--
-- When the user types a connector name while creating a task (e.g. "Chess.com")
-- and picks one of its capabilities ("Сыгранные партии"), we record which
-- connector + metric drives the task's progress. ConnectorService.todayValue
-- reads exactly this binding instead of guessing the metric from the title --
-- which is why Chess.com game counts (metric "itemsToday") never worked before.
--
-- Both columns are nullable text; an unset task behaves exactly as before.
-- Values mirror the Swift enums: DataConnector.rawValue (e.g. "chessCom") and
-- ConnectorMetric.rawValue (e.g. "itemsToday").

alter table public.activities
  add column if not exists connector        text,
  add column if not exists connector_metric text;

comment on column public.activities.connector is
  'DataConnector.rawValue bound to this task for auto-tracking (nullable).';
comment on column public.activities.connector_metric is
  'ConnectorMetric.rawValue the bound connector reads for this task (nullable).';
