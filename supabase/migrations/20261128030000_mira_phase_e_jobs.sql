create table if not exists public.mira_operation_daily_calls (
  member_id uuid not null references public.members(id),
  operation text not null,
  day_utc date not null,
  calls integer not null check (calls > 0),
  primary key (member_id, operation, day_utc)
);

alter table public.mira_operation_daily_calls enable row level security;
revoke all on public.mira_operation_daily_calls from public, anon, authenticated;
grant select, insert, update on public.mira_operation_daily_calls to service_role;

create or replace function public.mira_operation_daily_limit(p_operation text)
returns integer language sql immutable set search_path = public as $$
  select case p_operation
    when 'brandDoc' then 5
    when 'pickIdea' then 20
    when 'dealBrief' then 10
    when 'briefCheck' then 10
    when 'brandNote' then 10
    when 'dailyNote' then 1
  end;
$$;

revoke all on function public.mira_operation_daily_limit(text) from public, anon, authenticated;
grant execute on function public.mira_operation_daily_limit(text) to service_role;

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

  update public.mira_generation_jobs set status='failed',error='unreconciled_job_expired',updated_at=now()
    where member_id=p_member and created_at<now()-interval '15 minutes'
      and (status='queued' or (status='running' and lease_until<now()));
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
  if daily_limit is not null then
    perform pg_advisory_xact_lock(hashtextextended(job.member_id::text, 0));
    claim_day := (clock_timestamp() at time zone 'UTC')::date;
  end if;

  if operation_name = 'dailyNote' then
    update public.mira_generation_jobs
      set status = 'failed', error = 'daily_note_expired', updated_at = clock_timestamp()
      where id = p_id and (
        (status = 'queued' and (created_at at time zone 'UTC')::date <> claim_day)
        or (status = 'running' and lease_until <= clock_timestamp())
      );
  end if;

  update public.mira_generation_jobs
    set status = 'failed', error = 'worker_interrupted_retry_limit', updated_at = clock_timestamp()
    where id = p_id and status = 'running' and lease_until <= clock_timestamp() and attempts >= 3;

  update public.mira_generation_jobs
    set status = 'running', attempts = attempts + 1, lease_id = gen_random_uuid(), step = null,
        lease_until = clock_timestamp() + make_interval(secs => p_lease_seconds), updated_at = clock_timestamp()
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

  if new.status = 'running'
     and (old.status = 'queued' or (old.status = 'running' and old.lease_until <= clock_timestamp()))
     and old.attempts < 3 and new.attempts = old.attempts + 1
     and (old.input->>'operation' is distinct from 'dailyNote' or old.attempts = 0)
     and old.next_attempt_at <= clock_timestamp()
     and new.lease_id is not null and new.lease_id is distinct from old.lease_id
     and new.lease_until > clock_timestamp() then
    return new;
  end if;

  if new.attempts = old.attempts
     and new.lease_id is not distinct from old.lease_id
     and new.lease_until is not distinct from old.lease_until
     and (
       (old.status = 'queued' and new.status in ('failed', 'cancelled'))
       or (old.status = 'running' and new.status in ('succeeded', 'failed', 'cancelled'))
       or (old.status = 'running' and new.status = 'queued' and old.attempts < 3
           and old.input->>'operation' is distinct from 'dailyNote')
     ) then
    return new;
  end if;

  raise exception using errcode = '23514', message = 'mira_invalid_job_transition',
    detail = format('%s -> %s', old.status, new.status);
end $$;

create or replace function public.mira_claim_shot_pictures(
  p_job_id uuid, p_lease_id uuid, p_lease_seconds integer
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

  if not exists (select from public.mira_shot_pictures where job_id = p_job_id) then
    day_start := date_trunc('day', reserved_time, 'UTC');
    select greatest(0, 30 - count(*)) into remaining
      from public.mira_shot_pictures
      where member_id = card.member_id and reserved_at >= day_start;
    insert into public.mira_shot_pictures (
      job_id, shot_id, member_id, position, status, reserved_at, lease_id, lease_until
    )
    select card.id, (shot.value->>'id')::uuid, card.member_id, shot.ordinality,
      case when shot.ordinality <= remaining then 'generating' else 'failed' end,
      case when shot.ordinality <= remaining then reserved_time end,
      case when shot.ordinality <= remaining then p_lease_id end,
      case when shot.ordinality <= remaining then reserved_time + make_interval(secs => p_lease_seconds) end
    from jsonb_array_elements(card.output->'storyboard'->'shots') with ordinality shot(value, ordinality)
    where shot.ordinality <= card.picture_count;
  end if;

  return query select * from public.mira_shot_pictures where job_id = p_job_id order by position;
end $$;
