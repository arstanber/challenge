-- Ensure PostgREST discovers the routines RPCs after the schema migration.
notify pgrst, 'reload schema';
