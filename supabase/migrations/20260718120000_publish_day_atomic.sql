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
   for update;

  if not found then
    return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
  end if;

  if v_status not in ('draft', 'published') then
    return jsonb_build_object('error', 'daily_card_not_publishable', 'status', 409);
  end if;

  update public.daily_cards
     set status = 'archived', updated_at = v_published_at
   where workspace_id = v_workspace_id
     and creator_id = v_creator_id
     and scheduled_date = v_scheduled_date
     and id <> v_daily_card_id
     and status = 'published';
  get diagnostics v_archived_count = row_count;

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

revoke all on function public.publish_day_atomic(jsonb) from public;
grant execute on function public.publish_day_atomic(jsonb) to service_role;
