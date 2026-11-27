alter table public.mira_generation_jobs
  add column if not exists provider_started boolean not null default false;

alter table public.mira_shot_pictures
  add column if not exists dispatch_tracked boolean not null default false,
  add column if not exists started_at timestamptz;

create table if not exists public.mira_job_cancellations (
  job_id uuid not null,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  creator_id uuid not null references public.creators(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  primary key (job_id, workspace_id, creator_id, member_id)
);

alter table public.mira_job_cancellations enable row level security;
revoke all on public.mira_job_cancellations from public, anon, authenticated;

create or replace function public.mira_cancel(
  p_id uuid, p_workspace uuid, p_creator uuid, p_member uuid
)
returns public.mira_generation_jobs language plpgsql security definer set search_path = public as $$
declare
  job public.mira_generation_jobs;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_member::text, 0));
  select * into job from public.mira_generation_jobs
    where id = p_id and workspace_id = p_workspace and creator_id = p_creator and member_id = p_member
    for update;
  if not found then
    insert into public.mira_job_cancellations (job_id, workspace_id, creator_id, member_id)
      values (p_id, p_workspace, p_creator, p_member) on conflict do nothing;
    return null;
  end if;

  if job.status in ('queued', 'running') then
    update public.mira_generation_jobs
      set status = 'cancelled', updated_at = clock_timestamp()
      where id = p_id returning * into job;
  end if;
  return job;
end $$;

revoke all on function public.mira_cancel(uuid, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.mira_cancel(uuid, uuid, uuid, uuid) to service_role;

create or replace function public.mira_enqueue(
  p_id uuid, p_workspace uuid, p_creator uuid, p_member uuid, p_revision integer, p_input jsonb
)
returns public.mira_generation_jobs language plpgsql security definer set search_path = public as $$
declare
  existing public.mira_generation_jobs;
  result public.mira_generation_jobs;
  operation_name text := p_input->>'operation';
  daily_limit integer := public.mira_operation_daily_limit(operation_name);
  request_time timestamptz;
  day_start timestamptz;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_member::text, 0));
  select * into existing from public.mira_generation_jobs where id = p_id;
  if found then
    if existing.workspace_id <> p_workspace or existing.creator_id <> p_creator or existing.member_id <> p_member
       or existing.input_revision <> p_revision or existing.input <> p_input then
      raise exception 'idempotency_conflict';
    end if;
    return existing;
  end if;

  if exists (
    select from public.mira_job_cancellations
      where job_id = p_id and workspace_id = p_workspace and creator_id = p_creator and member_id = p_member
  ) then
    raise exception 'job_cancelled_before_start';
  end if;

  request_time := clock_timestamp();
  day_start := date_trunc('day', request_time, 'UTC');
  if operation_name = 'dailyNote' then
    select * into existing from public.mira_generation_jobs
      where member_id = p_member and input->>'operation' = 'dailyNote'
        and created_at >= day_start
      order by created_at, id limit 1;
    if found then
      if existing.workspace_id <> p_workspace or existing.creator_id <> p_creator then
        raise exception 'daily_note_scope_conflict';
      end if;
      return existing;
    end if;
  end if;

  if daily_limit is not null and exists (
    select from public.mira_operation_daily_calls
      where member_id = p_member and operation = operation_name
        and day_utc = (day_start at time zone 'UTC')::date and calls >= daily_limit
  ) then
    raise exception 'operation_daily_cap_reached';
  end if;

  update public.mira_generation_jobs
    set status = case when output is not null then 'succeeded' else 'failed' end,
        error = case when output is null then 'unreconciled_job_expired' end, updated_at = now()
    where member_id = p_member and created_at < now() - interval '15 minutes'
      and (status = 'queued' or (status = 'running' and lease_until < now()));
  if (select count(*) from public.mira_generation_jobs where member_id = p_member and created_at > now() - interval '1 minute') >= 10 then
    raise exception 'rate_limited';
  end if;
  if (select count(*) from public.mira_generation_jobs where member_id = p_member and status in ('queued','running')) >= 3 then
    raise exception 'too_many_active_jobs';
  end if;
  insert into public.mira_generation_jobs(id, workspace_id, creator_id, member_id, input_revision, input, created_at)
    values(p_id, p_workspace, p_creator, p_member, p_revision, p_input,
      case when operation_name = 'dailyNote' then request_time else now() end)
    returning * into result;
  return result;
end $$;

create or replace function public.mira_claim(p_id uuid, p_lease_seconds integer)
returns setof public.mira_generation_jobs language plpgsql security definer set search_path = public as $$
declare
  job public.mira_generation_jobs;
  operation_name text;
  daily_limit integer;
  claim_day date;
begin
  if p_lease_seconds is null or p_lease_seconds < 90 then
    raise exception using errcode = '22023', message = 'mira_lease_too_short';
  end if;

  select * into job from public.mira_generation_jobs where id = p_id;
  if not found then return; end if;
  operation_name := job.input->>'operation';
  daily_limit := public.mira_operation_daily_limit(operation_name);
  perform pg_advisory_xact_lock(hashtextextended(job.member_id::text, 0));
  if daily_limit is not null then
    claim_day := (clock_timestamp() at time zone 'UTC')::date;
  end if;

  perform from public.mira_generation_jobs where id = p_id for update;

  update public.mira_generation_jobs
    set status = 'succeeded', error = null, updated_at = clock_timestamp()
    where id = p_id and status = 'running' and output is not null;
  if found then return; end if;

  if operation_name = 'dailyNote' then
    update public.mira_generation_jobs
      set status = 'failed', error = 'daily_note_expired', updated_at = clock_timestamp()
      where id = p_id and (
        (status = 'queued' and (created_at at time zone 'UTC')::date <> claim_day)
        or (status = 'running' and lease_until <= clock_timestamp())
      );
  end if;

  update public.mira_generation_jobs
    set status = 'failed', error = 'worker_interrupted_after_dispatch', updated_at = clock_timestamp()
    where id = p_id and status = 'running' and lease_until <= clock_timestamp() and provider_started;

  update public.mira_generation_jobs
    set status = 'failed', error = 'worker_interrupted_retry_limit', updated_at = clock_timestamp()
    where id = p_id and status = 'running' and lease_until <= clock_timestamp() and attempts >= 3;

  update public.mira_generation_jobs
    set status = 'running', attempts = attempts + 1, lease_id = gen_random_uuid(), step = null,
        lease_until = clock_timestamp() + make_interval(secs => greatest(p_lease_seconds, 91)),
        updated_at = clock_timestamp()
    where id = p_id and attempts < 3 and next_attempt_at <= clock_timestamp()
      and (status = 'queued' or (status = 'running' and lease_until <= clock_timestamp()))
      and (operation_name is distinct from 'dailyNote' or attempts = 0)
    returning * into job;
  if not found then return; end if;

  if daily_limit is not null then
    insert into public.mira_operation_daily_calls as usage (member_id, operation, day_utc, calls)
      values (job.member_id, operation_name, claim_day, 1)
      on conflict (member_id, operation, day_utc) do update
        set calls = usage.calls + 1 where usage.calls < daily_limit;
    if not found then
      update public.mira_generation_jobs
        set status = 'failed', error = 'operation_daily_cap_reached', updated_at = clock_timestamp()
        where id = p_id;
      return;
    end if;
  end if;

  return next job;
end $$;

create or replace function public.mira_enforce_job_transition()
returns trigger language plpgsql set search_path = public as $$
begin
  if old.status = 'running' and new.status = 'running'
     and old.lease_until > clock_timestamp()
     and old.input->>'operation' in ('todayIdea', 'pickIdea')
     and array_position(array['idea_ready', 'script_ready', 'storyboard_ready'], new.step)
         > coalesce(array_position(array['idea_ready', 'script_ready', 'storyboard_ready'], old.step), 0)
     and (to_jsonb(new) - array['step', 'updated_at']) = (to_jsonb(old) - array['step', 'updated_at']) then
    return new;
  end if;

  if old.status = 'running' and new.status = 'running'
     and (
       (not old.provider_started and new.provider_started and old.lease_until > clock_timestamp()
        and (to_jsonb(new) - array['provider_started', 'updated_at'])
          = (to_jsonb(old) - array['provider_started', 'updated_at']))
       or (old.provider_started and old.output is null and new.output is not null and new.output <> 'null'::jsonb
        and (to_jsonb(new) - array['output', 'picture_count', 'updated_at'])
          = (to_jsonb(old) - array['output', 'picture_count', 'updated_at']))
     ) then
    return new;
  end if;

  if new.status = 'running'
     and not old.provider_started and not new.provider_started
     and old.output is null and new.output is null
     and (old.status = 'queued' or (old.status = 'running' and old.lease_until <= clock_timestamp()))
     and old.attempts < 3 and new.attempts = old.attempts + 1
     and (old.input->>'operation' is distinct from 'dailyNote' or old.attempts = 0)
     and old.next_attempt_at <= clock_timestamp()
     and new.lease_id is not null and new.lease_id is distinct from old.lease_id
     and new.lease_until >= clock_timestamp() + interval '90 seconds' then
    return new;
  end if;

  if new.attempts = old.attempts
     and new.lease_id is not distinct from old.lease_id
     and new.lease_until is not distinct from old.lease_until
     and (
       (old.status in ('queued', 'running') and new.status = 'failed' and new.error is not null
           and old.output is null and new.output is null)
       or (old.status in ('queued', 'running') and new.status = 'cancelled'
           and new.output is not distinct from old.output)
       or (old.status = 'running' and new.status = 'succeeded' and new.output is not null
           and new.output <> 'null'::jsonb and (old.output is null or new.output = old.output))
       or (old.status = 'running' and new.status = 'queued' and old.attempts < 3
           and old.input->>'operation' is distinct from 'dailyNote'
           and old.output is null and new.output is null and not new.provider_started)
     ) then
    return new;
  end if;

  raise exception using errcode = '23514', message = 'mira_invalid_job_transition',
    detail = format('%s -> %s', old.status, new.status);
end $$;

create or replace function public.mira_claim_shot_pictures(
  p_job_id uuid, p_lease_id uuid, p_lease_seconds integer, p_track_dispatch boolean
)
returns setof public.mira_shot_pictures
language plpgsql security definer set search_path = public as $$
declare
  card public.mira_generation_jobs;
  reserved_time timestamptz;
  day_start timestamptz;
  remaining integer;
begin
  if p_lease_id is null or p_lease_seconds is null or p_lease_seconds < 125 then
    raise exception using errcode = '22023', message = 'mira_picture_lease_too_short';
  end if;
  select * into card from public.mira_generation_jobs
    where id = p_job_id and status = 'succeeded' and input->>'operation' in ('todayIdea', 'pickIdea')
      and picture_count > 0;
  if not found then return; end if;

  perform pg_advisory_xact_lock(hashtextextended(card.member_id::text, 2));
  reserved_time := clock_timestamp();
  update public.mira_shot_pictures picture
    set status = case when exists (
      select from storage.objects object
        where object.bucket_id = 'mira-shot-pictures' and object.name = picture.object_path
    ) then 'ready' else 'failed' end
    where picture.job_id = p_job_id and picture.status = 'generating'
      and picture.lease_until <= reserved_time;

  update public.mira_shot_pictures picture
    set status = 'ready'
    where picture.job_id = p_job_id and picture.status = 'failed' and picture.lease_id is not null
      and exists (
        select from storage.objects object
          where object.bucket_id = 'mira-shot-pictures' and object.name = picture.object_path
      );

  if not exists (select from public.mira_shot_pictures where job_id = p_job_id) then
    day_start := date_trunc('day', reserved_time, 'UTC');
    select greatest(0, 30 - count(*)) into remaining
      from public.mira_shot_pictures
      where member_id = card.member_id and reserved_at >= day_start
        and (not dispatch_tracked or started_at is not null
          or (status = 'generating' and lease_until > reserved_time));
    insert into public.mira_shot_pictures (
      job_id, shot_id, member_id, position, status, reserved_at, lease_id, lease_until, dispatch_tracked
    )
    select card.id, (shot.value->>'id')::uuid, card.member_id, shot.ordinality,
      case when shot.ordinality <= remaining then 'generating' else 'failed' end,
      case when shot.ordinality <= remaining then reserved_time end,
      case when shot.ordinality <= remaining then p_lease_id end,
      case when shot.ordinality <= remaining then reserved_time + make_interval(secs => p_lease_seconds) end,
      p_track_dispatch
    from jsonb_array_elements(card.output->'storyboard'->'shots') with ordinality shot(value, ordinality)
    where shot.ordinality <= card.picture_count
    on conflict (job_id, shot_id) do nothing;
  end if;

  return query select * from public.mira_shot_pictures where job_id = p_job_id order by position;
end $$;

revoke all on function public.mira_claim_shot_pictures(uuid, uuid, integer, boolean) from public, anon, authenticated;
grant execute on function public.mira_claim_shot_pictures(uuid, uuid, integer, boolean) to service_role;

create or replace function public.mira_claim_shot_pictures(
  p_job_id uuid, p_lease_id uuid, p_lease_seconds integer
)
returns setof public.mira_shot_pictures language sql security definer set search_path = public as $$
  select * from public.mira_claim_shot_pictures(p_job_id, p_lease_id, p_lease_seconds, false);
$$;

create or replace function public.mira_start_shot_picture(p_job_id uuid, p_shot_id uuid, p_lease_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  owner_id uuid;
begin
  select member_id into owner_id from public.mira_shot_pictures
    where job_id = p_job_id and shot_id = p_shot_id;
  if not found then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended(owner_id::text, 2));
  update public.mira_shot_pictures
    set started_at = clock_timestamp()
    where job_id = p_job_id and shot_id = p_shot_id and lease_id = p_lease_id
      and status = 'generating' and started_at is null and lease_until > clock_timestamp();
  return found;
end $$;

revoke all on function public.mira_start_shot_picture(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.mira_start_shot_picture(uuid, uuid, uuid) to service_role;
