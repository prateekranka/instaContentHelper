alter table public.daily_cards add column if not exists shot_content_owned boolean not null default false;

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
  v_day public.creator_days;
  v_run public.weekly_generation_runs;
  v_card public.daily_cards;
  v_plan public.weekly_plans;
  v_recovery boolean;
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
  v_recovery := coalesce(v_card.status = 'archived' and not v_card.is_current, false);
  if v_replace and (v_card.id is null or (v_expected is not null and v_expected <> v_card.id)) then
    return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
  end if;
  if not v_replace and not v_recovery and (v_plan.status <> 'draft' or v_plan.is_soft_locked) then
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
    output_snapshot, idempotency_key, request_identity, replaced_daily_card_id)
    values(v_workspace, v_creator, v_plan.weekly_setup_id, v_plan.id, (payload->>'member_id')::uuid,
      'running', payload->>'model', 'creator-weekly-generation-v1', 'day', case when v_recovery then null else v_card.id end, v_date, payload->'input_snapshot',
      jsonb_build_object('kind', 'single_day_generation_v1', 'scheduled_date', v_date, 'status', 'pending',
        'preserve_manual_edits', coalesce((payload->>'preserve_manual_edits')::boolean, false), 'updated_at', now()),
      v_key, v_identity, case when v_replace then v_card.id else null end)
    returning * into v_run;
  update public.creator_days set generation_run_id = v_run.id, updated_at = now()
    where workspace_id = v_workspace and creator_id = v_creator and scheduled_date = v_date;
  return to_jsonb(v_run) || jsonb_build_object('replayed', false);
end;
$$;

create or replace function public.persist_day_revision(payload jsonb)
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
  if not found then
    if v_run.status <> 'running' or v_day.generation_run_id is distinct from v_run.id then
      return jsonb_build_object('error', 'generation_run_closed', 'status', 409);
    end if;
    insert into public.daily_cards(workspace_id, creator_id, weekly_plan_id, scheduled_date, generation_run_id,
      title, why_today, growth_job, content_pillar, shootability, estimated_shoot_minutes, energy_required, language_mode,
      scene_list, shot_content_owned, script, no_voiceover_version, on_screen_text, caption, cta, hashtags, cover_text, post_instructions,
      brand_event_notes, backup_story, backup_caption_only, risk_notes, assumptions, source_note)
    select v_run.workspace_id, v_run.creator_id, v_run.weekly_plan_id, v_run.target_scheduled_date, v_run.id,
      c.title, c.why_today, c.growth_job, c.content_pillar, c.shootability, c.estimated_shoot_minutes, c.energy_required, c.language_mode,
      coalesce(c.scene_list, '[]'), coalesce(c.shot_content_owned, false), c.script, c.no_voiceover_version, coalesce(c.on_screen_text, '[]'), c.caption, c.cta,
      coalesce(c.hashtags, '{}'), c.cover_text, coalesce(c.post_instructions, '{}'), c.brand_event_notes,
      coalesce(c.backup_story, '{}'), coalesce(c.backup_caption_only, '{}'), coalesce(c.risk_notes, '[]'), coalesce(c.assumptions, '[]'), c.source_note
    from jsonb_populate_record(null::public.daily_cards, v_values) c returning * into v_card;
  end if;
  if v_run.status = 'running' and v_day.generation_run_id = v_run.id then
    update public.weekly_generation_runs set status = 'completed', error_code = null, completed_at = clock_timestamp(),
      output_snapshot = jsonb_build_object(
        'generation_id', v_run.id, 'weekly_plan_id', v_run.weekly_plan_id, 'status', 'draft',
        'target_scheduled_date', v_run.target_scheduled_date,
        'daily_card', coalesce(payload->'draft_card', to_jsonb(v_card)) || jsonb_build_object('id', v_card.id),
        'warnings', '[]'::jsonb, 'assumptions', '[]'::jsonb, 'source_summary', '', 'generated_at', clock_timestamp(),
        'visuals_status', 'pending')
      where id = v_run.id and status = 'running';
  end if;
  return to_jsonb(v_card);
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
  v_card record;
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

  if v_daily_card_id is null and v_scheduled_date is null then
    return jsonb_build_object('error', 'invalid_update_ready_day_package_payload', 'status', 400);
  end if;

  if v_daily_card_id is not null then
    select
      dc.id,
      dc.scheduled_date,
      dc.status,
      dc.weekly_plan_id,
      dc.title,
      dc.why_today,
      dc.caption,
      dc.script,
      dc.backup_story,
      dc.backup_caption_only,
      dc.shootability,
      dc.estimated_shoot_minutes,
      dc.scene_list
      into v_card
      from public.daily_cards dc
     where dc.id = v_daily_card_id
       and dc.workspace_id = v_workspace_id
       and dc.creator_id = v_creator_id
       and dc.is_current
       and (v_scheduled_date is null or dc.scheduled_date = v_scheduled_date)
       for update;
  else
    select
      dc.id,
      dc.scheduled_date,
      dc.status,
      dc.weekly_plan_id,
      dc.title,
      dc.why_today,
      dc.caption,
      dc.script,
      dc.backup_story,
      dc.backup_caption_only,
      dc.shootability,
      dc.estimated_shoot_minutes,
      dc.scene_list
      into v_card
      from public.daily_cards dc
     where dc.workspace_id = v_workspace_id
       and dc.creator_id = v_creator_id
       and dc.scheduled_date = v_scheduled_date
       and dc.is_current
       and dc.status in (
         'published',
         'in_decision',
         'shot',
         'posted',
         'used_backup',
         'saved_for_tomorrow',
         'skipped_intentionally'
       )
     order by dc.updated_at desc
     limit 1 for update;
  end if;

  if not found then
    return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
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
    'scheduled_date', v_card.scheduled_date,
    'status', v_card.status,
    'weekly_plan_id', v_card.weekly_plan_id,
    'title', v_title,
    'caption', v_caption
  );
end;
$$;
