\set ON_ERROR_STOP on
\if :{?mira_full_schema}
\else
create role anon;
create role authenticated;
create role service_role bypassrls;
create table public.workspaces(id uuid primary key, name text not null);
create table public.creators(id uuid primary key, workspace_id uuid references public.workspaces, display_name text not null);
create table public.members(id uuid primary key, workspace_id uuid references public.workspaces, display_name text not null, role text not null);
\i /20261026170000_mira_generation_jobs.sql
\i /20261119012500_mira_three_active_jobs.sql
\i /20261127190000_mira_job_state_machine.sql
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
  assert claimed.attempts = 1 and claimed.lease_until - claimed.updated_at between interval '89 seconds' and interval '90 seconds',
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
  update public.mira_generation_jobs set status = 'failed' where id = job.id;
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
    perform count(*) from public.mira_generation_jobs;
    raise exception 'anonymous caller read private jobs';
  exception when insufficient_privilege then null;
  end;
end $$;
rollback;
select 'PASS: idempotency, both claim signatures, lease floor, retry backoff, transition guard, cancellation and grants' as verification;
