-- Preserve generated storyboard thumbnail asset metadata when publishing drafts.

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
  v_card_tags     text[];
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
  v_card_storyboard_thumbnails jsonb;
  v_expected_dates text[];
  v_seen_dates    text[];
  v_plan_update   jsonb;
begin
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

  if jsonb_typeof(v_draft_cards) != 'array' or jsonb_array_length(v_draft_cards) != 7 then
    return jsonb_build_object('error', 'invalid_day_payload', 'status', 400);
  end if;

  v_expected_dates := public.week_date_array(v_draft_plan.week_start_date::text);
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
    v_card_scenes     := coalesce(v_card->'scene_list', '[]'::jsonb);
    v_card_script     := nullif(trim(v_card->>'script'), '');
    v_card_no_vo      := nullif(trim(v_card->>'no_voiceover_version'), '');
    v_card_ost        := coalesce(v_card->'on_screen_text', '[]'::jsonb);
    v_card_caption    := nullif(trim(v_card->>'caption'), '');
    v_card_cta        := nullif(trim(v_card->>'cta'), '');
    v_card_tags       := coalesce(
      (
        select array_agg(tag order by ordinality)
          from jsonb_array_elements_text(coalesce(v_card->'hashtags', '[]'::jsonb))
               with ordinality as tags(tag, ordinality)
      ),
      '{}'::text[]
    );
    v_card_cover      := nullif(trim(v_card->>'cover_text'), '');
    v_card_post       := coalesce(v_card->'post_instructions', '{}'::jsonb);
    if jsonb_typeof(v_card_post) = 'string' then
      v_card_post := jsonb_build_object('line', v_card_post);
    end if;
    v_card_post := v_card_post
      || jsonb_strip_nulls(jsonb_build_object(
        'instructions', coalesce(v_card_post->>'instructions', v_card_post->>'line', v_card->>'post_instructions'),
        'audio_option_notes', coalesce(v_card_post->>'audio_option_notes', v_card->>'audio_option_notes'),
        'format', coalesce(v_card_post->>'format', v_card->>'format'),
        'primary_surface', coalesce(v_card_post->>'primary_surface', v_card->>'primary_surface'),
        'duration_seconds', coalesce(v_card_post->>'duration_seconds', v_card->>'duration_seconds'),
        'hook', coalesce(v_card_post->>'hook', v_card->>'hook'),
        'save_share_reason', coalesce(v_card_post->>'save_share_reason', v_card->>'save_share_reason'),
        'shot_timeline', coalesce(v_card_post->'shot_timeline', v_card->'shot_timeline'),
        'voiceover_timeline', coalesce(v_card_post->'voiceover_timeline', v_card->'voiceover_timeline'),
        'silent_version_timeline', coalesce(v_card_post->'silent_version_timeline', v_card->'silent_version_timeline'),
        'on_screen_text_timeline', coalesce(v_card_post->'on_screen_text_timeline', v_card->'on_screen_text_timeline'),
        'caption_backup_detail', coalesce(v_card_post->>'caption_backup_detail', v_card->>'caption_backup_detail'),
        'creator_fit_score', coalesce(v_card_post->>'creator_fit_score', v_card->>'creator_fit_score')
      ));
    v_card_brand      := nullif(trim(v_card->>'brand_event_notes'), '');
    v_card_backup     := coalesce(v_card->'backup_story', '{}'::jsonb);
    if jsonb_typeof(v_card_backup) = 'string' then
      v_card_backup := jsonb_build_object('line', v_card_backup);
    end if;
    if v_card ? 'backup_story_detail' then
      v_card_backup := v_card_backup || jsonb_build_object('detail', v_card->'backup_story_detail');
    end if;
    v_card_backup_cap := coalesce(v_card->'backup_caption_only', '{}'::jsonb);
    if jsonb_typeof(v_card_backup_cap) = 'string' then
      v_card_backup_cap := jsonb_build_object('line', v_card_backup_cap);
    end if;
    if coalesce(v_card->>'caption_backup_detail', '') <> '' then
      v_card_backup_cap := v_card_backup_cap || jsonb_build_object('detail', v_card->>'caption_backup_detail');
    end if;
    v_card_audio_id   := nullif(v_card->>'audio_option_id', '')::uuid;
    v_card_audio_fb   := nullif(v_card->>'audio_fallback_id', '')::uuid;
    v_card_score      := (v_card->>'creator_fit_score')::double precision;
    v_card_risks      := coalesce(v_card->'risk_notes', '[]'::jsonb);
    v_card_assumps    := coalesce(v_card->'assumptions', '[]'::jsonb);
    v_card_source     := nullif(trim(v_card->>'source_note'), '');
    v_card_storyboard_thumbnails := coalesce(v_card->'storyboard_thumbnail_assets', '[]'::jsonb);
    if jsonb_typeof(v_card_storyboard_thumbnails) != 'array' then
      v_card_storyboard_thumbnails := '[]'::jsonb;
    end if;

    v_review_state := nullif(trim(v_card->>'review_state'), '');
    if v_review_state is null then
      v_review_state := 'ready';
    end if;
    if not (v_review_state in ('open', 'ready', 'backup')) then
      v_review_state := 'ready';
    end if;

    select id into v_existing_id
      from public.daily_cards
     where workspace_id = v_workspace_id
       and creator_id = v_creator_id
       and weekly_plan_id = v_weekly_plan_id
       and scheduled_date = v_scheduled_date::date;

    v_card_id := coalesce(v_existing_id, nullif(v_card->>'id', '')::uuid, gen_random_uuid());

    insert into public.daily_cards (
      id, workspace_id, creator_id, weekly_plan_id,
      scheduled_date, status, review_state, title, why_today,
      growth_job, content_pillar, shootability, estimated_shoot_minutes,
      energy_required, language_mode,
      scene_list, script, no_voiceover_version, on_screen_text,
      caption, cta, hashtags, cover_text, post_instructions,
      brand_event_notes, backup_story, backup_caption_only,
      audio_option_id, audio_fallback_id,
      creator_fit_score, risk_notes, assumptions, source_note,
      storyboard_thumbnail_assets
    ) values (
      v_card_id, v_workspace_id, v_creator_id, v_weekly_plan_id,
      v_scheduled_date::date, 'published', v_review_state, v_card_title, coalesce(v_card_why, 'Prepared for this day.'),
      v_card_growth, v_card_pillar, v_card_shoot, v_card_minutes,
      v_card_energy, v_card_lang,
      v_card_scenes, v_card_script, v_card_no_vo, v_card_ost,
      v_card_caption, v_card_cta, v_card_tags, v_card_cover, v_card_post,
      v_card_brand, v_card_backup, v_card_backup_cap,
      v_card_audio_id, v_card_audio_fb,
      v_card_score, v_card_risks, v_card_assumps, v_card_source,
      v_card_storyboard_thumbnails
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
      scene_list = excluded.scene_list,
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
      audio_option_id = excluded.audio_option_id,
      audio_fallback_id = excluded.audio_fallback_id,
      creator_fit_score = excluded.creator_fit_score,
      risk_notes = excluded.risk_notes,
      assumptions = excluded.assumptions,
      source_note = excluded.source_note,
      storyboard_thumbnail_assets = excluded.storyboard_thumbnail_assets,
      updated_at = v_now;
  end loop;

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

  update public.daily_cards
     set status = 'published'
   where workspace_id = v_workspace_id
     and creator_id = v_creator_id
     and weekly_plan_id = v_weekly_plan_id
     and status = 'draft';

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
  'Atomic existing-draft publish using daily_cards schema columns only; preserves review state and storyboard thumbnail metadata.';
