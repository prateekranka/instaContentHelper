-- publish_week_atomic passes weekly_plans.week_start_date (date) into
-- week_date_array(text), which Postgres rejects at runtime with:
--   function public.week_date_array(date) does not exist

create or replace function public.week_date_array(week_start_date date)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select public.week_date_array(week_start_date::text);
$$;
revoke all on function public.week_date_array(date) from public, anon, authenticated;
grant execute on function public.week_date_array(date) to service_role;
comment on function public.week_date_array(date) is
  'Date overload for publish_week_atomic; delegates to week_date_array(text).';
