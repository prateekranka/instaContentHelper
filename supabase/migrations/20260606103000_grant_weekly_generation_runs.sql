alter table public.weekly_generation_runs enable row level security;

grant all privileges on table public.weekly_generation_runs to service_role;
