-- The weekly publish Edge Function and app path are retired.
-- Keep the migration ledger for provenance, but remove the live RPC artifacts
-- that only supported publish_week_atomic.

drop function if exists public.publish_week_atomic(jsonb);
drop function if exists public.week_date_array(date);
drop function if exists public.week_date_array(text);
