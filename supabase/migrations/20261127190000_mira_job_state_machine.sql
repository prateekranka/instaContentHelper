create or replace function public.mira_claim(p_id uuid, p_lease_seconds integer)
returns setof public.mira_generation_jobs language plpgsql security definer set search_path = public as $$
begin
  if p_lease_seconds is null or p_lease_seconds < 90 then
    raise exception using errcode = '22023', message = 'mira_lease_too_short';
  end if;

  update public.mira_generation_jobs
    set status = 'failed', error = 'worker_interrupted_retry_limit', updated_at = clock_timestamp()
    where id = p_id and status = 'running' and lease_until <= clock_timestamp() and attempts >= 3;

  return query update public.mira_generation_jobs
    set status = 'running', attempts = attempts + 1, lease_id = gen_random_uuid(),
        lease_until = clock_timestamp() + make_interval(secs => p_lease_seconds), updated_at = clock_timestamp()
    where id = p_id and attempts < 3 and next_attempt_at <= clock_timestamp()
      and (status = 'queued' or (status = 'running' and lease_until <= clock_timestamp()))
    returning *;
end $$;

revoke all on function public.mira_claim(uuid, integer) from public, anon, authenticated;
grant execute on function public.mira_claim(uuid, integer) to service_role;

create or replace function public.mira_claim(p_id uuid)
returns setof public.mira_generation_jobs language sql security definer set search_path = public as $$
  select * from public.mira_claim(p_id, 90);
$$;

create or replace function public.mira_enforce_job_transition()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.status = 'running'
     and (old.status = 'queued' or (old.status = 'running' and old.lease_until <= clock_timestamp()))
     and old.attempts < 3 and new.attempts = old.attempts + 1
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
       or (old.status = 'running' and new.status = 'queued' and old.attempts < 3)
     ) then
    return new;
  end if;

  raise exception using errcode = '23514', message = 'mira_invalid_job_transition',
    detail = format('%s -> %s', old.status, new.status);
end $$;

create or replace trigger mira_job_transition
before update on public.mira_generation_jobs
for each row execute function public.mira_enforce_job_transition();
