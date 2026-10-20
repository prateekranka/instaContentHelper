alter table public.daily_cards
  drop constraint daily_cards_weekly_plan_id_scheduled_date_key,
  add column is_current boolean not null default false,
  add column generation_run_id uuid references public.weekly_generation_runs(id) on delete set null;

alter table public.weekly_generation_runs
  add column idempotency_key text,
  add column request_identity jsonb,
  add column replaced_daily_card_id uuid references public.daily_cards(id) on delete set null,
  add constraint generation_idempotency_key_valid check (idempotency_key is null or length(btrim(idempotency_key)) between 1 and 200),
  add constraint generation_idempotency_key_unique unique (workspace_id, creator_id, idempotency_key);

create unique index daily_cards_run_date_revision_key
  on public.daily_cards(generation_run_id, scheduled_date) where generation_run_id is not null;

create table public.creator_days (
  workspace_id uuid not null,
  creator_id uuid not null,
  scheduled_date date not null,
  current_revision_id uuid,
  generation_run_id uuid references public.weekly_generation_runs(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (workspace_id, creator_id, scheduled_date),
  foreign key (workspace_id, creator_id) references public.creators(workspace_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, current_revision_id) references public.daily_cards(workspace_id, creator_id, id)
);

alter table public.creator_days enable row level security;
revoke all on public.creator_days from public, anon, authenticated;
grant all on public.creator_days to service_role;

insert into public.creator_days(workspace_id, creator_id, scheduled_date, current_revision_id)
select distinct on (workspace_id, creator_id, scheduled_date)
  workspace_id, creator_id, scheduled_date, id
from public.daily_cards
order by workspace_id, creator_id, scheduled_date, updated_at desc, created_at desc, id;

update public.daily_cards dc set is_current = true
from public.creator_days d where d.current_revision_id = dc.id;

create unique index daily_cards_current_day_key
  on public.daily_cards(workspace_id, creator_id, scheduled_date) where is_current;

alter table public.archive_entries
  add column title_snapshot text,
  add column caption_snapshot text,
  add column decision_at timestamptz,
  drop constraint archive_entries_decision_check,
  add constraint archive_entries_decision_check check (decision in ('shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally', 'replaced'));

update public.archive_entries ae
set title_snapshot = dc.title, caption_snapshot = dc.caption,
    decision_at = coalesce(dc.decision_at, ae.created_at)
from public.daily_cards dc where dc.id = ae.daily_card_id;

alter table public.archive_entries
  alter column title_snapshot set not null,
  alter column decision_at set default now(),
  alter column decision_at set not null;

create function public.snapshot_archive_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_card public.daily_cards;
begin
  if tg_op = 'UPDATE' then
    if (new.workspace_id, new.creator_id, new.daily_card_id) is distinct from (old.workspace_id, old.creator_id, old.daily_card_id) then
      raise exception 'archive_revision_immutable' using errcode = 'P0001';
    end if;
    if old.decision = 'posted' then return old; end if;
    if new.decision = old.decision then
      new.title_snapshot := old.title_snapshot;
      new.caption_snapshot := old.caption_snapshot;
      new.decision_at := old.decision_at;
      return new;
    end if;
  end if;
  select * into strict v_card from public.daily_cards
    where id = new.daily_card_id and workspace_id = new.workspace_id and creator_id = new.creator_id;
  new.title_snapshot := v_card.title;
  new.caption_snapshot := v_card.caption;
  new.decision_at := coalesce(new.decision_at, v_card.decision_at, now());
  return new;
end;
$$;
create trigger zz_snapshot_archive_revision before insert or update on public.archive_entries
for each row execute function public.snapshot_archive_revision();

create function public.attach_current_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.creator_days(workspace_id, creator_id, scheduled_date)
    values(new.workspace_id, new.creator_id, new.scheduled_date) on conflict do nothing;
  perform 1 from public.creator_days where workspace_id = new.workspace_id and creator_id = new.creator_id
    and scheduled_date = new.scheduled_date for update;
  insert into public.archive_entries(workspace_id, creator_id, daily_card_id, archive_date, decision, output_line)
    select workspace_id, creator_id, id, scheduled_date,
      case when status in ('shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally') then status else 'replaced' end, title
    from public.daily_cards where workspace_id = new.workspace_id and creator_id = new.creator_id
      and scheduled_date = new.scheduled_date and is_current
    on conflict (daily_card_id) do nothing;
  update public.daily_cards set is_current = false, status = 'archived'
    where workspace_id = new.workspace_id and creator_id = new.creator_id and scheduled_date = new.scheduled_date and is_current;
  new.is_current := true;
  return new;
end;
$$;
create trigger attach_current_revision before insert on public.daily_cards
for each row execute function public.attach_current_revision();

create function public.point_to_current_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.creator_days set current_revision_id = new.id, updated_at = now()
    where workspace_id = new.workspace_id and creator_id = new.creator_id and scheduled_date = new.scheduled_date;
  return new;
end;
$$;
create trigger point_to_current_revision after insert on public.daily_cards
for each row execute function public.point_to_current_revision();

create function public.protect_historical_revision()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not old.is_current and (to_jsonb(new) - 'updated_at' - 'storyboard_thumbnail_assets')
    is distinct from (to_jsonb(old) - 'updated_at' - 'storyboard_thumbnail_assets') then
    raise exception 'historical_revision_immutable' using errcode = 'P0001';
  end if;
  if (new.id, new.workspace_id, new.creator_id, new.scheduled_date, new.generation_run_id)
    is distinct from (old.id, old.workspace_id, old.creator_id, old.scheduled_date, old.generation_run_id) then
    raise exception 'revision_identity_immutable' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger protect_historical_revision before update on public.daily_cards
for each row execute function public.protect_historical_revision();

create function public.close_generation_run()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status in ('failed', 'completed') and new.status <> old.status then
    raise exception 'generation_run_closed' using errcode = 'P0001';
  end if;
  if new.status in ('failed', 'completed') then
    new.completed_at := coalesce(new.completed_at, now());
  end if;
  return new;
end;
$$;
create trigger close_generation_run before update on public.weekly_generation_runs
for each row execute function public.close_generation_run();

create function public.start_day_generation(payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_workspace uuid := (payload->>'workspace_id')::uuid;
  v_creator uuid := (payload->>'creator_id')::uuid;
  v_date date := (payload->>'scheduled_date')::date;
  v_key text := nullif(btrim(payload->>'idempotency_key'), '');
  v_identity jsonb := payload->'request_identity';
  v_replace boolean := coalesce((payload->>'replace')::boolean, false);
  v_expected uuid := nullif(payload->>'daily_card_id', '')::uuid;
  v_day public.creator_days;
  v_run public.weekly_generation_runs;
  v_card public.daily_cards;
  v_plan public.weekly_plans;
begin
  if v_workspace is null or v_creator is null or v_date is null or v_key is null or length(v_key) > 200 or v_identity is null then
    return jsonb_build_object('error', 'invalid_generation_payload', 'status', 400);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_workspace::text || v_creator::text || v_key, 0));
  insert into public.creator_days(workspace_id, creator_id, scheduled_date)
    values(v_workspace, v_creator, v_date) on conflict do nothing;
  select * into v_day from public.creator_days
    where workspace_id = v_workspace and creator_id = v_creator and scheduled_date = v_date for update;
  select * into v_run from public.weekly_generation_runs
    where workspace_id = v_workspace and creator_id = v_creator and idempotency_key = v_key for update;
  if found then
    if v_run.request_identity is distinct from v_identity then
      return jsonb_build_object('error', 'idempotency_key_conflict', 'status', 409);
    end if;
    if v_run.status = 'running' and v_run.updated_at < now() - interval '10 minutes' then
      update public.weekly_generation_runs set status = 'failed', error_code = 'generation_stale', completed_at = now()
        where id = v_run.id returning * into v_run;
    end if;
    return to_jsonb(v_run) || jsonb_build_object('replayed', true);
  end if;
  select * into v_plan from public.weekly_plans
    where id = (payload->>'weekly_plan_id')::uuid and workspace_id = v_workspace and creator_id = v_creator;
  if not found then return jsonb_build_object('error', 'weekly_plan_not_found', 'status', 404); end if;
  if v_date < v_plan.week_start_date or v_date > v_plan.week_start_date + 6 then
    return jsonb_build_object('error', 'date_not_in_plan', 'status', 400);
  end if;
  select * into v_card from public.daily_cards where id = v_day.current_revision_id for update;
  if v_replace and (v_card.id is null or (v_expected is not null and v_expected <> v_card.id)) then
    return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
  end if;
  if not v_replace and (v_plan.status <> 'draft' or v_plan.is_soft_locked) then
    return jsonb_build_object('error', 'existing_published_week_locked', 'status', 409);
  end if;
  if not v_replace and v_card.id is not null and v_card.status <> 'draft' then
    return jsonb_build_object('error', 'replace_day_required', 'status', 409);
  end if;
  if v_day.generation_run_id is not null then
    update public.weekly_generation_runs set status = 'failed', error_code = 'generation_superseded', completed_at = now()
      where id = v_day.generation_run_id and status = 'running';
  end if;
  if v_replace then
    insert into public.archive_entries(workspace_id, creator_id, daily_card_id, archive_date, decision, output_line)
      values(v_workspace, v_creator, v_card.id, v_date,
        case when v_card.status in ('shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally') then v_card.status else 'replaced' end,
        v_card.title) on conflict (daily_card_id) do nothing;
    update public.daily_cards set status = 'archived' where id = v_card.id;
  end if;
  insert into public.weekly_generation_runs(workspace_id, creator_id, weekly_setup_id, weekly_plan_id, requested_by_member_id,
    status, model, prompt_version, generation_scope, target_daily_card_id, target_scheduled_date, input_snapshot,
    output_snapshot, idempotency_key, request_identity, replaced_daily_card_id)
    values(v_workspace, v_creator, v_plan.weekly_setup_id, v_plan.id, (payload->>'member_id')::uuid,
      'running', payload->>'model', 'creator-weekly-generation-v1', 'day', v_card.id, v_date, payload->'input_snapshot',
      jsonb_build_object('kind', 'single_day_generation_v1', 'scheduled_date', v_date, 'status', 'pending',
        'preserve_manual_edits', coalesce((payload->>'preserve_manual_edits')::boolean, false), 'updated_at', now()),
      v_key, v_identity, case when v_replace then v_card.id else null end)
    returning * into v_run;
  update public.creator_days set generation_run_id = v_run.id, updated_at = now()
    where workspace_id = v_workspace and creator_id = v_creator and scheduled_date = v_date;
  return to_jsonb(v_run) || jsonb_build_object('replayed', false);
end;
$$;

create function public.replace_day(payload jsonb)
returns jsonb language sql security definer set search_path = '' as $$
  select public.start_day_generation(payload || jsonb_build_object('replace', true));
$$;

create function public.persist_day_revision(payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_run public.weekly_generation_runs;
  v_day public.creator_days;
  v_card public.daily_cards;
  v_values jsonb := payload->'card';
begin
  select * into v_run from public.weekly_generation_runs
    where id = (payload->>'generation_id')::uuid and workspace_id = (payload->>'workspace_id')::uuid
      and creator_id = (payload->>'creator_id')::uuid;
  if not found then return jsonb_build_object('error', 'generation_run_not_found', 'status', 404); end if;
  select * into v_day from public.creator_days where workspace_id = v_run.workspace_id and creator_id = v_run.creator_id
    and scheduled_date = v_run.target_scheduled_date for update;
  select * into v_run from public.weekly_generation_runs where id = v_run.id for update;
  select * into v_card from public.daily_cards where generation_run_id = v_run.id and scheduled_date = v_run.target_scheduled_date;
  if found then return to_jsonb(v_card); end if;
  if v_run.status <> 'running' or v_day.generation_run_id is distinct from v_run.id then
    return jsonb_build_object('error', 'generation_run_closed', 'status', 409);
  end if;
  insert into public.daily_cards(workspace_id, creator_id, weekly_plan_id, scheduled_date, generation_run_id,
    title, why_today, growth_job, content_pillar, shootability, estimated_shoot_minutes, energy_required, language_mode,
    scene_list, script, no_voiceover_version, on_screen_text, caption, cta, hashtags, cover_text, post_instructions,
    brand_event_notes, backup_story, backup_caption_only, risk_notes, assumptions, source_note)
  select v_run.workspace_id, v_run.creator_id, v_run.weekly_plan_id, v_run.target_scheduled_date, v_run.id,
    c.title, c.why_today, c.growth_job, c.content_pillar, c.shootability, c.estimated_shoot_minutes, c.energy_required, c.language_mode,
    coalesce(c.scene_list, '[]'), c.script, c.no_voiceover_version, coalesce(c.on_screen_text, '[]'), c.caption, c.cta,
    coalesce(c.hashtags, '{}'), c.cover_text, coalesce(c.post_instructions, '{}'), c.brand_event_notes,
    coalesce(c.backup_story, '{}'), coalesce(c.backup_caption_only, '{}'), coalesce(c.risk_notes, '[]'), coalesce(c.assumptions, '[]'), c.source_note
  from jsonb_populate_record(null::public.daily_cards, v_values) c returning * into v_card;
  return to_jsonb(v_card);
end;
$$;

revoke all on function public.start_day_generation(jsonb), public.replace_day(jsonb), public.persist_day_revision(jsonb),
  public.snapshot_archive_revision(), public.attach_current_revision(), public.point_to_current_revision(),
  public.protect_historical_revision(), public.close_generation_run() from public, anon, authenticated;
grant execute on function public.start_day_generation(jsonb), public.replace_day(jsonb), public.persist_day_revision(jsonb) to service_role;
