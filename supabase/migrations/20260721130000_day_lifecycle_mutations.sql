-- Day lifecycle mutations: Unpublish (ready → draft) and light edit of ready packages.
-- Unpublish clears live Decision fields on the card but never deletes archive_entries.
-- Light edit updates package fields in place and keeps published-lifecycle status.

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
  v_card record;
  v_previous_status text;
  v_cleared_live_decision boolean := false;
  v_archive_retained boolean := false;
begin
  if v_workspace_id is null or v_creator_id is null then
    return jsonb_build_object('error', 'invalid_unpublish_day_payload', 'status', 400);
  end if;

  if v_daily_card_id is null and v_scheduled_date is null then
    return jsonb_build_object('error', 'invalid_unpublish_day_payload', 'status', 400);
  end if;

  if v_daily_card_id is not null then
    select
      dc.id,
      dc.workspace_id,
      dc.creator_id,
      dc.weekly_plan_id,
      dc.scheduled_date,
      dc.status,
      dc.decision_at,
      dc.completed_by_member_id
      into v_card
      from public.daily_cards dc
     where dc.id = v_daily_card_id
       and dc.workspace_id = v_workspace_id
       and dc.creator_id = v_creator_id;
  else
    select
      dc.id,
      dc.workspace_id,
      dc.creator_id,
      dc.weekly_plan_id,
      dc.scheduled_date,
      dc.status,
      dc.decision_at,
      dc.completed_by_member_id
      into v_card
      from public.daily_cards dc
     where dc.workspace_id = v_workspace_id
       and dc.creator_id = v_creator_id
       and dc.scheduled_date = v_scheduled_date
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
     limit 1;
  end if;

  if not found then
    return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
  end if;

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

  -- Intentionally do not delete or mutate archive_entries.
  select exists(
    select 1
      from public.archive_entries ae
     where ae.workspace_id = v_workspace_id
       and ae.creator_id = v_creator_id
       and ae.daily_card_id = v_card.id
  ) into v_archive_retained;

  return jsonb_build_object(
    'daily_card_id', v_card.id,
    'scheduled_date', v_card.scheduled_date,
    'status', 'draft',
    'previous_status', v_previous_status,
    'cleared_live_decision', v_cleared_live_decision,
    'archive_retained', v_archive_retained,
    'weekly_plan_id', v_card.weekly_plan_id
  );
end;
$$;

revoke all on function public.unpublish_day(jsonb) from public, anon, authenticated;
grant execute on function public.unpublish_day(jsonb) to service_role;

comment on function public.unpublish_day(jsonb) is
  'Demotes one ready/decision daily_card to draft. Clears live Decision fields; retains archive_entries.';

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
  v_backup_story text;
  v_backup_caption_only text;
  v_shootability text;
  v_estimated_shoot_minutes integer;
  v_scene_list jsonb;
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
       and dc.creator_id = v_creator_id;
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
     limit 1;
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

  -- Intentionally ignore weekly_plans.is_soft_locked: light edit of a ready
  -- package must not require week unlock and must not demote status.
  v_title := coalesce(nullif(trim(v_package->>'title'), ''), v_card.title);
  v_why_today := coalesce(nullif(trim(v_package->>'why_today'), ''), v_card.why_today);
  v_caption := coalesce(nullif(trim(v_package->>'caption'), ''), v_card.caption);
  v_script := coalesce(nullif(trim(v_package->>'script'), ''), v_card.script);
  v_backup_story := coalesce(nullif(trim(v_package->>'backup_story'), ''), v_card.backup_story);
  v_backup_caption_only := coalesce(
    nullif(trim(v_package->>'backup_caption_only'), ''),
    v_card.backup_caption_only
  );
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

revoke all on function public.update_ready_day_package(jsonb) from public, anon, authenticated;
grant execute on function public.update_ready_day_package(jsonb) to service_role;

comment on function public.update_ready_day_package(jsonb) is
  'Light-edits package fields on a ready/decision daily_card without demoting status or requiring week soft-lock unlock.';
