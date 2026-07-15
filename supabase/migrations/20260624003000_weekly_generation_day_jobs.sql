create unique index if not exists daily_cards_plan_date_id_idx
  on public.daily_cards(weekly_plan_id, scheduled_date, id);

create table if not exists public.weekly_generation_day_jobs (
  id uuid primary key default gen_random_uuid(),
  generation_run_id uuid not null
    references public.weekly_generation_runs(id) on delete cascade,
  weekly_plan_id uuid not null,
  workspace_id uuid not null,
  creator_id uuid not null,
  scheduled_date date not null,
  day_index integer not null
    check (day_index between 0 and 6),
  status text not null default 'queued'
    check (
      status in (
        'queued',
        'generating',
        'generated',
        'failed',
        'retrying',
        'cancelled'
      )
    ),
  attempt_count integer not null default 0
    check (attempt_count >= 0),
  daily_card_id uuid,
  error_code text,
  error_message text,
  started_at timestamptz,
  completed_at timestamptz,
  heartbeat_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, weekly_plan_id)
    references public.weekly_plans(workspace_id, creator_id, id) on delete cascade,
  foreign key (weekly_plan_id, scheduled_date, daily_card_id)
    references public.daily_cards(weekly_plan_id, scheduled_date, id)
    on delete set null (daily_card_id),
  constraint weekly_generation_day_jobs_generation_date_key
    unique (generation_run_id, scheduled_date),
  constraint weekly_generation_day_jobs_generation_day_key
    unique (generation_run_id, day_index)
);

create unique index if not exists weekly_generation_day_jobs_plan_date_card_idx
  on public.weekly_generation_day_jobs(weekly_plan_id, scheduled_date)
  where daily_card_id is not null;

create unique index if not exists weekly_generation_day_jobs_daily_card_idx
  on public.weekly_generation_day_jobs(daily_card_id)
  where daily_card_id is not null;

create index if not exists weekly_generation_day_jobs_claim_idx
  on public.weekly_generation_day_jobs(status, created_at, id)
  where status in ('queued', 'retrying');

create index if not exists weekly_generation_day_jobs_generating_heartbeat_idx
  on public.weekly_generation_day_jobs(heartbeat_at, started_at)
  where status = 'generating';

create index if not exists weekly_generation_day_jobs_generation_status_idx
  on public.weekly_generation_day_jobs(generation_run_id, status, day_index);

create index if not exists weekly_generation_day_jobs_workspace_status_idx
  on public.weekly_generation_day_jobs(
    workspace_id,
    creator_id,
    status,
    scheduled_date
  );

create trigger weekly_generation_day_jobs_set_updated_at
  before update on public.weekly_generation_day_jobs
  for each row execute function public.set_updated_at();

alter table public.weekly_generation_day_jobs enable row level security;

grant all privileges on table public.weekly_generation_day_jobs to service_role;

comment on table public.weekly_generation_day_jobs is
  'Durable per-day jobs for queued weekly content generation.';

comment on column public.weekly_generation_day_jobs.status is
  'queued, generating, generated, failed, retrying, or cancelled.';

comment on index public.weekly_generation_day_jobs_claim_idx is
  'Supports workers claiming queued or retrying day-generation jobs in FIFO order.';
