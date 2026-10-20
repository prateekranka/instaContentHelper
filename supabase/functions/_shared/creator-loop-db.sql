begin;
do $$
declare
  w uuid := gen_random_uuid();
  c uuid := gen_random_uuid();
  m uuid := gen_random_uuid();
  p uuid := gen_random_uuid();
  old_id uuid := gen_random_uuid();
  new_id uuid;
  run_id uuid;
  d date := current_date + 1;
  input jsonb;
  result jsonb;
  first_archive jsonb;
  card jsonb;
begin
  insert into public.workspaces(id, name) values(w, 'Local revision test');
  insert into public.creators(id, workspace_id, display_name) values(c, w, 'Local creator');
  insert into public.members(id, workspace_id, display_name, role) values(m, w, 'Local member', 'owner');
  insert into public.weekly_plans(id, workspace_id, creator_id, week_start_date) values(p, w, c, d);
  insert into public.daily_cards(id, workspace_id, creator_id, weekly_plan_id, scheduled_date, status, title, caption, post_instructions)
    values(old_id, w, c, p, d, 'published', 'Posted title', 'Posted caption', '{"filmed_shots":["shot-1"]}');
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', old_id, 'decision', jsonb_build_object('status', 'posted', 'output_line', 'Posted', 'has_post_thumbnail', false)));
  if result ? 'error' then raise exception 'complete_today failed: %', result; end if;
  select to_jsonb(a) into first_archive from public.archive_entries a where daily_card_id = old_id;
  if first_archive->>'title_snapshot' <> 'Posted title' or first_archive->>'caption_snapshot' <> 'Posted caption' then
    raise exception 'decision snapshots missing';
  end if;
  result := public.update_ready_day_package(jsonb_build_object('workspace_id', w, 'creator_id', c, 'daily_card_id', old_id,
    'package', jsonb_build_object('caption', E' \n\t')));
  if result->>'error' <> 'blank_package_text' then raise exception 'blank edit accepted: %', result; end if;
  result := public.update_ready_day_package(jsonb_build_object('workspace_id', w, 'creator_id', c, 'daily_card_id', old_id,
    'package', jsonb_build_object('caption', chr(160) || chr(8192) || chr(65279))));
  if result->>'error' is distinct from 'blank_package_text' then raise exception 'unicode blank edit accepted: %', result; end if;
  result := public.update_ready_day_package(jsonb_build_object('workspace_id', w, 'creator_id', c, 'daily_card_id', old_id,
    'package', jsonb_build_object('caption', 'Edited caption')));
  if result ? 'error' then raise exception 'valid edit failed: %', result; end if;
  update public.archive_entries set title_snapshot = 'Changed', caption_snapshot = 'Changed', decision = 'skipped_intentionally' where daily_card_id = old_id;
  if (select to_jsonb(a) from public.archive_entries a where daily_card_id = old_id) <> first_archive then
    raise exception 'posted history changed';
  end if;
  input := jsonb_build_object('workspace_id', w, 'creator_id', c, 'weekly_plan_id', p, 'scheduled_date', d,
    'member_id', m, 'daily_card_id', old_id, 'model', 'local-mock', 'idempotency_key', 'replace-1',
    'request_identity', jsonb_build_object('brief', 'New brief'), 'input_snapshot', '{}'::jsonb);
  begin
    perform public.replace_day(input || jsonb_build_object('member_id', gen_random_uuid()));
    raise exception 'foreign key failure expected';
  exception when foreign_key_violation then null;
  end;
  if (select status from public.daily_cards where id = old_id) <> 'posted' then raise exception 'failed replace did not roll back'; end if;
  result := public.replace_day(input);
  if result ? 'error' then raise exception 'replacement failed: %', result; end if;
  run_id := (result->>'id')::uuid;
  if (select status from public.daily_cards where id = old_id) <> 'archived' then raise exception 'replacement did not unpublish'; end if;
  if (select post_instructions from public.daily_cards where id = old_id) <> '{"filmed_shots":["shot-1"]}'::jsonb then
    raise exception 'filming progress changed';
  end if;
  result := public.replace_day(input);
  if (result->>'id')::uuid <> run_id or result->>'replayed' <> 'true' then raise exception 'replacement duplicated'; end if;
  result := public.replace_day(input || '{"request_identity":{"brief":"Different brief"}}');
  if result->>'error' <> 'idempotency_key_conflict' then raise exception 'changed brief reused key'; end if;
  card := jsonb_build_object('title', 'New title', 'caption', 'New caption');
  result := public.persist_day_revision(jsonb_build_object('workspace_id', w, 'creator_id', c, 'generation_id', run_id, 'card', card));
  if result ? 'error' then raise exception 'revision insert failed: %', result; end if;
  new_id := (result->>'id')::uuid;
  if new_id = old_id then raise exception 'revision id reused'; end if;
  if (select current_revision_id from public.creator_days where workspace_id = w and creator_id = c and scheduled_date = d) <> new_id then
    raise exception 'day pointer was not updated';
  end if;
  result := public.persist_day_revision(jsonb_build_object('workspace_id', w, 'creator_id', c, 'generation_id', run_id, 'card', card));
  if (result->>'id')::uuid <> new_id then raise exception 'persistence replay duplicated revision'; end if;
  if (select count(*) from public.daily_cards where workspace_id = w) <> 2 then raise exception 'revision rows missing'; end if;
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', old_id, 'decision', jsonb_build_object('status', 'posted', 'output_line', 'Replay', 'has_post_thumbnail', true)));
  if result ? 'error' then raise exception 'old decision replay failed: %', result; end if;
  if (select to_jsonb(a) from public.archive_entries a where daily_card_id = old_id) <> first_archive then raise exception 'replay changed posted history'; end if;
  if (select status from public.daily_cards where id = new_id) <> 'draft' then raise exception 'old decision changed current revision'; end if;
  update public.weekly_generation_runs set status = 'failed', error_code = 'local_failure' where id = run_id;
  if (select completed_at from public.weekly_generation_runs where id = run_id) is null then raise exception 'failed run is not closed'; end if;
  begin
    update public.weekly_generation_runs set status = 'running' where id = run_id;
    raise exception 'closed run reopened';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'generation_run_closed' then raise; end if;
  end;
  result := public.start_day_generation((input - 'daily_card_id') || jsonb_build_object('idempotency_key', 'new-brief', 'request_identity', '{"brief":"New attempt"}'::jsonb));
  if result ? 'error' or (result->>'id')::uuid = run_id then raise exception 'new attempt did not create a run: %', result; end if;
  result := public.read_creator_days(jsonb_build_object('workspace_id', w, 'creator_id', c));
  if result #>> '{days,0,current_revision_id}' <> new_id::text then raise exception 'day read pointer incorrect'; end if;
  if has_function_privilege('anon', 'public.replace_day(jsonb)', 'execute') or has_function_privilege('authenticated', 'public.start_day_generation(jsonb)', 'execute') then
    raise exception 'service-only mutation exposed';
  end if;
end;
$$;
rollback;
