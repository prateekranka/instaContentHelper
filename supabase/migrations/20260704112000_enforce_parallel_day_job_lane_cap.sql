-- Enforce the weekly day-job lane cap inside the database claim/reclaim RPCs.
-- App-side post-claim checks are useful diagnostics, but concurrent Edge
-- isolates can still race. The advisory transaction lock serializes queue
-- ownership changes per generation run, and the live-count check happens
-- inside that critical section before a new lease is handed out.

drop function if exists public.claim_queued_day_job(uuid, text, text);
drop function if exists public.reclaim_stale_day_job(uuid, text, text, integer, integer);

create or replace function public.claim_queued_day_job(
  p_generation_run_id uuid,
  p_lease_token text,
  p_worker_boot_id text default null,
  p_max_live_jobs integer default 4,
  p_stale_threshold_ms integer default 240000
)
returns setof public.weekly_generation_day_jobs
language plpgsql
as $$
declare
  v_max_live_jobs integer := greatest(1, least(coalesce(p_max_live_jobs, 4), 7));
  v_stale_threshold_ms integer := greatest(
    30000,
    least(coalesce(p_stale_threshold_ms, 240000), 600000)
  );
  v_live_jobs integer;
begin
  perform pg_advisory_xact_lock(
    hashtext('weekly_generation_day_jobs'),
    hashtext(p_generation_run_id::text)
  );

  select count(*)
    into v_live_jobs
  from public.weekly_generation_day_jobs
  where generation_run_id = p_generation_run_id
    and status = 'generating'
    and (
      coalesce(heartbeat_at, started_at) is null
      or coalesce(heartbeat_at, started_at) >=
        now() - (v_stale_threshold_ms || ' milliseconds')::interval
    );

  if v_live_jobs >= v_max_live_jobs then
    return;
  end if;

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
    status         = 'generating',
    lease_token    = p_lease_token,
    worker_boot_id = p_worker_boot_id,
    started_at     = coalesce(j.started_at, now()),
    heartbeat_at   = now(),
    attempt_count  = j.attempt_count + 1,
    error_code     = null,
    error_message  = null,
    staged_output  = null,
    completed_at   = null,
    updated_at     = now()
  from claimed
  where j.id = claimed.id
    and j.status in ('queued', 'retrying')
  returning j.*;
end;
$$;

create or replace function public.reclaim_stale_day_job(
  p_generation_run_id uuid,
  p_lease_token text,
  p_worker_boot_id text default null,
  p_stale_threshold_ms integer default 240000,
  p_max_attempts integer default 2,
  p_max_live_jobs integer default 4
)
returns setof public.weekly_generation_day_jobs
language plpgsql
as $$
declare
  v_max_live_jobs integer := greatest(1, least(coalesce(p_max_live_jobs, 4), 7));
  v_stale_threshold_ms integer := greatest(
    30000,
    least(coalesce(p_stale_threshold_ms, 240000), 600000)
  );
  v_max_attempts integer := greatest(1, coalesce(p_max_attempts, 2));
  v_live_jobs integer;
begin
  perform pg_advisory_xact_lock(
    hashtext('weekly_generation_day_jobs'),
    hashtext(p_generation_run_id::text)
  );

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
    and heartbeat_at < now() - (v_stale_threshold_ms || ' milliseconds')::interval
    and attempt_count >= v_max_attempts;

  select count(*)
    into v_live_jobs
  from public.weekly_generation_day_jobs
  where generation_run_id = p_generation_run_id
    and status = 'generating'
    and (
      coalesce(heartbeat_at, started_at) is null
      or coalesce(heartbeat_at, started_at) >=
        now() - (v_stale_threshold_ms || ' milliseconds')::interval
    );

  if v_live_jobs >= v_max_live_jobs then
    return;
  end if;

  return query
  with stale as (
    select id
    from public.weekly_generation_day_jobs
    where generation_run_id = p_generation_run_id
      and status = 'generating'
      and heartbeat_at is not null
      and heartbeat_at < now() - (v_stale_threshold_ms || ' milliseconds')::interval
      and attempt_count < v_max_attempts
    order by day_index asc
    limit 1
    for update skip locked
  )
  update public.weekly_generation_day_jobs j
  set
    lease_token    = p_lease_token,
    worker_boot_id = p_worker_boot_id,
    heartbeat_at   = now(),
    started_at     = now(),
    attempt_count  = j.attempt_count + 1,
    error_code     = null,
    error_message  = null,
    staged_output  = null,
    completed_at   = null,
    updated_at     = now()
  from stale
  where j.id = stale.id
    and j.status = 'generating'
    and j.heartbeat_at is not null
    and j.heartbeat_at < now() - (v_stale_threshold_ms || ' milliseconds')::interval
    and j.attempt_count < v_max_attempts
  returning j.*;
end;
$$;

revoke execute on function public.claim_queued_day_job(uuid, text, text, integer, integer)
  from public, anon, authenticated;
revoke execute on function public.reclaim_stale_day_job(uuid, text, text, integer, integer, integer)
  from public, anon, authenticated;

grant execute on function public.claim_queued_day_job(uuid, text, text, integer, integer)
  to service_role;
grant execute on function public.reclaim_stale_day_job(uuid, text, text, integer, integer, integer)
  to service_role;

notify pgrst, 'reload schema';
