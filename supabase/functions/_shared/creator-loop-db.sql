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
  undo_archive jsonb;
  shot_archive jsonb;
  shot_id uuid := gen_random_uuid();
  undecided_id uuid := gen_random_uuid();
  action_name text;
  decision_name text;
  card jsonb;
  invalid_scene_list jsonb;
  before_scene_edit jsonb;
begin
  insert into public.workspaces(id, name) values(w, 'Local revision test');
  insert into public.creators(id, workspace_id, display_name) values(c, w, 'Local creator');
  insert into public.members(id, workspace_id, display_name, role) values(m, w, 'Local member', 'owner');
  insert into public.weekly_plans(id, workspace_id, creator_id, week_start_date) values(p, w, c, d);
  insert into public.daily_cards(id, workspace_id, creator_id, weekly_plan_id, scheduled_date, status, title, caption, post_instructions)
    values(old_id, w, c, p, d, 'published', 'Posted title', 'Posted caption', '{"filmed_shots":["shot-1"]}');
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', old_id, 'decision_at', clock_timestamp() - interval '1 day',
    'decision', jsonb_build_object('status', 'posted', 'output_line', 'Posted', 'has_post_thumbnail', false)));
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
  select to_jsonb(dc) into before_scene_edit from public.daily_cards dc where id = old_id;
  for invalid_scene_list in select value from jsonb_array_elements('[
    null, {}, "shots", 1, true,
    [null], [[]], ["shot"], [1], [true],
    [{}],
    [{"title":"Shot","duration":"5 sec"}],
    [{"id":"shot-1","duration":"5 sec"}],
    [{"id":"shot-1","title":"Shot"}],
    [{"id":1,"title":"Shot","duration":"5 sec"}],
    [{"id":"shot-1","title":null,"duration":"5 sec"}],
    [{"id":"shot-1","title":"Shot","duration":5}],
    [{"id":"shot-1","title":"Shot","duration":"5 sec","dialogue":null}],
    [{"id":"shot-1","title":"Shot","duration":"5 sec","dialogue":{}}],
    [{"id":"shot-1","title":"Shot","duration":"5 sec"}, false]
  ]'::jsonb) loop
    result := public.update_ready_day_package(jsonb_build_object('workspace_id', w, 'creator_id', c, 'daily_card_id', old_id,
      'package', jsonb_build_object('caption', 'Must not be saved', 'scene_list', invalid_scene_list)));
    if result->>'error' is distinct from 'invalid_package_scene_list'
      or result->>'field' is distinct from 'scene_list' or result->>'status' is distinct from '400' then
      raise exception 'invalid scene list accepted: %, result: %', invalid_scene_list, result;
    end if;
    if jsonb_typeof(invalid_scene_list) = 'array' and result->>'shot_index' is distinct from
      (case when jsonb_array_length(invalid_scene_list) = 2 then '1' else '0' end) then
      raise exception 'incorrect invalid shot index: %', result;
    end if;
    if (select to_jsonb(dc) from public.daily_cards dc where id = old_id) is distinct from before_scene_edit then
      raise exception 'invalid scene list partially changed the revision';
    end if;
  end loop;
  for invalid_scene_list in select value from jsonb_array_elements('[
    [],
    [{"id":"shot-1","number":1,"title":"Shot","duration":"5 sec","symbol":"camera","dialogue":"Line"},
     {"id":"shot-2","title":"Silent","duration":"0 sec"},
     {"id":"shot-3","title":"Blank line","duration":"3 sec","dialogue":""}]
  ]'::jsonb) loop
    result := public.update_ready_day_package(jsonb_build_object('workspace_id', w, 'creator_id', c, 'daily_card_id', old_id,
      'package', jsonb_build_object('scene_list', invalid_scene_list)));
    if result ? 'error' or (select scene_list from public.daily_cards where id = old_id) is distinct from invalid_scene_list then
      raise exception 'valid scene list rejected or changed: %', result;
    end if;
  end loop;
  result := public.update_ready_day_package(jsonb_build_object('workspace_id', w, 'creator_id', c, 'daily_card_id', old_id,
    'package', jsonb_build_object('title', 'Edited title', 'caption', 'Edited caption')));
  if result ? 'error' then raise exception 'valid edit failed: %', result; end if;
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', old_id, 'decision', jsonb_build_object('status', 'posted', 'output_line', 'Replay', 'has_post_thumbnail', true)));
  if result ? 'error' or result->'archive_entry' is distinct from first_archive then
    raise exception 'current posted replay changed snapshot: %', result;
  end if;
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', old_id, 'decision', jsonb_build_object('status', 'shot', 'output_line', 'Shot', 'has_post_thumbnail', true)));
  if result ? 'error' or result #>> '{daily_card,status}' is distinct from 'shot' then
    raise exception 'current posted undo failed: %', result;
  end if;
  select to_jsonb(a) into undo_archive from public.archive_entries a where daily_card_id = old_id;
  if undo_archive->>'id' is distinct from first_archive->>'id'
    or undo_archive->>'decision' is distinct from 'shot'
    or undo_archive->>'title_snapshot' is distinct from first_archive->>'title_snapshot'
    or undo_archive->>'caption_snapshot' is distinct from first_archive->>'caption_snapshot'
    or (undo_archive->>'decision_at')::timestamptz <= (first_archive->>'decision_at')::timestamptz then
    raise exception 'current undo did not retain snapshots and set a new decision time';
  end if;
  if (select status from public.daily_cards where id = old_id) is distinct from 'shot'
    or (select decision_at from public.daily_cards where id = old_id) is distinct from (undo_archive->>'decision_at')::timestamptz then
    raise exception 'current undo did not update the card and archive together';
  end if;
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', old_id, 'decision', jsonb_build_object('status', 'shot', 'output_line', 'Shot', 'has_post_thumbnail', true)));
  if result ? 'error' or result->'archive_entry' is distinct from undo_archive then raise exception 'undo replay changed archive: %', result; end if;
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', old_id, 'decision_at', undo_archive->>'decision_at',
    'decision', jsonb_build_object('status', 'posted', 'output_line', 'Posted', 'has_post_thumbnail', false)));
  if result ? 'error' or result #>> '{daily_card,decision_at}' is distinct from result #>> '{archive_entry,decision_at}'
    or result #>> '{archive_entry,decision_at}' is not distinct from undo_archive->>'decision_at' then
    raise exception 'reposting with a reused timestamp did not save a new consistent time: %', result;
  end if;
  select to_jsonb(a) into first_archive from public.archive_entries a where daily_card_id = old_id;
  result := public.write_content(jsonb_build_object('action', 'upsert_archive_decision', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', old_id, 'archive_date', d, 'decision', 'shot', 'output_line', 'Archive undo', 'has_post_thumbnail', false));
  if result ? 'error' or result #>> '{archive_entry,decision}' is distinct from 'shot'
    or result #>> '{archive_entry,title_snapshot}' is distinct from first_archive->>'title_snapshot'
    or result #>> '{archive_entry,caption_snapshot}' is distinct from first_archive->>'caption_snapshot'
    or result #>> '{archive_entry,decision_at}' is not distinct from first_archive->>'decision_at' then
    raise exception 'current archive undo failed: %', result;
  end if;
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', old_id, 'decision', jsonb_build_object('status', 'posted', 'output_line', 'Posted', 'has_post_thumbnail', false)));
  if result ? 'error' then raise exception 'reposting after archive undo failed: %', result; end if;
  select to_jsonb(a) into first_archive from public.archive_entries a where daily_card_id = old_id;
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
  foreach action_name in array array['complete_today', 'upsert_archive_decision'] loop
    result := public.write_content(jsonb_build_object('action', action_name, 'workspace_id', w, 'creator_id', c,
      'member_id', m, 'daily_card_id', old_id, 'archive_date', d, 'output_line', 'Posted', 'has_post_thumbnail', false,
      'decision', case when action_name = 'complete_today' then
        jsonb_build_object('status', 'posted', 'output_line', 'Posted', 'has_post_thumbnail', false) else '"posted"'::jsonb end));
    if result ? 'error' or result->'archive_entry' is distinct from first_archive then raise exception 'old decision replay failed: %', result; end if;
  end loop;
  if (select to_jsonb(a) from public.archive_entries a where daily_card_id = old_id) <> first_archive then raise exception 'replay changed posted history'; end if;
  if (select status from public.daily_cards where id = new_id) <> 'draft' then raise exception 'old decision changed current revision'; end if;
  foreach action_name in array array['complete_today', 'upsert_archive_decision'] loop
    foreach decision_name in array array['shot', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally', 'posted'] loop
      result := public.write_content(jsonb_build_object('action', action_name, 'workspace_id', w, 'creator_id', c,
        'member_id', m, 'daily_card_id', old_id, 'archive_date', d, 'output_line', 'Changed', 'has_post_thumbnail', true,
        'decision', case when action_name = 'complete_today' then
          jsonb_build_object('status', decision_name, 'output_line', 'Changed', 'has_post_thumbnail', true) else to_jsonb(decision_name) end));
      if result->>'error' is distinct from 'posted_revision_immutable' or result->>'status' is distinct from '409' then
        raise exception 'replaced posted revision accepted % / %: %', action_name, decision_name, result;
      end if;
    end loop;
  end loop;
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', old_id, 'decision_at', clock_timestamp() + interval '1 day',
    'decision', jsonb_build_object('status', 'posted', 'output_line', 'Posted', 'has_post_thumbnail', false)));
  if result->>'error' is distinct from 'posted_revision_immutable' then raise exception 'replaced decision timestamp changed: %', result; end if;
  begin
    update public.archive_entries set title_snapshot = 'Changed', caption_snapshot = 'Changed', decision = 'shot' where daily_card_id = old_id;
    raise exception 'replaced posted archive mutation accepted';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'archive_revision_immutable' then raise; end if;
  end;
  begin
    delete from public.archive_entries where daily_card_id = old_id;
    raise exception 'replaced archive deletion accepted';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'archive_revision_immutable' then raise; end if;
  end;
  if (select to_jsonb(a) from public.archive_entries a where daily_card_id = old_id) is distinct from first_archive then
    raise exception 'replaced posted snapshot changed';
  end if;
  if (select status from public.daily_cards where id = old_id) is distinct from 'archived'
    or (select status from public.daily_cards where id = new_id) is distinct from 'draft' then
    raise exception 'rejected historical decisions changed card state';
  end if;
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
  insert into public.daily_cards(id, workspace_id, creator_id, weekly_plan_id, scheduled_date, status, title, caption)
    values(shot_id, w, c, p, d + 1, 'published', 'Shot title', 'Shot caption');
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', shot_id, 'decision', jsonb_build_object('status', 'shot', 'output_line', 'Shot', 'has_post_thumbnail', false)));
  if result ? 'error' then raise exception 'shot setup failed: %', result; end if;
  select to_jsonb(a) into shot_archive from public.archive_entries a where daily_card_id = shot_id;
  insert into public.daily_cards(workspace_id, creator_id, weekly_plan_id, scheduled_date, title)
    values(w, c, p, d + 1, 'Replacement for shot');
  foreach action_name in array array['complete_today', 'upsert_archive_decision'] loop
    foreach decision_name in array array['shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally'] loop
      result := public.write_content(jsonb_build_object('action', action_name, 'workspace_id', w, 'creator_id', c,
        'member_id', m, 'daily_card_id', shot_id, 'archive_date', d + 1, 'output_line', 'Changed', 'has_post_thumbnail', true,
        'decision', case when action_name = 'complete_today' then
          jsonb_build_object('status', decision_name, 'output_line', 'Changed', 'has_post_thumbnail', true) else to_jsonb(decision_name) end));
      if result->>'error' is distinct from 'historical_revision_immutable' or result->>'status' is distinct from '409' then
        raise exception 'replaced shot revision accepted % / %: %', action_name, decision_name, result;
      end if;
    end loop;
  end loop;
  begin
    update public.archive_entries set output_line = 'Changed' where daily_card_id = shot_id;
    raise exception 'replaced shot archive mutation accepted';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'archive_revision_immutable' then raise; end if;
  end;
  if (select to_jsonb(a) from public.archive_entries a where daily_card_id = shot_id) is distinct from shot_archive then
    raise exception 'replaced shot snapshot changed';
  end if;
  insert into public.daily_cards(id, workspace_id, creator_id, weekly_plan_id, scheduled_date, title)
    values(undecided_id, w, c, p, d + 2, 'Undecided revision');
  insert into public.daily_cards(workspace_id, creator_id, weekly_plan_id, scheduled_date, title)
    values(w, c, p, d + 2, 'Replacement for undecided revision');
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'member_id', m, 'daily_card_id', undecided_id, 'decision', jsonb_build_object('status', 'posted', 'output_line', 'Late post', 'has_post_thumbnail', false)));
  if result->>'error' is distinct from 'historical_revision_immutable'
    or (select decision from public.archive_entries where daily_card_id = undecided_id) is distinct from 'replaced' then
    raise exception 'undecided replaced revision accepted a late decision: %', result;
  end if;
  if has_function_privilege('anon', 'public.replace_day(jsonb)', 'execute') or has_function_privilege('authenticated', 'public.start_day_generation(jsonb)', 'execute') then
    raise exception 'service-only mutation exposed';
  end if;
end;
$$;
rollback;
