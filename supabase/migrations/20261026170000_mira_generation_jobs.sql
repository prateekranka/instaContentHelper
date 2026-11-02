create table public.mira_generation_jobs (
  id uuid primary key,
  workspace_id uuid not null references public.workspaces(id),
  creator_id uuid not null references public.creators(id),
  member_id uuid not null references public.members(id),
  input_revision integer not null check (input_revision >= 0),
  input jsonb not null,
  status text not null default 'queued' check (status in ('queued','running','succeeded','failed','cancelled')),
  attempts integer not null default 0,
  lease_id uuid,
  lease_until timestamptz,
  next_attempt_at timestamptz not null default now(),
  output jsonb,
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index mira_jobs_member_created on public.mira_generation_jobs(member_id, created_at desc);
alter table public.mira_generation_jobs enable row level security;
revoke all on public.mira_generation_jobs from anon, authenticated;
grant all on public.mira_generation_jobs to service_role;

create function public.mira_enqueue(p_id uuid, p_workspace uuid, p_creator uuid, p_member uuid, p_revision integer, p_input jsonb)
returns public.mira_generation_jobs language plpgsql security definer set search_path = public as $$
declare existing public.mira_generation_jobs; result public.mira_generation_jobs;
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
  update public.mira_generation_jobs set status='failed',error='unreconciled_job_expired',updated_at=now()
    where member_id=p_member and created_at<now()-interval '15 minutes'
      and (status='queued' or (status='running' and lease_until<now()));
  if (select count(*) from public.mira_generation_jobs where member_id = p_member and created_at > now() - interval '1 minute') >= 10 then
    raise exception 'rate_limited';
  end if;
  if (select count(*) from public.mira_generation_jobs where member_id = p_member and status in ('queued','running')) >= 2 then
    raise exception 'too_many_active_jobs';
  end if;
  insert into public.mira_generation_jobs(id, workspace_id, creator_id, member_id, input_revision, input)
    values(p_id, p_workspace, p_creator, p_member, p_revision, p_input) returning * into result;
  return result;
end $$;

create function public.mira_claim(p_id uuid)
returns setof public.mira_generation_jobs language plpgsql security definer set search_path = public as $$
begin
  update public.mira_generation_jobs set status='failed', error='worker_interrupted_retry_limit', updated_at=now()
    where id=p_id and status='running' and lease_until<now() and attempts>=3;
  return query update public.mira_generation_jobs
    set status='running', attempts=attempts+1, lease_id=gen_random_uuid(), lease_until=now()+interval '90 seconds', updated_at=now()
    where id=p_id and attempts<3 and next_attempt_at<=now()
      and (status='queued' or (status='running' and lease_until<now())) returning *;
end $$;
revoke all on function public.mira_enqueue(uuid,uuid,uuid,uuid,integer,jsonb) from public, anon, authenticated;
revoke all on function public.mira_claim(uuid) from public, anon, authenticated;
grant execute on function public.mira_enqueue(uuid,uuid,uuid,uuid,integer,jsonb) to service_role;
grant execute on function public.mira_claim(uuid) to service_role;
