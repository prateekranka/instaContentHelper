create or replace function public.mira_enqueue(p_id uuid, p_workspace uuid, p_creator uuid, p_member uuid, p_revision integer, p_input jsonb)
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
  if (select count(*) from public.mira_generation_jobs where member_id = p_member and status in ('queued','running')) >= 3 then
    raise exception 'too_many_active_jobs';
  end if;
  insert into public.mira_generation_jobs(id, workspace_id, creator_id, member_id, input_revision, input)
    values(p_id, p_workspace, p_creator, p_member, p_revision, p_input) returning * into result;
  return result;
end $$;
