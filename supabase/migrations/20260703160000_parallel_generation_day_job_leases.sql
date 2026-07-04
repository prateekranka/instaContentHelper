-- Add lease-ownership columns and staged-output support to durable day-job table.
-- These let the parallel week-generation lane use guarded atomic operations
-- so only the owning worker can heartbeat, complete, fail, or stage output.
alter table public.weekly_generation_day_jobs
  add column if not exists lease_token text,
  add column if not exists worker_boot_id text,
  add column if not exists staged_output jsonb;

comment on column public.weekly_generation_day_jobs.lease_token is
  'Opaque token set by the claiming worker. All mutating operations (heartbeat, complete, fail, stage) must match this token.';

comment on column public.weekly_generation_day_jobs.worker_boot_id is
  'Execution / boot identifier for shutdown telemetry only; never used for ownership checks.';

comment on column public.weekly_generation_day_jobs.staged_output is
  'JSONB column holding the validated GeneratedDayOutput. Only written atomically when the owning worker stages its output. A late worker whose lease was replaced cannot stage or persist its output.';

-- Safe constraint extension: add ready_to_persist to the valid statuses.
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'weekly_generation_day_jobs_status_check'
      and conrelid = 'public.weekly_generation_day_jobs'::regclass
      and pg_get_constraintdef(oid) not like '%ready_to_persist%'
  ) then
    alter table public.weekly_generation_day_jobs
      drop constraint weekly_generation_day_jobs_status_check;
    alter table public.weekly_generation_day_jobs
      add constraint weekly_generation_day_jobs_status_check check (
        status in ('queued','generating','generated','failed','retrying','cancelled','ready_to_persist')
      );
  elsif not exists (
    select 1 from pg_constraint
    where conname = 'weekly_generation_day_jobs_status_check'
      and conrelid = 'public.weekly_generation_day_jobs'::regclass
  ) then
    alter table public.weekly_generation_day_jobs
      add constraint weekly_generation_day_jobs_status_check check (
        status in ('queued','generating','generated','failed','retrying','cancelled','ready_to_persist')
      );
  end if;
end;
$$;

-- Index for fast lookup by lease (used for expire/reclaim diagnostics).
create index if not exists weekly_generation_day_jobs_lease_idx
  on public.weekly_generation_day_jobs(lease_token)
  where lease_token is not null;

-- ── Atomic claim / reclaim functions (RPC-callable) ──

-- Claim the next queued or retrying job in FIFO (day_index) order.
-- Uses FOR UPDATE SKIP LOCKED so concurrent callers never block each other.
create or replace function claim_queued_day_job(
  p_generation_run_id uuid,
  p_lease_token   text,
  p_worker_boot_id text default null
)
returns setof public.weekly_generation_day_jobs
language plpgsql
as $$
begin
  return query
  with claimed as (
    select id
    from public.weekly_generation_day_jobs
    where generation_run_id = p_generation_run_id
      and status in ('queued', 'retrying')
    order by day_index asc
    limit 1
    for update skip locked
  )
  update public.weekly_generation_day_jobs j
  set
    status        = 'generating',
    lease_token   = p_lease_token,
    worker_boot_id = p_worker_boot_id,
    started_at    = coalesce(j.started_at, now()),
    heartbeat_at  = now(),
    attempt_count = j.attempt_count + 1,
    error_code    = null,
    error_message = null,
    staged_output = null,
    completed_at  = null,
    updated_at    = now()
  from claimed
  where j.id = claimed.id
    and j.status in ('queued', 'retrying')
  returning j.*;
end;
$$;

-- Reclaim a stale generating job (heartbeat expired beyond threshold).
-- Atomic: the old lease is overwritten only if the row is still generating
-- and its heartbeat is still stale at write time.
-- Enforces max attempts: a stale job at max attempts becomes terminal failed
-- with generation_timeout instead of being reclaimed.
create or replace function reclaim_stale_day_job(
  p_generation_run_id  uuid,
  p_lease_token        text,
  p_worker_boot_id     text default null,
  p_stale_threshold_ms integer default 240000,
  p_max_attempts       integer default 2
)
returns setof public.weekly_generation_day_jobs
language plpgsql
as $$
begin
  -- First: mark max-attempt stale jobs as terminal failed.
  update public.weekly_generation_day_jobs
  set
    status        = 'failed',
    error_code    = 'generation_timeout',
    error_message = 'Stale job reached max attempts without completing.',
    completed_at  = now(),
    updated_at    = now()
  where generation_run_id = p_generation_run_id
    and status = 'generating'
    and heartbeat_at is not null
    and heartbeat_at < now() - (p_stale_threshold_ms || ' milliseconds')::interval
    and attempt_count >= p_max_attempts;

  -- Then: reclaim the first eligible stale job that is still under max attempts.
  return query
  with stale as (
    select id
    from public.weekly_generation_day_jobs
    where generation_run_id = p_generation_run_id
      and status = 'generating'
      and heartbeat_at is not null
      and heartbeat_at < now() - (p_stale_threshold_ms || ' milliseconds')::interval
      and attempt_count < p_max_attempts
    order by day_index asc
    limit 1
    for update skip locked
  )
  update public.weekly_generation_day_jobs j
  set
    lease_token   = p_lease_token,
    worker_boot_id = p_worker_boot_id,
    heartbeat_at  = now(),
    started_at    = now(),
    attempt_count = j.attempt_count + 1,
    error_code    = null,
    error_message = null,
    staged_output = null,
    completed_at  = null,
    updated_at    = now()
  from stale
  where j.id = stale.id
    and j.status = 'generating'
    and j.heartbeat_at is not null
    and j.heartbeat_at < now() - (p_stale_threshold_ms || ' milliseconds')::interval
    and j.attempt_count < p_max_attempts
  returning j.*;
end;
$$;

-- Stage validated output atomically. Only succeeds if the lease token,
-- attempt count, and generating status still match. This prevents a
-- stale worker from overwriting output produced by a new owner.
create or replace function stage_day_job_output(
  p_job_id       uuid,
  p_lease_token  text,
  p_attempt      integer,
  p_output       jsonb
)
returns setof public.weekly_generation_day_jobs
language plpgsql
as $$
begin
  return query
  update public.weekly_generation_day_jobs
  set
    status        = 'ready_to_persist',
    staged_output = p_output,
    completed_at  = now(),
    updated_at    = now()
  where id            = p_job_id
    and lease_token   = p_lease_token
    and attempt_count = p_attempt
    and status        = 'generating'
  returning *;
end;
$$;

-- Revoke public/authenticated access to queue management RPCs.
-- These functions contain SKIP LOCKED + atomic ownership transitions and
-- must only be callable by the service-role Edge Function.
revoke execute on function claim_queued_day_job(uuid,text,text) from public, anon, authenticated;
revoke execute on function reclaim_stale_day_job(uuid,text,text,integer,integer) from public, anon, authenticated;
revoke execute on function stage_day_job_output(uuid,text,integer,jsonb) from public, anon, authenticated;
grant execute on function claim_queued_day_job(uuid,text,text) to service_role;
grant execute on function reclaim_stale_day_job(uuid,text,text,integer,integer) to service_role;
grant execute on function stage_day_job_output(uuid,text,integer,jsonb) to service_role;
