create table public.content_piece_moves (
  workspace_id uuid not null,
  creator_id uuid not null,
  idempotency_key text not null,
  request_identity jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (workspace_id, creator_id, idempotency_key),
  foreign key (workspace_id, creator_id) references public.creators(workspace_id, id) on delete cascade
);
create index content_piece_moves_in_progress_idx on public.content_piece_moves(workspace_id, creator_id, (request_identity->>'piece_id'))
  where result = '{}'::jsonb;
alter table public.content_piece_moves enable row level security;
revoke all on public.content_piece_moves from public, anon, authenticated, service_role;

alter table public.weekly_generation_day_jobs drop constraint weekly_generation_day_jobs_generation_date_key;
create index weekly_generation_day_jobs_generation_date_idx on public.weekly_generation_day_jobs(generation_run_id, scheduled_date);
drop index public.weekly_generation_day_jobs_plan_date_card_idx;
create index weekly_generation_day_jobs_plan_date_card_idx
  on public.weekly_generation_day_jobs(weekly_plan_id, scheduled_date) where daily_card_id is not null;

do $$
declare v_constraint text;
begin
  for v_constraint in select conname from pg_constraint
    where conrelid = 'public.weekly_generation_day_jobs'::regclass
      and confrelid = 'public.daily_cards'::regclass and contype = 'f'
  loop
    execute format('alter table public.weekly_generation_day_jobs alter constraint %I deferrable initially deferred', v_constraint);
  end loop;
end;
$$;

create or replace function public.protect_historical_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_moving boolean;
begin
  v_moving := new.scheduled_date <> old.scheduled_date
    and (to_jsonb(new) - 'scheduled_date' - 'updated_at') = (to_jsonb(old) - 'scheduled_date' - 'updated_at')
    and exists (select 1 from public.content_pieces p where p.id = new.piece_id
      and p.workspace_id = new.workspace_id and p.creator_id = new.creator_id and p.scheduled_date = new.scheduled_date)
    and exists (select 1 from public.content_piece_moves m where m.workspace_id = new.workspace_id and m.creator_id = new.creator_id
      and m.request_identity->>'piece_id' = new.piece_id::text
      and m.request_identity->>'scheduled_date' = old.scheduled_date::text
      and m.request_identity->>'target_scheduled_date' = new.scheduled_date::text
      and m.result = '{}'::jsonb);
  if v_moving then return new; end if;
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

create function public.move_content_piece(payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_workspace uuid;
  v_creator uuid;
  v_id uuid;
  v_source date;
  v_target date;
  v_key text := nullif(btrim(payload->>'idempotency_key'), '');
  v_piece public.content_pieces;
  v_saved public.content_piece_moves;
  v_identity jsonb;
  v_position integer;
  v_source_position integer := 0;
  v_other public.content_pieces;
  v_result jsonb;
begin
  begin
    v_id := nullif(payload->>'piece_id', '')::uuid;
  exception when invalid_text_representation then
    return jsonb_build_object('error', 'invalid_piece_id', 'status', 400);
  end;
  begin
    v_workspace := (payload->>'workspace_id')::uuid;
    v_creator := (payload->>'creator_id')::uuid;
    v_source := (payload->>'scheduled_date')::date;
    v_target := (payload->>'target_scheduled_date')::date;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    return jsonb_build_object('error', 'invalid_move_piece_payload', 'status', 400);
  end;
  if v_id is null then return jsonb_build_object('error', 'invalid_piece_id', 'status', 400); end if;
  if v_workspace is null or v_creator is null or v_source is null or v_target is null
    or v_source::text <> payload->>'scheduled_date' or v_target::text <> payload->>'target_scheduled_date'
    or (payload->>'scheduled_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or (payload->>'target_scheduled_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or jsonb_typeof(payload->'idempotency_key') <> 'string'
    or v_key is null or length(v_key) > 200 then
    return jsonb_build_object('error', 'invalid_move_piece_payload', 'status', 400);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_workspace::text || v_creator::text || v_key, 2));
  v_identity := jsonb_build_object('piece_id', v_id, 'scheduled_date', v_source, 'target_scheduled_date', v_target);
  select * into v_saved from public.content_piece_moves
    where workspace_id = v_workspace and creator_id = v_creator and idempotency_key = v_key;
  if found then
    if v_saved.request_identity is distinct from v_identity then
      return jsonb_build_object('error', 'idempotency_key_conflict', 'status', 409);
    end if;
    return v_saved.result || jsonb_build_object('replayed', true);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_workspace::text || v_creator::text || least(v_source, v_target)::text, 1));
  if v_source <> v_target then
    perform pg_advisory_xact_lock(hashtextextended(v_workspace::text || v_creator::text || greatest(v_source, v_target)::text, 1));
  end if;
  select * into v_piece from public.content_pieces where id = v_id for update;
  if not found then return jsonb_build_object('error', 'piece_not_found', 'status', 404); end if;
  if v_piece.workspace_id <> v_workspace or v_piece.creator_id <> v_creator then
    return jsonb_build_object('error', 'piece_scope_mismatch', 'status', 409);
  end if;
  if v_piece.removed_at is not null then return jsonb_build_object('error', 'piece_removed', 'status', 409); end if;
  if v_piece.scheduled_date <> v_source then return jsonb_build_object('error', 'piece_date_conflict', 'status', 409); end if;
  if exists (select 1 from public.weekly_generation_runs r where r.status = 'running' and (r.piece_id = v_id
    or exists (select 1 from public.weekly_generation_day_jobs j join public.daily_cards dc on dc.id = j.daily_card_id
      where j.generation_run_id = r.id and dc.piece_id = v_id))) then
    return jsonb_build_object('error', 'piece_generation_running', 'status', 409);
  end if;
  perform 1 from public.content_pieces where workspace_id = v_workspace and creator_id = v_creator
    and scheduled_date in (v_source, v_target) and removed_at is null order by scheduled_date, position for update;
  insert into public.content_piece_moves(workspace_id, creator_id, idempotency_key, request_identity, result)
    values(v_workspace, v_creator, v_key, v_identity, '{}'::jsonb);
  if v_source <> v_target then
    select coalesce(max(position) + 1, 0) into v_position from public.content_pieces
      where workspace_id = v_workspace and creator_id = v_creator and scheduled_date = v_target and removed_at is null;
    update public.content_pieces set scheduled_date = v_target, position = v_position, updated_at = clock_timestamp() where id = v_id;
    for v_other in select * from public.content_pieces where workspace_id = v_workspace and creator_id = v_creator
      and scheduled_date = v_source and removed_at is null order by position
    loop
      update public.content_pieces set position = v_source_position, updated_at = clock_timestamp() where id = v_other.id;
      v_source_position := v_source_position + 1;
    end loop;
    update public.daily_cards set scheduled_date = v_target where piece_id = v_id;
    update public.weekly_generation_day_jobs j set scheduled_date = v_target
      where j.daily_card_id in (select id from public.daily_cards where piece_id = v_id)
        or j.generation_run_id in (select id from public.weekly_generation_runs where piece_id = v_id);
    update public.weekly_generation_runs set target_scheduled_date = v_target,
      output_snapshot = case when jsonb_typeof(output_snapshot) = 'object' then output_snapshot
        || jsonb_build_object('target_scheduled_date', v_target, 'scheduled_date', v_target)
        || case when jsonb_typeof(output_snapshot->'daily_card') = 'object' then
          jsonb_build_object('daily_card', output_snapshot->'daily_card' || jsonb_build_object('scheduled_date', v_target)) else '{}'::jsonb end
        else output_snapshot end
      where piece_id = v_id;
    update public.weekly_generation_runs r set output_snapshot = jsonb_set(r.output_snapshot, '{daily_cards}', (
      select jsonb_agg(item.value || case when exists (select 1 from public.daily_cards dc
        where dc.piece_id = v_id and dc.id::text = item.value->>'id') then jsonb_build_object('scheduled_date', v_target)
        else '{}'::jsonb end order by item.ordinality)
      from jsonb_array_elements(r.output_snapshot->'daily_cards') with ordinality item
    )) where r.workspace_id = v_workspace and r.creator_id = v_creator
      and jsonb_typeof(r.output_snapshot->'daily_cards') = 'array'
      and exists (select 1 from jsonb_array_elements(r.output_snapshot->'daily_cards') item
        join public.daily_cards dc on dc.id::text = item->>'id' where dc.piece_id = v_id);
    delete from public.creator_days where workspace_id = v_workspace and creator_id = v_creator and scheduled_date = v_source
      and not exists (select 1 from public.content_pieces where workspace_id = v_workspace and creator_id = v_creator
        and scheduled_date = v_source and position = 0 and removed_at is null);
  else
    v_position := v_piece.position;
  end if;
  select jsonb_build_object('piece_id', v_id, 'source_scheduled_date', v_source, 'scheduled_date', v_target,
    'position', v_position, 'replayed', false, 'affected_pieces', coalesce(jsonb_agg(jsonb_build_object(
      'piece_id', id, 'scheduled_date', scheduled_date, 'position', position) order by scheduled_date, position), '[]'::jsonb))
    into v_result from public.content_pieces where workspace_id = v_workspace and creator_id = v_creator
      and scheduled_date in (v_source, v_target) and removed_at is null;
  update public.content_piece_moves set result = v_result
    where workspace_id = v_workspace and creator_id = v_creator and idempotency_key = v_key;
  return v_result;
end;
$$;
revoke all on function public.move_content_piece(jsonb) from public, anon, authenticated;
grant execute on function public.move_content_piece(jsonb) to service_role;
