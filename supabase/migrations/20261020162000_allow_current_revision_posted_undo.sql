create or replace function public.snapshot_archive_revision()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_card public.daily_cards;
begin
  if tg_op = 'UPDATE' and
    (new.id, new.workspace_id, new.creator_id, new.daily_card_id) is distinct from
    (old.id, old.workspace_id, old.creator_id, old.daily_card_id) then
    raise exception 'archive_revision_immutable' using errcode = 'P0001';
  end if;
  if tg_op = 'DELETE' then
    select * into strict v_card from public.daily_cards where id = old.daily_card_id for update;
    if not v_card.is_current then
      raise exception 'archive_revision_immutable' using errcode = 'P0001';
    end if;
    return old;
  end if;
  select * into strict v_card from public.daily_cards
    where id = new.daily_card_id and workspace_id = new.workspace_id and creator_id = new.creator_id for update;
  if not v_card.is_current then
    if tg_op = 'UPDATE' and (to_jsonb(new) - 'updated_at') = (to_jsonb(old) - 'updated_at') then
      return old;
    end if;
    raise exception 'archive_revision_immutable' using errcode = 'P0001';
  end if;
  if tg_op = 'UPDATE' then
    if old.decision = 'posted' and new.decision = 'posted' then return old; end if;
    if new.decision = old.decision or old.decision = 'posted' then
      new.title_snapshot := old.title_snapshot;
      new.caption_snapshot := old.caption_snapshot;
    else
      new.title_snapshot := v_card.title;
      new.caption_snapshot := v_card.caption;
    end if;
    if new.decision = old.decision then
      new.decision_at := old.decision_at;
    elsif new.decision_at is not distinct from old.decision_at then
      new.decision_at := clock_timestamp();
    end if;
  else
    new.title_snapshot := v_card.title;
    new.caption_snapshot := v_card.caption;
  end if;
  new.decision_at := coalesce(new.decision_at, v_card.decision_at, clock_timestamp());
  return new;
end;
$$;

create trigger zz_protect_archive_revision_delete before delete on public.archive_entries
for each row execute function public.snapshot_archive_revision();

create or replace function public.write_content(payload jsonb)
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
      and creator_id = (payload->>'creator_id')::uuid;
  if not found then return jsonb_build_object('error', 'daily_card_not_found', 'status', 404); end if;
  perform 1 from public.creator_days where workspace_id = v_card.workspace_id and creator_id = v_card.creator_id
    and scheduled_date = v_card.scheduled_date for update;
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
  if not v_card.is_current then
    if v_archive.id is null or v_archive.decision is distinct from v_decision
      or v_archive.archive_date is distinct from v_archive_date
      or v_archive.output_line is distinct from v_output
      or v_archive.has_post_thumbnail is distinct from v_thumbnail
      or (nullif(payload->>'decision_at', '') is not null
        and (payload->>'decision_at')::timestamptz is distinct from v_archive.decision_at) then
      return jsonb_build_object('error', case when v_archive.decision = 'posted' then 'posted_revision_immutable'
        else 'historical_revision_immutable' end, 'status', 409);
    end if;
  else
    v_decision_at := case when v_archive.decision = v_decision then v_archive.decision_at
      else coalesce(nullif(payload->>'decision_at', '')::timestamptz, clock_timestamp()) end;
    if v_archive.decision is distinct from v_decision and v_decision_at is not distinct from v_archive.decision_at then
      v_decision_at := greatest(clock_timestamp(), v_archive.decision_at + interval '1 microsecond');
    end if;
    if v_action = 'complete_today' and (v_archive.decision is distinct from 'posted' or v_decision <> 'posted') then
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
    return jsonb_build_object('action', v_action, 'daily_card', jsonb_build_object('id', v_card.id,
      'status', v_archive.decision, 'decision_at', v_archive.decision_at, 'completed_by_member_id', v_card.completed_by_member_id),
      'archive_entry', to_jsonb(v_archive));
  end if;
  return jsonb_build_object('action', v_action, 'archive_entry', to_jsonb(v_archive));
end;
$$;

revoke all on function public.snapshot_archive_revision(), public.write_content(jsonb) from public, anon, authenticated;
grant execute on function public.write_content(jsonb) to service_role;
