-- durable-review-atomic-publish
-- Column: daily_cards.review_state (open | ready | backup)
-- RPC:   publish_week_atomic(jsonb) — single-transaction existing-draft publish
-- RPC:   write_content(jsonb)       — extended with update_daily_card_review_state

-- ---------------------------------------------------------------------------
-- 1. Review-state column
-- ---------------------------------------------------------------------------
alter table public.daily_cards
  add column if not exists review_state text not null default 'open';

do $$
begin
  alter table public.daily_cards
    add constraint daily_cards_review_state_check
    check (review_state in ('open', 'ready', 'backup'));
exception
  when duplicate_object then null;
end;
$$;

comment on column public.daily_cards.review_state is
  'Per-card review state. Authoritative for draft cards; open → ready → backup. Published/terminal cards are mapped by status.';

-- ---------------------------------------------------------------------------
-- 2. Week-date helper (service_role only)
-- ---------------------------------------------------------------------------
create or replace function public.week_date_array(week_start_date text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array_agg(d::date::text order by d)
  from generate_series(
    week_start_date::date,
    week_start_date::date + interval '6 days',
    interval '1 day'
  ) as d;
$$;

revoke all on function public.week_date_array(text) from public, anon, authenticated;
grant execute on function public.week_date_array(text) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Atomic existing-draft publish (service_role only)
-- ---------------------------------------------------------------------------
create or replace function public.publish_week_atomic(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_workspace_id  uuid := (payload->>'workspace_id')::uuid;
  v_creator_id    uuid := (payload->>'creator_id')::uuid;
  v_weekly_plan_id uuid := (payload->>'weekly_plan_id')::uuid;
  v_draft_cards   jsonb := payload->'draft_daily_cards';
  v_strategy      text := payload->>'strategy_summary';
  v_card          jsonb;
  v_draft_plan    record;
  v_published_plan record;
  v_existing_id   uuid;
  v_published_count int;
  v_now           timestamptz := now();
  v_card_id       uuid;
  v_scheduled_date text;
  v_review_state  text;
  v_card_title    text;
  v_card_why      text;
  v_card_growth   text;
  v_card_pillar   text;
  v_card_shoot    text;
  v_card_minutes  int;
  v_card_energy   text;
  v_card_lang     text;
  v_card_scenes   jsonb;
  v_card_script   text;
  v_card_no_vo    text;
  v_card_ost      jsonb;
  v_card_caption  text;
  v_card_cta      text;
  v_card_tags     jsonb;
  v_card_cover    text;
  v_card_post     jsonb;
  v_card_brand    text;
  v_card_backup   jsonb;
  v_card_backup_cap jsonb;
  v_card_audio_id uuid;
  v_card_audio_fb uuid;
  v_card_score    double precision;
  v_card_risks    jsonb;
  v_card_assumps  jsonb;
  v_card_source   text;
  v_card_format   text;
  v_card_surface  text;
  v_card_dur      int;
  v_card_hook     text;
  v_card_save     text;
  v_card_shot_tl  jsonb;
  v_card_vo_tl    jsonb;
  v_card_ost_tl   jsonb;
  v_card_silent_tl jsonb;
  v_card_backup_tl jsonb;
  v_card_cap_bkp  text;
  v_expected_dates text[];
  v_seen_dates    text[];
  v_plan_update   jsonb;
begin
  --------------------------------------------------
  -- validate workspace + creator scoped draft plan
  --------------------------------------------------
  select id, workspace_id, creator_id, week_start_date, status, is_soft_locked, published_at
    into v_draft_plan
    from public.weekly_plans
   where workspace_id = v_workspace_id
     and creator_id = v_creator_id
     and id = v_weekly_plan_id;

  if not found then
    return jsonb_build_object('error', 'weekly_plan_not_found', 'status', 404);
  end if;

  if v_draft_plan.workspace_id != v_workspace_id or v_draft_plan.creator_id != v_creator_id then
    return jsonb_build_object('error', 'cross_workspace_forbidden', 'status', 403);
  end if;

  if v_draft_plan.status = 'published' then
    -- Idempotent: return the already-published summary
    select count(*) into v_published_count
      from public.daily_cards
     where workspace_id = v_workspace_id
       and creator_id = v_creator_id
       and weekly_plan_id = v_weekly_plan_id;

    return jsonb_build_object(
      'weekly_plan_id', v_weekly_plan_id,
      'daily_card_count', v_published_count,
      'is_soft_locked', true,
      'published_at', v_draft_plan.published_at
    );
  end if;

  if v_draft_plan.is_soft_locked or not (v_draft_plan.status in ('draft', 'reviewed')) then
    return jsonb_build_object('error', 'existing_published_week_locked', 'status', 409);
  end if;

  --------------------------------------------------
  -- validate draft cards payload
  --------------------------------------------------
  if jsonb_typeof(v_draft_cards) != 'array' or jsonb_array_length(v_draft_cards) != 7 then
    return jsonb_build_object('error', 'invalid_day_payload', 'status', 400);
  end if;

  v_expected_dates := public.week_date_array(v_draft_plan.week_start_date);
  v_seen_dates := array[]::text[];

  for i in 0..jsonb_array_length(v_draft_cards)-1 loop
    v_card := v_draft_cards->i;
    v_scheduled_date := v_card->>'scheduled_date';

    if v_scheduled_date is null
       or not (v_scheduled_date = any(v_expected_dates))
       or v_scheduled_date = any(v_seen_dates) then
      return jsonb_build_object('error', 'invalid_day_payload', 'status', 400);
    end if;

    v_card_title := v_card->>'title';
    if v_card_title is null or trim(v_card_title) = '' then
      return jsonb_build_object('error', 'invalid_day_payload', 'status', 400);
    end if;

    v_seen_dates := array_append(v_seen_dates, v_scheduled_date);
  end loop;

  --------------------------------------------------
  -- BEGIN TRANSACTION
  --------------------------------------------------
  -- 1. Archive any previously-published plan for same creator+week
  select id into v_published_plan
    from public.weekly_plans
   where workspace_id = v_workspace_id
     and creator_id = v_creator_id
     and week_start_date = v_draft_plan.week_start_date
     and status = 'published'
     and id != v_weekly_plan_id;

  if found then
    update public.weekly_plans
       set status = 'replaced',
           is_soft_locked = false,
           replaced_by_weekly_plan_id = v_weekly_plan_id
     where id = v_published_plan.id;

    update public.daily_cards
       set status = 'archived'
     where workspace_id = v_workspace_id
       and creator_id = v_creator_id
       and weekly_plan_id = v_published_plan.id
       and status in ('published','in_decision','shot','posted','used_backup','saved_for_tomorrow','skipped_intentionally');
  end if;

  -- 2. Upsert seven draft cards with rich fields
  for i in 0..jsonb_array_length(v_draft_cards)-1 loop
    v_card := v_draft_cards->i;
    v_scheduled_date := v_card->>'scheduled_date';
    v_card_title      := trim(v_card->>'title');
    v_card_why        := trim(v_card->>'why_today');
    v_card_growth     := nullif(trim(v_card->>'growth_job'), '');
    v_card_pillar     := nullif(trim(v_card->>'content_pillar'), '');
    v_card_shoot      := coalesce(nullif(trim(v_card->>'shootability'), ''), 'easy');
    v_card_minutes    := coalesce((v_card->>'estimated_shoot_minutes')::int, 10);
    v_card_energy     := nullif(trim(v_card->>'energy_required'), '');
    v_card_lang       := nullif(trim(v_card->>'language_mode'), '');
    v_card_format     := nullif(trim(v_card->>'format'), '');
    v_card_surface    := nullif(trim(v_card->>'primary_surface'), '');
    v_card_dur        := (v_card->>'duration_seconds')::int;
    v_card_hook       := nullif(trim(v_card->>'hook'), '');
    v_card_save       := nullif(trim(v_card->>'save_share_reason'), '');
    v_card_scenes     := coalesce(v_card->'scene_list', '[]'::jsonb);
    v_card_shot_tl    := coalesce(v_card->'shot_timeline', '[]'::jsonb);
    v_card_vo_tl      := coalesce(v_card->'voiceover_timeline', '[]'::jsonb);
    v_card_ost_tl     := coalesce(v_card->'on_screen_text_timeline', '[]'::jsonb);
    v_card_silent_tl  := coalesce(v_card->'silent_version_timeline', '[]'::jsonb);
    v_card_script     := nullif(trim(v_card->>'script'), '');
    v_card_no_vo      := nullif(trim(v_card->>'no_voiceover_version'), '');
    v_card_ost        := coalesce(v_card->'on_screen_text', '[]'::jsonb);
    v_card_caption    := nullif(trim(v_card->>'caption'), '');
    v_card_cta        := nullif(trim(v_card->>'cta'), '');
    v_card_tags       := coalesce(v_card->'hashtags', '[]'::jsonb);
    v_card_cover      := nullif(trim(v_card->>'cover_text'), '');
    v_card_post       := coalesce(v_card->'post_instructions', '{}'::jsonb);
    v_card_brand      := nullif(trim(v_card->>'brand_event_notes'), '');
    v_card_backup     := coalesce(v_card->'backup_story', '{}'::jsonb);
    v_card_backup_cap := coalesce(v_card->'backup_caption_only', '{}'::jsonb);
    v_card_backup_tl  := coalesce(v_card->'backup_story_detail', '[]'::jsonb);
    v_card_cap_bkp    := nullif(trim(v_card->>'caption_backup_detail'), '');
    v_card_audio_id   := (v_card->>'audio_option_id')::uuid;
    v_card_audio_fb   := (v_card->>'audio_fallback_id')::uuid;
    v_card_score      := (v_card->>'creator_fit_score')::double precision;
    v_card_risks      := coalesce(v_card->'risk_notes', '[]'::jsonb);
    v_card_assumps    := coalesce(v_card->'assumptions', '[]'::jsonb);
    v_card_source     := nullif(trim(v_card->>'source_note'), '');

    -- build-19 compat: missing review_state defaults to 'ready'
    v_review_state := nullif(trim(v_card->>'review_state'), '');
    if v_review_state is null then
      v_review_state := 'ready';
    end if;
    if not (v_review_state in ('open', 'ready', 'backup')) then
      v_review_state := 'ready';
    end if;

    -- Preserve existing card id on conflict (same weekly_plan+scheduled_date)
    select id into v_existing_id
      from public.daily_cards
     where workspace_id = v_workspace_id
       and creator_id = v_creator_id
       and weekly_plan_id = v_weekly_plan_id
       and scheduled_date = v_scheduled_date;

    v_card_id := coalesce(v_existing_id, (v_card->>'id')::uuid, gen_random_uuid());

    insert into public.daily_cards (
      id, workspace_id, creator_id, weekly_plan_id,
      scheduled_date, status, review_state, title, why_today,
      growth_job, content_pillar, shootability, estimated_shoot_minutes,
      energy_required, language_mode, format, primary_surface,
      duration_seconds, hook, save_share_reason,
      scene_list, shot_timeline, voiceover_timeline,
      on_screen_text_timeline, silent_version_timeline,
      script, no_voiceover_version, on_screen_text,
      caption, cta, hashtags, cover_text, post_instructions,
      brand_event_notes, backup_story, backup_caption_only,
      backup_story_detail, caption_backup_detail,
      audio_option_id, audio_fallback_id,
      creator_fit_score, risk_notes, assumptions, source_note
    ) values (
      v_card_id, v_workspace_id, v_creator_id, v_weekly_plan_id,
      v_scheduled_date, 'published', v_review_state, v_card_title, coalesce(v_card_why, 'Prepared for this day.'),
      v_card_growth, v_card_pillar, v_card_shoot, v_card_minutes,
      v_card_energy, v_card_lang, v_card_format, v_card_surface,
      v_card_dur, v_card_hook, v_card_save,
      v_card_scenes, v_card_shot_tl, v_card_vo_tl,
      v_card_ost_tl, v_card_silent_tl,
      v_card_script, v_card_no_vo, v_card_ost,
      v_card_caption, v_card_cta, v_card_tags, v_card_cover, v_card_post,
      v_card_brand, v_card_backup, v_card_backup_cap,
      v_card_backup_tl, v_card_cap_bkp,
      v_card_audio_id, v_card_audio_fb,
      v_card_score, v_card_risks, v_card_assumps, v_card_source
    )
    on conflict (weekly_plan_id, scheduled_date) do update
    set
      id = excluded.id,
      status = excluded.status,
      review_state = excluded.review_state,
      title = excluded.title,
      why_today = excluded.why_today,
      growth_job = excluded.growth_job,
      content_pillar = excluded.content_pillar,
      shootability = excluded.shootability,
      estimated_shoot_minutes = excluded.estimated_shoot_minutes,
      energy_required = excluded.energy_required,
      language_mode = excluded.language_mode,
      format = excluded.format,
      primary_surface = excluded.primary_surface,
      duration_seconds = excluded.duration_seconds,
      hook = excluded.hook,
      save_share_reason = excluded.save_share_reason,
      scene_list = excluded.scene_list,
      shot_timeline = excluded.shot_timeline,
      voiceover_timeline = excluded.voiceover_timeline,
      on_screen_text_timeline = excluded.on_screen_text_timeline,
      silent_version_timeline = excluded.silent_version_timeline,
      script = excluded.script,
      no_voiceover_version = excluded.no_voiceover_version,
      on_screen_text = excluded.on_screen_text,
      caption = excluded.caption,
      cta = excluded.cta,
      hashtags = excluded.hashtags,
      cover_text = excluded.cover_text,
      post_instructions = excluded.post_instructions,
      brand_event_notes = excluded.brand_event_notes,
      backup_story = excluded.backup_story,
      backup_caption_only = excluded.backup_caption_only,
      backup_story_detail = excluded.backup_story_detail,
      caption_backup_detail = excluded.caption_backup_detail,
      audio_option_id = excluded.audio_option_id,
      audio_fallback_id = excluded.audio_fallback_id,
      creator_fit_score = excluded.creator_fit_score,
      risk_notes = excluded.risk_notes,
      assumptions = excluded.assumptions,
      source_note = excluded.source_note,
      updated_at = v_now;
  end loop;

  -- 3. Mark plan published
  v_plan_update := jsonb_build_object(
    'status', 'published',
    'is_soft_locked', true,
    'published_at', v_now
  );
  if v_strategy is not null and trim(v_strategy) != '' then
    v_plan_update := v_plan_update || jsonb_build_object('strategy_summary', trim(v_strategy));
  end if;

  update public.weekly_plans
     set status = (v_plan_update->>'status'),
         is_soft_locked = (v_plan_update->>'is_soft_locked')::boolean,
         published_at = (v_plan_update->>'published_at')::timestamptz,
         strategy_summary = coalesce(v_plan_update->>'strategy_summary', strategy_summary)
   where workspace_id = v_workspace_id
     and creator_id = v_creator_id
     and id = v_weekly_plan_id;

  -- 4. Mark all 7 cards published
  update public.daily_cards
     set status = 'published'
   where workspace_id = v_workspace_id
     and creator_id = v_creator_id
     and weekly_plan_id = v_weekly_plan_id
     and status = 'draft';

  -- 5. Count for response
  select count(*) into v_published_count
    from public.daily_cards
   where workspace_id = v_workspace_id
     and creator_id = v_creator_id
     and weekly_plan_id = v_weekly_plan_id;

  return jsonb_build_object(
    'weekly_plan_id', v_weekly_plan_id,
    'daily_card_count', v_published_count,
    'is_soft_locked', true,
    'published_at', v_now
  );

exception
  when others then
    return jsonb_build_object(
      'error', 'daily_cards_publish_failed',
      'status', 500,
      'detail', SQLERRM
    );
end;
$$;

revoke all on function public.publish_week_atomic(jsonb) from public, anon, authenticated;
grant execute on function public.publish_week_atomic(jsonb) to service_role;

comment on function public.publish_week_atomic(jsonb) is
  'Atomic existing-draft publish: archives prior week, upserts 7 draft cards, marks plan published. Service role only.';

-- ---------------------------------------------------------------------------
-- 4. Extend write_content: add update_daily_card_review_state action
-- ---------------------------------------------------------------------------
create or replace function public.write_content(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text := payload->>'action';
  v_workspace_id uuid := (payload->>'workspace_id')::uuid;
  v_creator_id uuid := (payload->>'creator_id')::uuid;
  v_member_id uuid := (payload->>'member_id')::uuid;
  v_daily_card_id uuid;
  v_idea_id uuid;
  v_weekly_plan_id uuid;
  v_decision_status text;
  v_output_line text;
  v_has_post_thumbnail boolean;
  v_archive_date date;
  v_decision_at timestamptz;
  v_daily_card record;
  v_archive_entry record;
  v_idea record;
  v_review_state text;
  v_weekly_plan_status text;
  v_weekly_plan_locked boolean;
begin
  if v_action = 'complete_today' then
    begin
      v_daily_card_id := (payload->>'daily_card_id')::uuid;
      v_decision_status := payload #>> '{decision,status}';
      v_decision_at := coalesce(nullif(payload->>'decision_at', '')::timestamptz, now());

      update public.daily_cards
      set
        status = v_decision_status,
        decision_at = v_decision_at,
        completed_by_member_id = v_member_id
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and id = v_daily_card_id
      returning id, status, decision_at, completed_by_member_id
      into v_daily_card;

      if not found then
        return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
      end if;

      return jsonb_build_object(
        'action', v_action,
        'daily_card', jsonb_build_object(
          'id', v_daily_card.id,
          'status', v_daily_card.status,
          'decision_at', v_daily_card.decision_at,
          'completed_by_member_id', v_daily_card.completed_by_member_id
        )
      );
    exception
      when others then
        return jsonb_build_object('error', 'complete_today_failed', 'status', 500);
    end;
  end if;

  if v_action = 'upsert_archive_decision' then
    begin
      v_daily_card_id := (payload->>'daily_card_id')::uuid;
      v_archive_date := (payload->>'archive_date')::date;
      v_decision_status := payload->>'decision';
      v_output_line := payload->>'output_line';
      v_has_post_thumbnail := (payload->>'has_post_thumbnail')::boolean;

      perform 1
      from public.daily_cards
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and id = v_daily_card_id;

      if not found then
        return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
      end if;

      insert into public.archive_entries (
        workspace_id,
        creator_id,
        daily_card_id,
        archive_date,
        decision,
        output_line,
        has_post_thumbnail
      )
      values (
        v_workspace_id,
        v_creator_id,
        v_daily_card_id,
        v_archive_date,
        v_decision_status,
        v_output_line,
        v_has_post_thumbnail
      )
      on conflict (daily_card_id) do update
      set
        archive_date = excluded.archive_date,
        decision = excluded.decision,
        output_line = excluded.output_line,
        has_post_thumbnail = excluded.has_post_thumbnail
      returning
        id,
        daily_card_id,
        archive_date,
        decision,
        output_line,
        has_post_thumbnail
      into v_archive_entry;

      return jsonb_build_object(
        'action', v_action,
        'archive_entry', jsonb_build_object(
          'id', v_archive_entry.id,
          'daily_card_id', v_archive_entry.daily_card_id,
          'archive_date', v_archive_entry.archive_date,
          'decision', v_archive_entry.decision,
          'output_line', v_archive_entry.output_line,
          'has_post_thumbnail', v_archive_entry.has_post_thumbnail
        )
      );
    exception
      when others then
        return jsonb_build_object('error', 'archive_upsert_failed', 'status', 500);
    end;
  end if;

  if v_action = 'select_idea_for_next_open_day' then
    begin
      v_idea_id := (payload->>'idea_id')::uuid;

      if nullif(payload->>'weekly_plan_id', '') is not null then
        v_weekly_plan_id := (payload->>'weekly_plan_id')::uuid;

        perform 1
        from public.weekly_plans
        where workspace_id = v_workspace_id
          and creator_id = v_creator_id
          and id = v_weekly_plan_id;

        if not found then
          return jsonb_build_object('error', 'select_idea_failed', 'status', 404);
        end if;
      end if;

      select
        id,
        title,
        summary,
        suggested_use,
        shootability
      from public.ideas
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and id = v_idea_id
      into v_idea;

      if not found then
        return jsonb_build_object('error', 'idea_not_found', 'status', 404);
      end if;

      select
        id,
        scheduled_date
      from public.daily_cards
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and (v_weekly_plan_id is null or weekly_plan_id = v_weekly_plan_id)
        and status = 'draft'
      order by scheduled_date asc
      limit 1
      into v_daily_card;

      if not found then
        return jsonb_build_object('error', 'select_idea_failed', 'status', 404);
      end if;

      update public.daily_cards
      set
        origin_idea_id = v_idea.id,
        status = 'published',
        title = v_idea.title,
        why_today = coalesce(v_idea.summary, v_idea.suggested_use, 'Prepared from idea bank.'),
        content_pillar = 'idea',
        shootability = coalesce(nullif(v_idea.shootability, ''), 'easy'),
        estimated_shoot_minutes = case
          when estimated_shoot_minutes is null or estimated_shoot_minutes = 0 then 10
          else estimated_shoot_minutes
        end,
        source_note = 'Selected from idea bank.'
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and id = v_daily_card.id
      returning id, status, decision_at, completed_by_member_id
      into v_daily_card;

      update public.ideas
      set status = 'scheduled'
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and id = v_idea_id
      returning id, status
      into v_idea;

      return jsonb_build_object(
        'action', v_action,
        'daily_card', jsonb_build_object(
          'id', v_daily_card.id,
          'status', v_daily_card.status,
          'decision_at', v_daily_card.decision_at,
          'completed_by_member_id', v_daily_card.completed_by_member_id
        ),
        'idea', jsonb_build_object(
          'id', v_idea.id,
          'status', v_idea.status
        )
      );
    exception
      when others then
        return jsonb_build_object('error', 'select_idea_failed', 'status', 500);
    end;
  end if;

  -- NEW ACTION: update_daily_card_review_state
  if v_action = 'update_daily_card_review_state' then
    begin
      v_daily_card_id := (payload->>'daily_card_id')::uuid;
      v_review_state := nullif(trim(payload->>'review_state'), '');

      if v_daily_card_id is null then
        return jsonb_build_object('error', 'invalid_review_state_payload', 'status', 400);
      end if;

      if v_review_state is null or not (v_review_state in ('open', 'ready', 'backup')) then
        return jsonb_build_object('error', 'invalid_review_state_payload', 'status', 400);
      end if;

      -- Validate card belongs to workspace/creator and the weekly plan is draft/reviewed + unlocked
      select dc.weekly_plan_id, wp.status, wp.is_soft_locked
        into v_weekly_plan_id, v_weekly_plan_status, v_weekly_plan_locked
        from public.daily_cards dc
        join public.weekly_plans wp
          on wp.id = dc.weekly_plan_id
         and wp.workspace_id = dc.workspace_id
         and wp.creator_id = dc.creator_id
       where dc.workspace_id = v_workspace_id
         and dc.creator_id = v_creator_id
         and dc.id = v_daily_card_id;

      if not found then
        return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
      end if;

      if v_weekly_plan_locked or not (v_weekly_plan_status in ('draft', 'reviewed')) then
        return jsonb_build_object('error', 'published_week_locked', 'status', 409);
      end if;

      update public.daily_cards
         set review_state = v_review_state
       where workspace_id = v_workspace_id
         and creator_id = v_creator_id
         and id = v_daily_card_id
         and status = 'draft'
       returning id
         into v_daily_card;

      if not found then
        return jsonb_build_object('error', 'review_state_update_failed', 'status', 500);
      end if;

      return jsonb_build_object(
        'action', v_action,
        'daily_card_id', v_daily_card.id,
        'review_state', v_review_state
      );
    exception
      when others then
        return jsonb_build_object('error', 'review_state_update_failed', 'status', 500);
    end;
  end if;

  return jsonb_build_object('error', 'invalid_write_payload', 'status', 400);
end;
$$;

grant execute on function public.write_content(jsonb) to service_role;
