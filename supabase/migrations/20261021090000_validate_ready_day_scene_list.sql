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
        or jsonb_typeof(v_shot->'title') is distinct from 'string'
        or jsonb_typeof(v_shot->'duration') is distinct from 'string'
        or (v_shot ? 'dialogue' and jsonb_typeof(v_shot->'dialogue') is distinct from 'string') then
        return jsonb_build_object('error', 'invalid_package_scene_list', 'field', 'scene_list', 'shot_index', v_shot_index, 'status', 400);
      end if;
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
