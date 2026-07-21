-- Per-day Available on Today: promote one draft daily_card to published (ready package)
-- without requiring seven days or setting weekly_plans.is_soft_locked.

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
       and dc.creator_id = v_creator_id;
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
       and dc.status = 'draft'
     order by dc.updated_at desc
     limit 1;
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

  -- Intentionally do not set weekly_plans.status or is_soft_locked.
  -- Week container may remain draft storage underneath.

  return jsonb_build_object(
    'daily_card_id', v_card.id,
    'scheduled_date', v_card.scheduled_date,
    'status', 'published',
    'weekly_plan_id', v_card.weekly_plan_id,
    'week_is_soft_locked', coalesce(v_plan_soft_locked, false)
  );
end;
$$;

revoke all on function public.make_day_available(jsonb) from public, anon, authenticated;
grant execute on function public.make_day_available(jsonb) to service_role;

comment on function public.make_day_available(jsonb) is
  'Promotes one draft daily_card to published (ready package) for Available on Today without week soft-lock or seven-day requirement.';
