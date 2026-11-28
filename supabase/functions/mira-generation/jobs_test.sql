\set ON_ERROR_STOP on
\if :{?mira_full_schema}
\else
create role anon;
create role authenticated;
create role service_role bypassrls;
create schema storage;
create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects(bucket_id text, name text);
alter table storage.objects enable row level security;
create table public.workspaces(id uuid primary key, name text not null);
create table public.creators(id uuid primary key, workspace_id uuid references public.workspaces, display_name text not null);
create table public.members(id uuid primary key, workspace_id uuid references public.workspaces, display_name text not null, role text not null);
grant insert on public.members to service_role;
\i /mira-migrations.sql
\endif

insert into public.workspaces(id, name) values
 ('10000000-0000-4000-8000-000000000001', 'Mira SQL fixture') on conflict (id) do nothing;
insert into public.creators(id, workspace_id, display_name) values
 ('10000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'Fixture creator') on conflict (id) do nothing;
insert into public.members(id, workspace_id, display_name, role) values
 ('10000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', 'Fixture member', 'creator') on conflict (id) do nothing;

begin;
set local role service_role;
do $$
declare
  job public.mira_generation_jobs;
  repeated public.mira_generation_jobs;
  claimed public.mira_generation_jobs;
  expired_id uuid := gen_random_uuid();
  exhausted_id uuid := gen_random_uuid();
  cancelled_id uuid := gen_random_uuid();
begin
  job := public.mira_enqueue(gen_random_uuid(), '10000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000003', 1, '{"operation":"ideas"}');
  repeated := public.mira_enqueue(job.id, job.workspace_id, job.creator_id, job.member_id, 1, job.input);
  assert repeated.created_at = job.created_at, 'duplicate submission created a different job';
  begin
    perform public.mira_enqueue(job.id, job.workspace_id, job.creator_id, job.member_id, 2, job.input);
    raise exception 'expected idempotency conflict';
  exception when raise_exception then
    if sqlerrm <> 'idempotency_conflict' then raise; end if;
  end;

  begin
    perform public.mira_claim(job.id, 89);
    raise exception 'short lease accepted';
  exception when invalid_parameter_value then
    if sqlerrm <> 'mira_lease_too_short' then raise; end if;
  end;
  begin
    update public.mira_generation_jobs set status = 'succeeded' where id = job.id;
    raise exception 'queued job skipped claim';
  exception when check_violation then
    if sqlerrm <> 'mira_invalid_job_transition' then raise; end if;
  end;

  select * into strict claimed from public.mira_claim(job.id);
  assert claimed.attempts = 1 and claimed.lease_until - claimed.updated_at between interval '90 seconds' and interval '91 seconds',
    'legacy claim did not grant a 90-second lease';
  assert not exists (select from public.mira_claim(job.id, 120)), 'concurrent claim acquired an active lease';
  begin
    update public.mira_generation_jobs
      set attempts = attempts + 1, lease_id = gen_random_uuid(), lease_until = clock_timestamp() + interval '120 seconds'
      where id = job.id;
    raise exception 'unexpired lease was reclaimed';
  exception when check_violation then
    if sqlerrm <> 'mira_invalid_job_transition' then raise; end if;
  end;
  update public.mira_generation_jobs set status = 'queued', next_attempt_at = clock_timestamp() + interval '1 minute'
    where id = job.id;
  assert not exists (select from public.mira_claim(job.id, 120)), 'retry bypassed backoff';
  update public.mira_generation_jobs set status = 'failed', error = 'fixture_failure' where id = job.id;
  begin
    update public.mira_generation_jobs set status = 'queued' where id = job.id;
    raise exception 'terminal job was reopened';
  exception when check_violation then
    if sqlerrm <> 'mira_invalid_job_transition' then raise; end if;
  end;

  insert into public.mira_generation_jobs(id, workspace_id, creator_id, member_id, input_revision, input, status, attempts, lease_id, lease_until)
    values (expired_id, job.workspace_id, job.creator_id, job.member_id, 1, job.input, 'running', 1, gen_random_uuid(), clock_timestamp() - interval '1 second'),
           (exhausted_id, job.workspace_id, job.creator_id, job.member_id, 1, job.input, 'running', 3, gen_random_uuid(), clock_timestamp() - interval '1 second');
  begin
    update public.mira_generation_jobs
      set attempts = 3, lease_id = gen_random_uuid(), lease_until = clock_timestamp() + interval '120 seconds'
      where id = expired_id;
    raise exception 'reclaim skipped an attempt';
  exception when check_violation then
    if sqlerrm <> 'mira_invalid_job_transition' then raise; end if;
  end;
  select * into strict claimed from public.mira_claim(expired_id, 120);
  assert claimed.attempts = 2 and claimed.lease_until - claimed.updated_at between interval '119 seconds' and interval '120 seconds',
    'interrupted worker did not get a new 120-second lease';
  update public.mira_generation_jobs set status = 'succeeded', output = '{}' where id = expired_id;
  assert not exists (select from public.mira_claim(exhausted_id)), 'interrupted worker exceeded retry bound';
  assert (select status = 'failed' from public.mira_generation_jobs where id = exhausted_id),
    'exhausted job stayed running';

  perform public.mira_enqueue(cancelled_id, job.workspace_id, job.creator_id, job.member_id, 1, job.input);
  update public.mira_generation_jobs set status = 'cancelled' where id = cancelled_id;
  assert not exists (select from public.mira_claim(cancelled_id)), 'cancelled job restarted';
end $$;
do $$
declare
  member uuid := gen_random_uuid();
  workspace uuid := '10000000-0000-4000-8000-000000000001';
  creator uuid := '10000000-0000-4000-8000-000000000002';
  job uuid := gen_random_uuid();
  lease uuid := gen_random_uuid();
  shot_output jsonb;
  ignored uuid;
begin
  insert into public.members(id, workspace_id, display_name, role)
    values (member, workspace, 'Mira D2 SQL fixture', 'creator');
  perform public.mira_enqueue(job, workspace, creator, member, 1, '{"operation":"todayIdea"}');
  perform public.mira_claim(job);
  update public.mira_generation_jobs set step = 'idea_ready', updated_at = clock_timestamp() where id = job;
  update public.mira_generation_jobs set step = 'script_ready', updated_at = clock_timestamp() where id = job;
  begin
    update public.mira_generation_jobs set step = 'idea_ready' where id = job;
    raise exception 'progress went backwards';
  exception when check_violation then
    if sqlerrm <> 'mira_invalid_job_transition' then raise; end if;
  end;
  begin
    update public.mira_generation_jobs set step = 'storyboard_ready', picture_count = 5 where id = job;
    raise exception 'progress write changed the picture count';
  exception when check_violation then
    if sqlerrm <> 'mira_invalid_job_transition' then raise; end if;
  end;
  update public.mira_generation_jobs set status = 'queued' where id = job;
  perform public.mira_claim(job);
  assert (select step is null from public.mira_generation_jobs where id = job),
    'the new claim did not reset progress';
  update public.mira_generation_jobs set status = 'cancelled' where id = job;

  begin
    perform public.mira_claim_shot_pictures(gen_random_uuid(), gen_random_uuid(), 124);
    raise exception 'short picture lease accepted';
  exception when invalid_parameter_value then
    if sqlerrm <> 'mira_picture_lease_too_short' then raise; end if;
  end;

  for i in 1..7 loop
    job := gen_random_uuid();
    select jsonb_build_object('storyboard', jsonb_build_object('shots', jsonb_agg(jsonb_build_object('id', gen_random_uuid()))))
      into shot_output from generate_series(1, 5);
    perform public.mira_enqueue(job, workspace, creator, member, 1, '{"operation":"todayIdea"}');
    perform public.mira_claim(job);
    update public.mira_generation_jobs
      set status = 'succeeded', output = shot_output, picture_count = 5 where id = job;
    assert (select count(*) from public.mira_claim_shot_pictures(job, lease, 125)
      where status = 'generating' and lease_id = lease) = case when i <= 6 then 5 else 0 end,
      'picture reservation exceeded the cap or failed below it';
    assert not exists (select from public.mira_claim_shot_pictures(job, gen_random_uuid(), 125)
      where lease_id is distinct from lease and status = 'generating'), 'duplicate claim acquired picture work';
  end loop;

  assert (select count(*) from public.mira_shot_pictures where member_id = member and lease_id = lease) = 30,
    'wrong number of reserved pictures';
  assert (select count(*) from public.mira_shot_pictures where job_id = job and status = 'failed' and reserved_at is null) = 5,
    'jobs over the cap did not get fallback status';
  select (public.mira_enqueue(gen_random_uuid(), workspace, creator, member, 1, '{"operation":"ideas"}')).id into ignored;
  assert ignored is not null, 'picture work blocked a text job';
end $$;

reset role;
set local role anon;
do $$
begin
  begin
    perform public.mira_claim(gen_random_uuid());
    raise exception 'anonymous caller obtained a legacy claim';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.mira_claim(gen_random_uuid(), 120);
    raise exception 'anonymous caller obtained a parameterized claim';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.mira_claim_shot_pictures(gen_random_uuid(), gen_random_uuid(), 125);
    raise exception 'anonymous caller obtained a picture claim';
  exception when insufficient_privilege then null;
  end;
  begin
    perform count(*) from public.mira_shot_pictures;
    raise exception 'anonymous caller read picture metadata';
  exception when insufficient_privilege then null;
  end;
  begin
    perform count(*) from public.mira_generation_jobs;
    raise exception 'anonymous caller read private jobs';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;
select 'PASS: idempotency, both claim signatures, lease floor, retry backoff, transition guard, cancellation, picture reservations, UTC daily cap and grants' as verification;
