create or replace function public.publish_day_atomic(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
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

  select scheduled_date, status
    into v_scheduled_date, v_status
    from public.daily_cards
   where id = v_daily_card_id
     and workspace_id = v_workspace_id
     and creator_id = v_creator_id
     and is_current
   for update;

  if not found then
    return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
  end if;

  if v_status not in ('draft', 'published') then
    return jsonb_build_object('error', 'daily_card_not_publishable', 'status', 409);
  end if;

  update public.daily_cards
     set status = 'published', updated_at = v_published_at
   where id = v_daily_card_id;

  return jsonb_build_object(
    'daily_card_id', v_daily_card_id,
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
  v_card record;
  v_plan_soft_locked boolean;
begin
  if v_workspace_id is null or v_creator_id is null then
    return jsonb_build_object('error', 'invalid_make_day_available_payload', 'status', 400);
  end if;

  if v_daily_card_id is null and v_scheduled_date is null then
    return jsonb_build_object('error', 'invalid_make_day_available_payload', 'status', 400);
  end if;

  if v_daily_card_id is not null then
    select
      dc.id,
      dc.workspace_id,
      dc.creator_id,
      dc.weekly_plan_id,
      dc.scheduled_date,
      dc.status,
      dc.title
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
      dc.workspace_id,
      dc.creator_id,
      dc.weekly_plan_id,
      dc.scheduled_date,
      dc.status,
      dc.title
      into v_card
      from public.daily_cards dc
     where dc.workspace_id = v_workspace_id
       and dc.creator_id = v_creator_id
       and dc.scheduled_date = v_scheduled_date
       and dc.is_current
       and dc.status = 'draft'
     order by dc.updated_at desc
     limit 1 for update;
  end if;

  if not found then
    return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
  end if;

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
       and dc.creator_id = v_creator_id
       and dc.is_current
       and (v_scheduled_date is null or dc.scheduled_date = v_scheduled_date)
       for update;
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

alter function public.write_content(jsonb) rename to write_content_before_revisions;
revoke all on function public.write_content_before_revisions(jsonb) from public, anon, authenticated, service_role;

create function public.write_content(payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
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
    return public.write_content_before_revisions(payload);
  end if;
  select * into v_card from public.daily_cards
    where id = (payload->>'daily_card_id')::uuid and workspace_id = (payload->>'workspace_id')::uuid
      and creator_id = (payload->>'creator_id')::uuid for update;
  if not found then return jsonb_build_object('error', 'daily_card_not_found', 'status', 404); end if;
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
  if v_archive.id is not null and v_archive.decision = 'posted' and v_decision <> 'posted' then
    return jsonb_build_object('error', 'posted_revision_immutable', 'status', 409);
  end if;
  v_decision_at := case when v_archive.decision = v_decision then v_archive.decision_at
    else coalesce(nullif(payload->>'decision_at', '')::timestamptz, v_card.decision_at, now()) end;
  if v_action = 'complete_today' and v_card.is_current and v_archive.decision is distinct from 'posted' then
    update public.daily_cards set status = v_decision, decision_at = v_decision_at,
      completed_by_member_id = (payload->>'member_id')::uuid where id = v_card.id returning * into v_card;
  end if;
  insert into public.archive_entries(workspace_id, creator_id, daily_card_id, archive_date, decision, output_line, has_post_thumbnail, decision_at)
    values(v_card.workspace_id, v_card.creator_id, v_card.id, v_archive_date, v_decision, v_output, v_thumbnail, v_decision_at)
  on conflict (daily_card_id) do update set archive_date = excluded.archive_date, decision = excluded.decision,
    output_line = excluded.output_line, has_post_thumbnail = excluded.has_post_thumbnail, decision_at = excluded.decision_at
  returning * into v_archive;
  if v_action = 'complete_today' then
    return jsonb_build_object('action', v_action, 'daily_card', jsonb_build_object('id', v_card.id,
      'status', v_archive.decision, 'decision_at', v_archive.decision_at, 'completed_by_member_id', v_card.completed_by_member_id),
      'archive_entry', to_jsonb(v_archive));
  end if;
  return jsonb_build_object('action', v_action, 'archive_entry', to_jsonb(v_archive));
end;
$$;

revoke all on function public.write_content(jsonb), public.publish_day_atomic(jsonb), public.make_day_available(jsonb),
  public.unpublish_day(jsonb), public.update_ready_day_package(jsonb) from public, anon, authenticated;
grant execute on function public.write_content(jsonb), public.publish_day_atomic(jsonb), public.make_day_available(jsonb),
  public.unpublish_day(jsonb), public.update_ready_day_package(jsonb) to service_role;

create function public.read_creator_days(payload jsonb)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('days', coalesce(jsonb_agg(jsonb_build_object(
    'scheduled_date', d.scheduled_date,
    'current_revision_id', d.current_revision_id,
    'generation_id', d.generation_run_id,
    'revision', to_jsonb(dc),
    'generation', case when r.id is null then null else jsonb_build_object(
      'generation_id', r.id, 'status', r.status, 'error_code', r.error_code,
      'idempotency_key', r.idempotency_key, 'completed_at', r.completed_at) end,
    'updated_at', greatest(d.updated_at, dc.updated_at, r.updated_at)
  ) order by d.scheduled_date), '[]'::jsonb))
  from public.creator_days d
  left join public.daily_cards dc on dc.id = d.current_revision_id
  left join public.weekly_generation_runs r on r.id = d.generation_run_id
  where d.workspace_id = (payload->>'workspace_id')::uuid and d.creator_id = (payload->>'creator_id')::uuid;
$$;
revoke all on function public.read_creator_days(jsonb) from public, anon, authenticated;
grant execute on function public.read_creator_days(jsonb) to service_role;
