alter table public.mira_generation_jobs
  add column if not exists step text
    check (step in ('idea_ready', 'script_ready', 'storyboard_ready')),
  add column if not exists picture_count smallint
    check (picture_count between 0 and 5);

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
    set status = 'running', attempts = attempts + 1, lease_id = gen_random_uuid(), step = null,
        lease_until = clock_timestamp() + make_interval(secs => p_lease_seconds), updated_at = clock_timestamp()
    where id = p_id and attempts < 3 and next_attempt_at <= clock_timestamp()
      and (status = 'queued' or (status = 'running' and lease_until <= clock_timestamp()))
    returning *;
end $$;

create or replace function public.mira_enforce_job_transition()
returns trigger language plpgsql set search_path = public as $$
begin
  if old.status = 'running' and new.status = 'running'
     and old.lease_until > clock_timestamp()
     and old.input->>'operation' = 'todayIdea'
     and array_position(array['idea_ready', 'script_ready', 'storyboard_ready'], new.step)
         > coalesce(array_position(array['idea_ready', 'script_ready', 'storyboard_ready'], old.step), 0)
     and (to_jsonb(new) - array['step', 'updated_at']) = (to_jsonb(old) - array['step', 'updated_at']) then
    return new;
  end if;

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

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('mira-shot-pictures', 'mira-shot-pictures', false, 2097152, array['image/jpeg'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists mira_shot_pictures_private on storage.objects;
create policy mira_shot_pictures_private on storage.objects as restrictive
  for all to anon, authenticated
  using (bucket_id <> 'mira-shot-pictures')
  with check (bucket_id <> 'mira-shot-pictures');

create table if not exists public.mira_shot_pictures (
  job_id uuid not null references public.mira_generation_jobs(id),
  shot_id uuid not null,
  member_id uuid not null references public.members(id),
  position smallint not null check (position between 1 and 5),
  object_path text generated always as (job_id::text || '/' || shot_id::text || '.jpg') stored,
  status text not null check (status in ('generating', 'ready', 'failed')),
  reserved_at timestamptz,
  lease_id uuid,
  lease_until timestamptz,
  primary key (job_id, shot_id),
  unique (job_id, position),
  check ((reserved_at is null and lease_id is null and lease_until is null and status = 'failed')
     or (reserved_at is not null and lease_id is not null and lease_until is not null))
);

create index if not exists mira_pictures_member_reserved
  on public.mira_shot_pictures(member_id, reserved_at) where reserved_at is not null;

alter table public.mira_shot_pictures enable row level security;
revoke all on public.mira_shot_pictures from public, anon, authenticated;
grant select, insert, update on public.mira_shot_pictures to service_role;

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
    where id = p_job_id and status = 'succeeded' and input->>'operation' = 'todayIdea'
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

revoke all on function public.mira_claim_shot_pictures(uuid, uuid, integer) from public, anon, authenticated;
grant execute on function public.mira_claim_shot_pictures(uuid, uuid, integer) to service_role;
