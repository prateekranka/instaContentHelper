create table public.content_pieces (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  scheduled_date date not null,
  position integer not null check (position >= 0),
  current_revision_id uuid,
  generation_run_id uuid references public.weekly_generation_runs(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  removed_at timestamptz,
  unique (workspace_id, creator_id, id),
  foreign key (workspace_id, creator_id) references public.creators(workspace_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, current_revision_id) references public.daily_cards(workspace_id, creator_id, id)
);

alter table public.content_pieces enable row level security;
revoke all on public.content_pieces from public, anon, authenticated;
grant all on public.content_pieces to service_role;

create unique index content_pieces_active_date_position_key
  on public.content_pieces(workspace_id, creator_id, scheduled_date, position) where removed_at is null;
create index content_pieces_current_revision_fk_idx
  on public.content_pieces(workspace_id, creator_id, current_revision_id);
create index content_pieces_generation_run_fk_idx on public.content_pieces(generation_run_id);

alter table public.daily_cards add column piece_id uuid;
alter table public.weekly_generation_runs add column piece_id uuid;

alter table public.daily_cards disable trigger protect_historical_revision;
do $$
declare
  v_revisions bigint := (select count(*) from public.daily_cards);
  v_days bigint := (select count(*) from public.creator_days);
  v_expected bigint;
begin
  select count(*) into v_expected from (
    select workspace_id, creator_id, scheduled_date from public.creator_days
    union select workspace_id, creator_id, scheduled_date from public.daily_cards
  ) dates;
  insert into public.content_pieces(workspace_id, creator_id, scheduled_date, position, current_revision_id, generation_run_id, updated_at)
    select workspace_id, creator_id, scheduled_date, 0, current_revision_id, generation_run_id, updated_at from public.creator_days;
  if (select count(*) from public.content_pieces) <> v_days then raise exception 'piece_migration_day_count_mismatch'; end if;
  insert into public.content_pieces(workspace_id, creator_id, scheduled_date, position, current_revision_id)
    select dc.workspace_id, dc.creator_id, dc.scheduled_date, 0,
      (array_agg(dc.id order by dc.is_current desc, dc.updated_at desc, dc.id))[1]
    from public.daily_cards dc where not exists (
      select 1 from public.content_pieces p where p.workspace_id = dc.workspace_id
        and p.creator_id = dc.creator_id and p.scheduled_date = dc.scheduled_date
    ) group by dc.workspace_id, dc.creator_id, dc.scheduled_date;
  update public.daily_cards dc set piece_id = p.id from public.content_pieces p
    where p.workspace_id = dc.workspace_id and p.creator_id = dc.creator_id and p.scheduled_date = dc.scheduled_date;
  if (select count(*) from public.content_pieces) <> v_expected
    or (select count(*) from public.daily_cards) <> v_revisions
    or (select count(*) from public.daily_cards where piece_id is not null) <> v_revisions then
    raise exception 'piece_migration_revision_count_mismatch';
  end if;
  if exists (select 1 from public.creator_days d join public.content_pieces p using(workspace_id, creator_id, scheduled_date)
    where d.current_revision_id is distinct from p.current_revision_id or d.generation_run_id is distinct from p.generation_run_id) then
    raise exception 'piece_migration_pointer_mismatch';
  end if;
end;
$$;
alter table public.daily_cards enable trigger protect_historical_revision;
alter table public.daily_cards alter column piece_id set not null;
alter table public.daily_cards add constraint daily_cards_piece_fk foreign key (workspace_id, creator_id, piece_id)
  references public.content_pieces(workspace_id, creator_id, id);
create index daily_cards_piece_fk_idx on public.daily_cards(workspace_id, creator_id, piece_id);

update public.weekly_generation_runs r set piece_id = p.id from public.content_pieces p
  where r.workspace_id = p.workspace_id and r.creator_id = p.creator_id and r.target_scheduled_date = p.scheduled_date;
alter table public.weekly_generation_runs add constraint weekly_generation_runs_piece_fk foreign key (workspace_id, creator_id, piece_id)
  references public.content_pieces(workspace_id, creator_id, id);
create index weekly_generation_runs_piece_fk_idx on public.weekly_generation_runs(workspace_id, creator_id, piece_id);
update public.weekly_generation_runs set output_snapshot = output_snapshot || jsonb_build_object('piece_id', piece_id)
  || case when output_snapshot ? 'daily_card' then jsonb_build_object('daily_card', output_snapshot->'daily_card' || jsonb_build_object('piece_id', piece_id)) else '{}'::jsonb end
  where piece_id is not null and jsonb_typeof(output_snapshot) = 'object';
update public.weekly_generation_runs r set output_snapshot = jsonb_set(r.output_snapshot, '{daily_cards}', (
  select coalesce(jsonb_agg(item.value || case when dc.piece_id is null then '{}'::jsonb
    else jsonb_build_object('piece_id', dc.piece_id) end order by item.ordinality), '[]'::jsonb)
  from jsonb_array_elements(r.output_snapshot->'daily_cards') with ordinality item
  left join public.daily_cards dc on dc.id::text = item.value->>'id'
    and dc.workspace_id = r.workspace_id and dc.creator_id = r.creator_id
)) where jsonb_typeof(r.output_snapshot->'daily_cards') = 'array';

drop index public.daily_cards_current_day_key;
create unique index daily_cards_current_piece_key on public.daily_cards(piece_id) where is_current;
drop index public.daily_cards_run_date_revision_key;
create unique index daily_cards_run_piece_revision_key on public.daily_cards(generation_run_id, piece_id) where generation_run_id is not null;

create function public.resolve_content_piece(payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_workspace uuid := (payload->>'workspace_id')::uuid;
  v_creator uuid := (payload->>'creator_id')::uuid;
  v_date date := nullif(payload->>'scheduled_date', '')::date;
  v_id uuid;
  v_piece public.content_pieces;
  v_position integer;
begin
  begin
    v_id := nullif(payload->>'piece_id', '')::uuid;
  exception when invalid_text_representation then
    return jsonb_build_object('error', 'invalid_piece_id', 'status', 400);
  end;
  if v_workspace is null or v_creator is null or (v_date is null and v_id is null) then
    return jsonb_build_object('error', 'invalid_piece_target', 'status', 400);
  end if;
  if v_date is not null then
    perform pg_advisory_xact_lock(hashtextextended(v_workspace::text || v_creator::text || v_date::text, 1));
  end if;
  if v_id is not null then
    select * into v_piece from public.content_pieces where id = v_id for update;
    if found then
      if v_piece.workspace_id <> v_workspace or v_piece.creator_id <> v_creator
        or (v_date is not null and v_piece.scheduled_date <> v_date) then
        return jsonb_build_object('error', 'piece_scope_mismatch', 'status', 409);
      end if;
      if v_piece.removed_at is not null then return jsonb_build_object('error', 'piece_removed', 'status', 409); end if;
      return to_jsonb(v_piece);
    end if;
  else
    select * into v_piece from public.content_pieces where workspace_id = v_workspace and creator_id = v_creator
      and scheduled_date = v_date and position = 0 and removed_at is null for update;
    if found then return to_jsonb(v_piece); end if;
  end if;
  if v_date is null then return jsonb_build_object('error', 'piece_not_found', 'status', 404); end if;
  select coalesce(max(position) + 1, 0) into v_position from public.content_pieces
    where workspace_id = v_workspace and creator_id = v_creator and scheduled_date = v_date and removed_at is null;
  insert into public.content_pieces(id, workspace_id, creator_id, scheduled_date, position)
    values(coalesce(v_id, gen_random_uuid()), v_workspace, v_creator, v_date, case when v_id is null then 0 else v_position end)
    on conflict (id) do nothing returning * into v_piece;
  if not found then
    select * into v_piece from public.content_pieces where id = v_id for update;
    if v_piece.workspace_id <> v_workspace or v_piece.creator_id <> v_creator or v_piece.scheduled_date <> v_date then
      return jsonb_build_object('error', 'piece_scope_mismatch', 'status', 409);
    end if;
    if v_piece.removed_at is not null then return jsonb_build_object('error', 'piece_removed', 'status', 409); end if;
  end if;
  return to_jsonb(v_piece);
end;
$$;

create function public.sync_legacy_creator_day()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.position = 0 and new.removed_at is null then
    insert into public.creator_days(workspace_id, creator_id, scheduled_date, current_revision_id, generation_run_id, updated_at)
      values(new.workspace_id, new.creator_id, new.scheduled_date, new.current_revision_id, new.generation_run_id, new.updated_at)
      on conflict (workspace_id, creator_id, scheduled_date) do update
      set current_revision_id = excluded.current_revision_id, generation_run_id = excluded.generation_run_id, updated_at = excluded.updated_at;
  end if;
  return new;
end;
$$;
create trigger sync_legacy_creator_day after insert or update on public.content_pieces
  for each row execute function public.sync_legacy_creator_day();
insert into public.creator_days(workspace_id, creator_id, scheduled_date, current_revision_id, generation_run_id, updated_at)
  select workspace_id, creator_id, scheduled_date, current_revision_id, generation_run_id, updated_at from public.content_pieces where position = 0
  on conflict (workspace_id, creator_id, scheduled_date) do update set current_revision_id = excluded.current_revision_id,
    generation_run_id = excluded.generation_run_id, updated_at = excluded.updated_at;

create or replace function public.attach_current_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_piece jsonb;
begin
  v_piece := public.resolve_content_piece(jsonb_build_object('workspace_id', new.workspace_id, 'creator_id', new.creator_id,
    'scheduled_date', new.scheduled_date, 'piece_id', new.piece_id));
  if v_piece ? 'error' then raise exception '%', v_piece->>'error' using errcode = 'P0001'; end if;
  new.piece_id := (v_piece->>'id')::uuid;
  insert into public.archive_entries(workspace_id, creator_id, daily_card_id, archive_date, decision, output_line)
    select workspace_id, creator_id, id, scheduled_date,
      case when status in ('shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally') then status else 'replaced' end, title
    from public.daily_cards where piece_id = new.piece_id and is_current on conflict (daily_card_id) do nothing;
  update public.daily_cards set is_current = false, status = 'archived' where piece_id = new.piece_id and is_current;
  new.is_current := true;
  return new;
end;
$$;

create or replace function public.point_to_current_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.content_pieces set current_revision_id = new.id, updated_at = now() where id = new.piece_id;
  return new;
end;
$$;

create or replace function public.protect_historical_revision()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not old.is_current and (to_jsonb(new) - 'updated_at' - 'storyboard_thumbnail_assets')
    is distinct from (to_jsonb(old) - 'updated_at' - 'storyboard_thumbnail_assets') then
    raise exception 'historical_revision_immutable' using errcode = 'P0001';
  end if;
  if (new.id, new.workspace_id, new.creator_id, new.scheduled_date, new.generation_run_id, new.piece_id)
    is distinct from (old.id, old.workspace_id, old.creator_id, old.scheduled_date, old.generation_run_id, old.piece_id) then
    raise exception 'revision_identity_immutable' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

create or replace function public.start_day_generation(payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_workspace uuid := (payload->>'workspace_id')::uuid;
  v_creator uuid := (payload->>'creator_id')::uuid;
  v_date date := (payload->>'scheduled_date')::date;
  v_key text := nullif(btrim(payload->>'idempotency_key'), '');
  v_identity jsonb := payload->'request_identity';
  v_replace boolean := coalesce((payload->>'replace')::boolean, false);
  v_expected uuid := nullif(payload->>'daily_card_id', '')::uuid;
  v_day public.content_pieces;
  v_piece jsonb;
  v_run public.weekly_generation_runs;
  v_card public.daily_cards;
  v_plan public.weekly_plans;
  v_recovery boolean;
begin
  if v_workspace is null or v_creator is null or v_date is null or v_key is null or length(v_key) > 200 or v_identity is null then
    return jsonb_build_object('error', 'invalid_generation_payload', 'status', 400);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_workspace::text || v_creator::text || v_key, 0));
  v_piece := public.resolve_content_piece(payload);
  if v_piece ? 'error' then return v_piece; end if;
  select * into v_day from public.content_pieces where id = (v_piece->>'id')::uuid for update;
  select * into v_run from public.weekly_generation_runs
    where workspace_id = v_workspace and creator_id = v_creator and idempotency_key = v_key for update;
  if found then
    if v_run.request_identity is distinct from v_identity or v_run.piece_id is distinct from v_day.id then
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
  if v_plan.status not in ('draft', 'reviewed', 'published') then
    return jsonb_build_object('error', 'weekly_plan_not_found', 'status', 404);
  end if;
  if v_date < v_plan.week_start_date or v_date > v_plan.week_start_date + 6 then
    return jsonb_build_object('error', 'date_not_in_plan', 'status', 400);
  end if;
  select * into v_card from public.daily_cards where id = v_day.current_revision_id for update;
  v_recovery := coalesce(v_card.status = 'archived' and not v_card.is_current, false);
  if v_replace and (v_card.id is null or (v_expected is not null and v_expected <> v_card.id)) then
    return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
  end if;
  if v_day.current_revision_id is not null and not v_replace and not v_recovery and (v_plan.status <> 'draft' or v_plan.is_soft_locked) then
    return jsonb_build_object('error', 'existing_published_week_locked', 'status', 409);
  end if;
  if not v_replace and not v_recovery and v_card.id is not null and v_card.status <> 'draft' then
    return jsonb_build_object('error', 'replace_day_required', 'status', 409);
  end if;
  if v_day.generation_run_id is not null then
    update public.weekly_generation_runs set status = 'failed', error_code = 'generation_superseded', completed_at = now()
      where id = v_day.generation_run_id and status = 'running';
  end if;
  if v_replace and not v_recovery then
    insert into public.archive_entries(workspace_id, creator_id, daily_card_id, archive_date, decision, output_line)
      values(v_workspace, v_creator, v_card.id, v_date,
        case when v_card.status in ('shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally') then v_card.status else 'replaced' end,
        v_card.title) on conflict (daily_card_id) do nothing;
    update public.daily_cards set status = 'archived', is_current = false where id = v_card.id;
  end if;
  insert into public.weekly_generation_runs(workspace_id, creator_id, weekly_setup_id, weekly_plan_id, requested_by_member_id,
    status, model, prompt_version, generation_scope, target_daily_card_id, target_scheduled_date, input_snapshot,
    output_snapshot, idempotency_key, request_identity, replaced_daily_card_id, piece_id)
    values(v_workspace, v_creator, v_plan.weekly_setup_id, v_plan.id, (payload->>'member_id')::uuid,
      'running', payload->>'model', 'creator-weekly-generation-v1', 'day', case when v_recovery then null else v_card.id end, v_date, payload->'input_snapshot',
      jsonb_build_object('kind', 'single_day_generation_v1', 'scheduled_date', v_date, 'piece_id', v_day.id, 'status', 'pending',
        'preserve_manual_edits', coalesce((payload->>'preserve_manual_edits')::boolean, false), 'updated_at', now()),
      v_key, v_identity, case when v_replace then v_card.id else null end, v_day.id)
    returning * into v_run;
  update public.content_pieces set generation_run_id = v_run.id, updated_at = now()
    where id = v_day.id;
  return to_jsonb(v_run) || jsonb_build_object('replayed', false);
end;
$$;


create or replace function public.persist_day_revision(payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_run public.weekly_generation_runs;
  v_day public.content_pieces;
  v_card public.daily_cards;
  v_values jsonb := payload->'card';
  v_piece jsonb;
begin
  select * into v_run from public.weekly_generation_runs
    where id = (payload->>'generation_id')::uuid and workspace_id = (payload->>'workspace_id')::uuid
      and creator_id = (payload->>'creator_id')::uuid;
  if not found then return jsonb_build_object('error', 'generation_run_not_found', 'status', 404); end if;
  v_piece := public.resolve_content_piece(jsonb_build_object('workspace_id', v_run.workspace_id, 'creator_id', v_run.creator_id,
    'scheduled_date', v_run.target_scheduled_date, 'piece_id', v_run.piece_id));
  if v_piece ? 'error' then return v_piece; end if;
  select * into v_day from public.content_pieces where id = (v_piece->>'id')::uuid for update;
  select * into v_run from public.weekly_generation_runs where id = v_run.id for update;
  select * into v_card from public.daily_cards where generation_run_id = v_run.id and scheduled_date = v_run.target_scheduled_date;
  if not found then
    if v_run.status <> 'running' or v_day.generation_run_id is distinct from v_run.id then
      return jsonb_build_object('error', 'generation_run_closed', 'status', 409);
    end if;
    insert into public.daily_cards(workspace_id, creator_id, weekly_plan_id, scheduled_date, generation_run_id, piece_id,
      title, why_today, growth_job, content_pillar, shootability, estimated_shoot_minutes, energy_required, language_mode,
      scene_list, shot_content_owned, script, no_voiceover_version, on_screen_text, caption, cta, hashtags, cover_text, post_instructions,
      brand_event_notes, backup_story, backup_caption_only, risk_notes, assumptions, source_note)
    select v_run.workspace_id, v_run.creator_id, v_run.weekly_plan_id, v_run.target_scheduled_date, v_run.id, v_day.id,
      c.title, c.why_today, c.growth_job, c.content_pillar, c.shootability, c.estimated_shoot_minutes, c.energy_required, c.language_mode,
      coalesce(c.scene_list, '[]'), coalesce(c.shot_content_owned, false), c.script, c.no_voiceover_version, coalesce(c.on_screen_text, '[]'), c.caption, c.cta,
      coalesce(c.hashtags, '{}'), c.cover_text, coalesce(c.post_instructions, '{}'), c.brand_event_notes,
      coalesce(c.backup_story, '{}'), coalesce(c.backup_caption_only, '{}'), coalesce(c.risk_notes, '[]'), coalesce(c.assumptions, '[]'), c.source_note
    from jsonb_populate_record(null::public.daily_cards, v_values) c returning * into v_card;
  end if;
  if v_run.status = 'running' and v_day.generation_run_id = v_run.id then
    update public.weekly_generation_runs set status = 'completed', error_code = null, completed_at = clock_timestamp(),
      output_snapshot = jsonb_build_object(
        'generation_id', v_run.id, 'piece_id', v_day.id, 'weekly_plan_id', v_run.weekly_plan_id, 'status', 'draft',
        'target_scheduled_date', v_run.target_scheduled_date,
        'daily_card', coalesce(payload->'draft_card', to_jsonb(v_card)) || jsonb_build_object('id', v_card.id, 'piece_id', v_day.id),
        'warnings', '[]'::jsonb, 'assumptions', '[]'::jsonb, 'source_summary', '', 'generated_at', clock_timestamp(),
        'visuals_status', 'pending')
      where id = v_run.id and status = 'running';
  end if;
  return to_jsonb(v_card);
end;
$$;


create function public.resolve_piece_revision(payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_card public.daily_cards;
  v_piece jsonb;
  v_target jsonb := payload;
begin
  if nullif(payload->>'daily_card_id', '') is not null then
    select * into v_card from public.daily_cards where id = (payload->>'daily_card_id')::uuid
      and workspace_id = (payload->>'workspace_id')::uuid and creator_id = (payload->>'creator_id')::uuid;
    if not found then return jsonb_build_object('error', 'daily_card_not_found', 'status', 404); end if;
    if nullif(payload->>'piece_id', '') is null and nullif(payload->>'scheduled_date', '') is null then
      v_target := v_target || jsonb_build_object('piece_id', v_card.piece_id);
    end if;
    v_target := v_target || jsonb_build_object('scheduled_date', coalesce(nullif(payload->>'scheduled_date', ''), v_card.scheduled_date::text));
  end if;
  v_piece := public.resolve_content_piece(v_target);
  if v_piece ? 'error' then return v_piece; end if;
  if v_card.id is not null then
    if v_card.piece_id <> (v_piece->>'id')::uuid then
      return jsonb_build_object('error', 'piece_revision_mismatch', 'status', 409);
    end if;
  else
    select * into v_card from public.daily_cards where id = (v_piece->>'current_revision_id')::uuid;
  end if;
  if v_card.id is null then return jsonb_build_object('error', 'daily_card_not_found', 'status', 404); end if;
  return to_jsonb(v_card);
end;
$$;

create or replace function public.publish_day_atomic(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target jsonb;
  v_card public.daily_cards;
  v_workspace_id uuid;
  v_creator_id uuid;
  v_daily_card_id uuid;
  v_scheduled_date date;
  v_status text;
  v_published_at timestamptz := now();
  v_archived_count integer := 0;
begin
  begin
    v_workspace_id := (payload ->> 'workspace_id')::uuid;
    v_creator_id := (payload ->> 'creator_id')::uuid;
    v_daily_card_id := (payload ->> 'daily_card_id')::uuid;
  exception when others then
    return jsonb_build_object('error', 'invalid_publish_payload', 'status', 400);
  end;

  v_target := public.resolve_piece_revision(payload);
  if v_target ? 'error' then return v_target; end if;
  select * into v_card from public.daily_cards where id = (v_target->>'id')::uuid and is_current for update;
  if not found then return jsonb_build_object('error', 'daily_card_not_found', 'status', 404); end if;
  v_daily_card_id := v_card.id;
  v_scheduled_date := v_card.scheduled_date;
  v_status := v_card.status;

  if v_status not in ('draft', 'published') then
    return jsonb_build_object('error', 'daily_card_not_publishable', 'status', 409);
  end if;

  update public.daily_cards
     set status = 'published', updated_at = v_published_at
   where id = v_daily_card_id;

  return jsonb_build_object(
    'daily_card_id', v_daily_card_id,
    'piece_id', v_card.piece_id,
    'scheduled_date', to_char(v_scheduled_date, 'YYYY-MM-DD'),
    'published_at', v_published_at,
    'archived_card_count', v_archived_count
  );
end;
$$;

create or replace function public.make_day_available(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid := (payload->>'workspace_id')::uuid;
  v_creator_id uuid := (payload->>'creator_id')::uuid;
  v_daily_card_id uuid := nullif(payload->>'daily_card_id', '')::uuid;
  v_scheduled_date date := nullif(payload->>'scheduled_date', '')::date;
  v_card public.daily_cards;
  v_target jsonb;
  v_plan_soft_locked boolean;
begin
  if v_workspace_id is null or v_creator_id is null then
    return jsonb_build_object('error', 'invalid_make_day_available_payload', 'status', 400);
  end if;

  if v_daily_card_id is null and v_scheduled_date is null and nullif(payload->>'piece_id', '') is null then
    return jsonb_build_object('error', 'invalid_make_day_available_payload', 'status', 400);
  end if;

  v_target := public.resolve_piece_revision(payload);
  if v_target ? 'error' then return v_target; end if;
  select * into v_card from public.daily_cards where id = (v_target->>'id')::uuid and is_current for update;
  if not found then return jsonb_build_object('error', 'daily_card_not_found', 'status', 404); end if;

  if v_card.status is distinct from 'draft' then
    return jsonb_build_object('error', 'daily_card_not_draft', 'status', 409);
  end if;

  if v_card.title is null or trim(v_card.title) = '' then
    return jsonb_build_object('error', 'daily_card_incomplete', 'status', 400);
  end if;

  update public.daily_cards
     set status = 'published',
         updated_at = now()
   where id = v_card.id
     and status = 'draft';

  if not found then
    return jsonb_build_object('error', 'daily_card_not_draft', 'status', 409);
  end if;

  select wp.is_soft_locked
    into v_plan_soft_locked
    from public.weekly_plans wp
   where wp.id = v_card.weekly_plan_id;


  return jsonb_build_object(
    'daily_card_id', v_card.id,
    'piece_id', v_card.piece_id,
    'scheduled_date', v_card.scheduled_date,
    'status', 'published',
    'weekly_plan_id', v_card.weekly_plan_id,
    'week_is_soft_locked', coalesce(v_plan_soft_locked, false)
  );
end;
$$;

create or replace function public.unpublish_day(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid := (payload->>'workspace_id')::uuid;
  v_creator_id uuid := (payload->>'creator_id')::uuid;
  v_daily_card_id uuid := nullif(payload->>'daily_card_id', '')::uuid;
  v_scheduled_date date := nullif(payload->>'scheduled_date', '')::date;
  v_card public.daily_cards;
  v_target jsonb;
  v_previous_status text;
  v_cleared_live_decision boolean := false;
  v_archive_retained boolean := false;
begin
  if v_workspace_id is null or v_creator_id is null then
    return jsonb_build_object('error', 'invalid_unpublish_day_payload', 'status', 400);
  end if;

  if v_daily_card_id is null and v_scheduled_date is null and nullif(payload->>'piece_id', '') is null then
    return jsonb_build_object('error', 'invalid_unpublish_day_payload', 'status', 400);
  end if;

  v_target := public.resolve_piece_revision(payload);
  if v_target ? 'error' then return v_target; end if;
  select * into v_card from public.daily_cards where id = (v_target->>'id')::uuid and is_current for update;
  if not found then return jsonb_build_object('error', 'daily_card_not_found', 'status', 404); end if;

  if v_card.status = 'draft' then
    return jsonb_build_object('error', 'daily_card_already_draft', 'status', 409);
  end if;

  if v_card.status not in (
    'published',
    'in_decision',
    'shot',
    'posted',
    'used_backup',
    'saved_for_tomorrow',
    'skipped_intentionally'
  ) then
    return jsonb_build_object('error', 'daily_card_not_ready', 'status', 409);
  end if;

  v_previous_status := v_card.status;
  v_cleared_live_decision := v_card.status is distinct from 'published'
    or v_card.decision_at is not null
    or v_card.completed_by_member_id is not null;

  select exists(
    select 1
      from public.archive_entries ae
     where ae.workspace_id = v_workspace_id
       and ae.creator_id = v_creator_id
       and ae.daily_card_id = v_card.id
  ) into v_archive_retained;

  update public.daily_cards
     set status = 'draft',
         decision_at = null,
         completed_by_member_id = null,
         updated_at = now()
   where id = v_card.id
     and workspace_id = v_workspace_id
     and creator_id = v_creator_id
     and status = v_previous_status;

  if not found then
    return jsonb_build_object('error', 'unpublish_day_conflict', 'status', 409);
  end if;

  select exists(
    select 1
      from public.archive_entries ae
     where ae.workspace_id = v_workspace_id
       and ae.creator_id = v_creator_id
       and ae.daily_card_id = v_card.id
  ) into v_archive_retained;

  return jsonb_build_object(
    'daily_card_id', v_card.id,
    'piece_id', v_card.piece_id,
    'scheduled_date', v_card.scheduled_date,
    'status', 'draft',
    'previous_status', v_previous_status,
    'cleared_live_decision', v_cleared_live_decision,
    'archive_retained', v_archive_retained,
    'weekly_plan_id', v_card.weekly_plan_id
  );
end;
$$;

create or replace function public.update_ready_day_package(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_workspace_id uuid := (payload->>'workspace_id')::uuid;
  v_creator_id uuid := (payload->>'creator_id')::uuid;
  v_daily_card_id uuid := nullif(payload->>'daily_card_id', '')::uuid;
  v_scheduled_date date := nullif(payload->>'scheduled_date', '')::date;
  v_package jsonb := coalesce(payload->'package', '{}'::jsonb);
  v_card public.daily_cards;
  v_target jsonb;
  v_title text;
  v_why_today text;
  v_caption text;
  v_script text;
  v_backup_story jsonb;
  v_backup_caption_only jsonb;
  v_shootability text;
  v_estimated_shoot_minutes integer;
  v_scene_list jsonb;
  v_field text;
  v_shot jsonb;
  v_shot_index bigint;
  v_shot_ids uuid[] := array[]::uuid[];
begin
  if v_workspace_id is null or v_creator_id is null then
    return jsonb_build_object('error', 'invalid_update_ready_day_package_payload', 'status', 400);
  end if;

  if v_daily_card_id is null and v_scheduled_date is null and nullif(payload->>'piece_id', '') is null then
    return jsonb_build_object('error', 'invalid_update_ready_day_package_payload', 'status', 400);
  end if;

  v_target := public.resolve_piece_revision(payload);
  if v_target ? 'error' then return v_target; end if;
  select * into v_card from public.daily_cards where id = (v_target->>'id')::uuid and is_current for update;
  if not found then return jsonb_build_object('error', 'daily_card_not_found', 'status', 404); end if;

  if v_card.status not in (
    'published',
    'in_decision',
    'shot',
    'posted',
    'used_backup',
    'saved_for_tomorrow',
    'skipped_intentionally'
  ) then
    return jsonb_build_object('error', 'daily_card_not_ready', 'status', 409);
  end if;

  if jsonb_typeof(v_package) is distinct from 'object' then
    return jsonb_build_object('error', 'invalid_update_ready_day_package_payload', 'status', 400);
  end if;
  foreach v_field in array array['title', 'why_today', 'caption', 'script', 'backup_story', 'backup_caption_only', 'shootability'] loop
    if v_package ? v_field then
      if jsonb_typeof(v_package->v_field) is distinct from 'string' then
        return jsonb_build_object('error', 'invalid_package_text', 'field', v_field, 'status', 400);
      end if;
      if btrim(v_package->>v_field, E' \t\n\r\f' || chr(11) || chr(160) || chr(5760) || chr(8192) || chr(8193) || chr(8194) || chr(8195) || chr(8196) || chr(8197) || chr(8198) || chr(8199) || chr(8200) || chr(8201) || chr(8202) || chr(8232) || chr(8233) || chr(8239) || chr(8287) || chr(12288) || chr(65279)) = '' then
        return jsonb_build_object('error', 'blank_package_text', 'field', v_field, 'status', 400);
      end if;
    end if;
  end loop;
  if v_package ? 'scene_list' then
    if jsonb_typeof(v_package->'scene_list') is distinct from 'array' then
      return jsonb_build_object('error', 'invalid_package_scene_list', 'field', 'scene_list', 'status', 400);
    end if;
    for v_shot, v_shot_index in
      select value, ordinality - 1 from jsonb_array_elements(v_package->'scene_list') with ordinality
    loop
      if jsonb_typeof(v_shot) is distinct from 'object' then
        return jsonb_build_object('error', 'invalid_package_scene_list', 'field', 'scene_list', 'shot_index', v_shot_index, 'status', 400);
      end if;
      if jsonb_typeof(v_shot->'id') is distinct from 'string'
        or (v_shot->>'id') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        or jsonb_typeof(v_shot->'title') is distinct from 'string'
        or jsonb_typeof(v_shot->'duration') is distinct from 'string'
        or (v_shot ? 'dialogue' and jsonb_typeof(v_shot->'dialogue') is distinct from 'string')
        or (v_shot ? 'symbol' and jsonb_typeof(v_shot->'symbol') is distinct from 'string') then
        return jsonb_build_object('error', 'invalid_package_scene_list', 'field', 'scene_list', 'shot_index', v_shot_index, 'status', 400);
      end if;
      if v_shot ? 'number' then
        if jsonb_typeof(v_shot->'number') is distinct from 'number' then
          return jsonb_build_object('error', 'invalid_package_scene_list', 'field', 'scene_list', 'shot_index', v_shot_index, 'status', 400);
        end if;
        if (v_shot->>'number')::numeric <> trunc((v_shot->>'number')::numeric)
          or (v_shot->>'number')::numeric < -9223372036854775808
          or (v_shot->>'number')::numeric > 9223372036854775807 then
          return jsonb_build_object('error', 'invalid_package_scene_list', 'field', 'scene_list', 'shot_index', v_shot_index, 'status', 400);
        end if;
      end if;
      if (v_shot->>'id')::uuid = any(v_shot_ids) then
        return jsonb_build_object('error', 'invalid_package_scene_list', 'field', 'scene_list', 'shot_index', v_shot_index, 'status', 400);
      end if;
      v_shot_ids := array_append(v_shot_ids, (v_shot->>'id')::uuid);
    end loop;
  end if;
  v_title := coalesce(nullif(trim(v_package->>'title'), ''), v_card.title);
  v_why_today := coalesce(nullif(trim(v_package->>'why_today'), ''), v_card.why_today);
  v_caption := coalesce(nullif(trim(v_package->>'caption'), ''), v_card.caption);
  v_script := coalesce(nullif(trim(v_package->>'script'), ''), v_card.script);
  v_backup_story := case when v_package ? 'backup_story' then to_jsonb(btrim(v_package->>'backup_story')) else v_card.backup_story end;
  v_backup_caption_only := case when v_package ? 'backup_caption_only' then to_jsonb(btrim(v_package->>'backup_caption_only')) else v_card.backup_caption_only end;
  v_shootability := coalesce(nullif(trim(v_package->>'shootability'), ''), v_card.shootability);
  v_estimated_shoot_minutes := coalesce(
    nullif(v_package->>'estimated_shoot_minutes', '')::integer,
    v_card.estimated_shoot_minutes
  );
  v_scene_list := case
    when jsonb_typeof(v_package->'scene_list') = 'array' then v_package->'scene_list'
    else v_card.scene_list
  end;

  if v_title is null or trim(v_title) = '' then
    return jsonb_build_object('error', 'daily_card_incomplete', 'status', 400);
  end if;

  update public.daily_cards
     set title = v_title,
         why_today = v_why_today,
         caption = v_caption,
         script = v_script,
         backup_story = v_backup_story,
         backup_caption_only = v_backup_caption_only,
         shootability = v_shootability,
         estimated_shoot_minutes = v_estimated_shoot_minutes,
         scene_list = v_scene_list,
         shot_content_owned = shot_content_owned or (v_package ? 'scene_list'),
         updated_at = now()
   where id = v_card.id
     and workspace_id = v_workspace_id
     and creator_id = v_creator_id
     and status = v_card.status;

  if not found then
    return jsonb_build_object('error', 'update_ready_day_package_conflict', 'status', 409);
  end if;

  return jsonb_build_object(
    'daily_card_id', v_card.id,
    'piece_id', v_card.piece_id,
    'scheduled_date', v_card.scheduled_date,
    'status', v_card.status,
    'weekly_plan_id', v_card.weekly_plan_id,
    'title', v_title,
    'caption', v_caption
  );
end;
$$;

create or replace function public.write_content(payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_target jsonb;
  v_result jsonb;
  v_action text := payload->>'action';
  v_card public.daily_cards;
  v_archive public.archive_entries;
  v_decision text;
  v_decision_at timestamptz;
  v_archive_date date;
  v_output text;
  v_thumbnail boolean;
begin
  if v_action not in ('complete_today', 'upsert_archive_decision') then
    v_result := public.write_content_before_revisions(payload);
    if v_result ? 'daily_card_id' and not (v_result ? 'error') then
      select * into v_card from public.daily_cards where id = (v_result->>'daily_card_id')::uuid
        and workspace_id = (payload->>'workspace_id')::uuid and creator_id = (payload->>'creator_id')::uuid;
      v_result := v_result || jsonb_build_object('piece_id', v_card.piece_id);
    end if;
    return v_result;
  end if;
  v_target := public.resolve_piece_revision(payload);
  if v_target ? 'error' then return v_target; end if;
  select * into v_card from public.daily_cards where id = (v_target->>'id')::uuid for update;
  if v_action = 'complete_today' then
    v_decision := payload #>> '{decision,status}';
    v_output := payload #>> '{decision,output_line}';
    v_thumbnail := coalesce((payload #>> '{decision,has_post_thumbnail}')::boolean, false);
    v_archive_date := v_card.scheduled_date;
  else
    v_decision := payload->>'decision';
    v_output := payload->>'output_line';
    v_thumbnail := coalesce((payload->>'has_post_thumbnail')::boolean, false);
    v_archive_date := (payload->>'archive_date')::date;
  end if;
  if v_decision is null or v_decision not in ('shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally')
    or v_archive_date is null then
    return jsonb_build_object('error', 'invalid_write_payload', 'status', 400);
  end if;
  select * into v_archive from public.archive_entries where daily_card_id = v_card.id;
  if not v_card.is_current then
    if v_archive.id is null or v_archive.decision is distinct from v_decision
      or v_archive.archive_date is distinct from v_archive_date
      or v_archive.output_line is distinct from v_output
      or v_archive.has_post_thumbnail is distinct from v_thumbnail
      or (nullif(payload->>'decision_at', '') is not null
        and (payload->>'decision_at')::timestamptz is distinct from v_archive.decision_at) then
      return jsonb_build_object('error', 'historical_revision_immutable', 'status', 409);
    end if;
  else
    v_decision_at := case when v_archive.decision = v_decision then v_archive.decision_at
      else coalesce(nullif(payload->>'decision_at', '')::timestamptz, clock_timestamp()) end;
    if v_archive.decision is distinct from v_decision and v_decision_at is not distinct from v_archive.decision_at then
      v_decision_at := greatest(clock_timestamp(), v_archive.decision_at + interval '1 microsecond');
    end if;
    if v_action = 'complete_today' and (v_archive.decision is distinct from 'posted' or v_decision <> 'posted'
      or v_card.status is distinct from 'posted' or v_card.decision_at is distinct from v_decision_at) then
      update public.daily_cards set status = v_decision, decision_at = v_decision_at,
        completed_by_member_id = (payload->>'member_id')::uuid where id = v_card.id returning * into v_card;
    end if;
    insert into public.archive_entries(workspace_id, creator_id, daily_card_id, archive_date, decision, output_line, has_post_thumbnail, decision_at)
      values(v_card.workspace_id, v_card.creator_id, v_card.id, v_archive_date, v_decision, v_output, v_thumbnail, v_decision_at)
    on conflict (daily_card_id) do update set archive_date = excluded.archive_date, decision = excluded.decision,
      output_line = excluded.output_line, has_post_thumbnail = excluded.has_post_thumbnail, decision_at = excluded.decision_at
    returning * into v_archive;
  end if;
  if v_action = 'complete_today' then
    return jsonb_build_object('action', v_action, 'daily_card', jsonb_build_object('id', v_card.id, 'piece_id', v_card.piece_id,
      'status', v_archive.decision, 'decision_at', v_archive.decision_at, 'completed_by_member_id', v_card.completed_by_member_id),
      'archive_entry', to_jsonb(v_archive) || jsonb_build_object('piece_id', v_card.piece_id));
  end if;
  return jsonb_build_object('action', v_action, 'archive_entry', to_jsonb(v_archive) || jsonb_build_object('piece_id', v_card.piece_id));
end;
$$;

create or replace function public.read_creator_days(payload jsonb)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('days', coalesce(jsonb_agg(jsonb_build_object(
    'piece_id', d.id, 'position', d.position, 'scheduled_date', d.scheduled_date,
    'current_revision_id', d.current_revision_id, 'generation_id', d.generation_run_id,
    'revision', to_jsonb(dc),
    'generation', case when r.id is null then null else jsonb_build_object(
      'generation_id', r.id, 'piece_id', d.id, 'status', r.status, 'error_code', r.error_code,
      'idempotency_key', r.idempotency_key, 'completed_at', r.completed_at) end,
    'updated_at', greatest(d.updated_at, dc.updated_at, r.updated_at)
  ) order by d.scheduled_date, d.position, d.id), '[]'::jsonb))
  from public.content_pieces d
  left join public.daily_cards dc on dc.id = d.current_revision_id
  left join public.weekly_generation_runs r on r.id = d.generation_run_id
  where d.workspace_id = (payload->>'workspace_id')::uuid and d.creator_id = (payload->>'creator_id')::uuid
    and d.removed_at is null
    and (case when nullif(payload->>'piece_id', '') is not null then d.id = (payload->>'piece_id')::uuid
      when coalesce((payload->>'include_all_pieces')::boolean, false) then true else d.position = 0 end);
$$;

revoke all on function public.resolve_content_piece(jsonb) from public, anon, authenticated;
grant execute on function public.resolve_content_piece(jsonb) to service_role;
revoke all on function public.resolve_piece_revision(jsonb) from public, anon, authenticated;
grant execute on function public.resolve_piece_revision(jsonb) to service_role;
revoke all on function public.start_day_generation(jsonb) from public, anon, authenticated;
grant execute on function public.start_day_generation(jsonb) to service_role;
revoke all on function public.replace_day(jsonb) from public, anon, authenticated;
grant execute on function public.replace_day(jsonb) to service_role;
revoke all on function public.persist_day_revision(jsonb) from public, anon, authenticated;
grant execute on function public.persist_day_revision(jsonb) to service_role;
revoke all on function public.publish_day_atomic(jsonb) from public, anon, authenticated;
grant execute on function public.publish_day_atomic(jsonb) to service_role;
revoke all on function public.make_day_available(jsonb) from public, anon, authenticated;
grant execute on function public.make_day_available(jsonb) to service_role;
revoke all on function public.unpublish_day(jsonb) from public, anon, authenticated;
grant execute on function public.unpublish_day(jsonb) to service_role;
revoke all on function public.update_ready_day_package(jsonb) from public, anon, authenticated;
grant execute on function public.update_ready_day_package(jsonb) to service_role;
revoke all on function public.write_content(jsonb) from public, anon, authenticated;
grant execute on function public.write_content(jsonb) to service_role;
revoke all on function public.read_creator_days(jsonb) from public, anon, authenticated;
grant execute on function public.read_creator_days(jsonb) to service_role;
revoke all on function public.sync_legacy_creator_day() from public, anon, authenticated;
grant execute on function public.sync_legacy_creator_day() to service_role;
revoke all on function public.attach_current_revision() from public, anon, authenticated;
grant execute on function public.attach_current_revision() to service_role;
revoke all on function public.point_to_current_revision() from public, anon, authenticated;
grant execute on function public.point_to_current_revision() to service_role;
