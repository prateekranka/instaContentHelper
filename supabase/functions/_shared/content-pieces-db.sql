begin;
do $$
declare
  w uuid := gen_random_uuid();
  c uuid := gen_random_uuid();
  foreign_creator uuid := gen_random_uuid();
  m uuid := gen_random_uuid();
  plan_id uuid := gen_random_uuid();
  piece0 uuid;
  piece1 uuid := gen_random_uuid();
  card0 uuid;
  card1 uuid;
  run0 uuid;
  run1 uuid;
  d date := current_date + 1;
  result jsonb;
  input jsonb;
  saved0 jsonb;
  saved1 jsonb;
  target_piece uuid := gen_random_uuid();
  target_card uuid;
  move_result jsonb;
  before_revisions jsonb;
  before_archive jsonb;
  job_id uuid := gen_random_uuid();
  target_job uuid := gen_random_uuid();
  legacy_run uuid := gen_random_uuid();
begin
  if exists (select 1 from public.daily_cards dc left join public.content_pieces p on p.id = dc.piece_id
    where dc.piece_id is null or p.id is null or (p.workspace_id, p.creator_id, p.scheduled_date)
      is distinct from (dc.workspace_id, dc.creator_id, dc.scheduled_date)) then
    raise exception 'migration left an unbound revision';
  end if;
  insert into public.workspaces(id, name) values(w, 'Local pieces');
  insert into public.creators(id, workspace_id, display_name) values(c, w, 'Creator'), (foreign_creator, w, 'Other creator');
  insert into public.members(id, workspace_id, display_name, role) values(m, w, 'Owner', 'owner');
  insert into public.weekly_plans(id, workspace_id, creator_id, week_start_date) values(plan_id, w, c, d);
  input := jsonb_build_object('workspace_id', w, 'creator_id', c, 'weekly_plan_id', plan_id, 'scheduled_date', d,
    'member_id', m, 'model', 'local-mock', 'input_snapshot', '{}'::jsonb, 'request_identity', '{}'::jsonb, 'idempotency_key', 'piece-zero');
  result := public.start_day_generation(input);
  if result ? 'error' then raise exception 'legacy generation failed: %', result; end if;
  piece0 := (result->>'piece_id')::uuid;
  run0 := (result->>'id')::uuid;
  result := public.start_day_generation(input || jsonb_build_object('piece_id', piece1, 'idempotency_key', 'piece-one'));
  if result ? 'error' then raise exception 'second generation failed: %', result; end if;
  run1 := (result->>'id')::uuid;
  if (select status from public.weekly_generation_runs where id = run0) <> 'running' then
    raise exception 'second piece superseded first run';
  end if;
  result := public.start_day_generation(input || jsonb_build_object('piece_id', piece1, 'idempotency_key', 'piece-one'));
  if result->>'replayed' is distinct from 'true' or (result->>'id')::uuid <> run1
    or (select count(*) from public.content_pieces where id = piece1) <> 1 then
    raise exception 'client piece creation was not idempotent: %', result;
  end if;
  result := public.persist_day_revision(jsonb_build_object('workspace_id', w, 'creator_id', c, 'generation_id', run0,
    'card', jsonb_build_object('title', 'First piece', 'caption', 'First caption')));
  if result ? 'error' or (result->>'piece_id')::uuid <> piece0 then raise exception 'first revision failed: %', result; end if;
  card0 := (result->>'id')::uuid;
  result := public.persist_day_revision(jsonb_build_object('workspace_id', w, 'creator_id', c, 'generation_id', run1,
    'card', jsonb_build_object('title', 'Second piece', 'caption', 'Second caption')));
  if result ? 'error' or (result->>'piece_id')::uuid <> piece1 then raise exception 'second revision failed: %', result; end if;
  card1 := (result->>'id')::uuid;
  result := public.make_day_available(jsonb_build_object('workspace_id', w, 'creator_id', c, 'scheduled_date', d));
  if result ? 'error' or (result->>'daily_card_id')::uuid <> card0 then raise exception 'legacy make ready missed position 0: %', result; end if;
  result := public.make_day_available(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece1));
  if result ? 'error' then raise exception 'second make ready failed: %', result; end if;
  if (select count(*) from public.daily_cards where piece_id in (piece0, piece1) and is_current and status = 'published') <> 2 then
    raise exception 'two pieces could not both stay ready';
  end if;
  result := public.update_ready_day_package(jsonb_build_object('workspace_id', w, 'creator_id', c, 'scheduled_date', d,
    'package', jsonb_build_object('caption', 'Legacy edit')));
  if result ? 'error' or (result->>'piece_id')::uuid <> piece0
    or (select caption from public.daily_cards where id = card1) <> 'Second caption' then
    raise exception 'legacy package edit touched the wrong piece: %', result;
  end if;
  result := public.unpublish_day(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece1));
  if result ? 'error' then raise exception 'second unpublish failed: %', result; end if;
  select to_jsonb(dc) into saved1 from public.daily_cards dc where id = card1;
  result := public.write_content(jsonb_build_object('action', 'complete_today', 'workspace_id', w, 'creator_id', c,
    'scheduled_date', d, 'member_id', m, 'decision', jsonb_build_object('status', 'posted', 'output_line', 'Posted', 'has_post_thumbnail', false)));
  if result ? 'error' or (result #>> '{daily_card,piece_id}')::uuid <> piece0
    or (result #>> '{archive_entry,piece_id}')::uuid <> piece0 then raise exception 'piece decision failed: %', result; end if;
  if (select to_jsonb(dc) from public.daily_cards dc where id = card1) is distinct from saved1
    or saved1->>'status' <> 'draft' then raise exception 'posting first changed second draft'; end if;
  result := public.make_day_available(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece1));
  if result ? 'error' then raise exception 'second make ready before replacement failed: %', result; end if;
  select to_jsonb(dc) into saved1 from public.daily_cards dc where id = card1;
  result := public.replace_day(input || jsonb_build_object('piece_id', piece0, 'daily_card_id', card0, 'idempotency_key', 'replace-first'));
  if result ? 'error' then raise exception 'piece replacement failed: %', result; end if;
  run0 := (result->>'id')::uuid;
  if (select to_jsonb(dc) from public.daily_cards dc where id = card1) is distinct from saved1
    or exists (select 1 from public.archive_entries where daily_card_id = card1) then raise exception 'replacement changed second piece'; end if;
  result := public.persist_day_revision(jsonb_build_object('workspace_id', w, 'creator_id', c, 'generation_id', run0,
    'card', jsonb_build_object('title', 'Replacement', 'caption', 'New caption')));
  if result ? 'error' or (result->>'piece_id')::uuid <> piece0 then raise exception 'replacement revision failed: %', result; end if;
  card0 := (result->>'id')::uuid;
  if (select to_jsonb(dc) from public.daily_cards dc where id = card1) is distinct from saved1 then raise exception 'replacement insert changed second piece'; end if;
  select to_jsonb(dc) into saved0 from public.daily_cards dc where id = card0;
  result := public.resolve_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', foreign_creator, 'scheduled_date', d, 'piece_id', piece1));
  if result->>'error' is distinct from 'piece_scope_mismatch' then raise exception 'foreign creator piece accepted: %', result; end if;
  result := public.resolve_content_piece(jsonb_build_object('workspace_id', gen_random_uuid(), 'creator_id', c, 'scheduled_date', d, 'piece_id', piece1));
  if result->>'error' is distinct from 'piece_scope_mismatch' then raise exception 'foreign workspace piece accepted: %', result; end if;
  result := public.start_day_generation(input || jsonb_build_object('scheduled_date', d + 1, 'piece_id', piece1, 'idempotency_key', 'foreign-date'));
  if result->>'error' is distinct from 'piece_scope_mismatch' then raise exception 'foreign date piece accepted: %', result; end if;
  result := public.make_day_available(jsonb_build_object('workspace_id', w, 'creator_id', c, 'daily_card_id', card0, 'piece_id', piece1));
  if result->>'error' is distinct from 'piece_revision_mismatch' then raise exception 'wrong revision piece accepted: %', result; end if;
  if (select to_jsonb(dc) from public.daily_cards dc where id = card0) is distinct from saved0 then raise exception 'rejection changed first piece'; end if;
  if (select current_revision_id from public.creator_days where workspace_id = w and creator_id = c and scheduled_date = d) <> card0
    or (select generation_run_id from public.creator_days where workspace_id = w and creator_id = c and scheduled_date = d) <> run0 then
    raise exception 'legacy pointer no longer mirrors position 0';
  end if;
  result := public.read_creator_days(jsonb_build_object('workspace_id', w, 'creator_id', c));
  if jsonb_array_length(result->'days') <> 1 or (result #>> '{days,0,piece_id}')::uuid <> piece0 then raise exception 'legacy day read failed: %', result; end if;
  result := public.read_creator_days(jsonb_build_object('workspace_id', w, 'creator_id', c, 'include_all_pieces', true));
  if jsonb_array_length(result->'days') <> 2 then raise exception 'piece day read lost a piece: %', result; end if;
  if (select count(*) from public.daily_cards where piece_id = piece0 and is_current) <> 1 then raise exception 'piece has multiple current revisions'; end if;
  result := public.start_day_generation(input || jsonb_build_object('piece_id', target_piece, 'scheduled_date', d + 1, 'idempotency_key', 'move-target'));
  if result ? 'error' then raise exception 'move target generation failed: %', result; end if;
  result := public.persist_day_revision(jsonb_build_object('workspace_id', w, 'creator_id', c, 'generation_id', result->>'id',
    'card', jsonb_build_object('title', 'Target piece', 'caption', 'Target caption')));
  if result ? 'error' then raise exception 'move target revision failed: %', result; end if;
  target_card := (result->>'id')::uuid;
  update public.daily_cards set post_instructions = jsonb_build_object('filmed_shots', jsonb_build_array('1407e44a-1f70-4b96-8ee2-000000000001')) where id = card0;
  insert into public.weekly_generation_runs(id, workspace_id, creator_id, weekly_plan_id, status, prompt_version, output_snapshot)
    values(legacy_run, w, c, plan_id, 'completed', 'local-legacy', jsonb_build_object('daily_cards', jsonb_build_array(
      jsonb_build_object('id', card0, 'scheduled_date', d), jsonb_build_object('id', target_card, 'scheduled_date', d + 1))));
  insert into public.weekly_generation_day_jobs(id, generation_run_id, weekly_plan_id, workspace_id, creator_id, scheduled_date, day_index, status, daily_card_id)
    values(job_id, legacy_run, plan_id, w, c, d, 0, 'retrying', card0),
      (target_job, legacy_run, plan_id, w, c, d + 1, 1, 'generated', target_card);
  select jsonb_agg(to_jsonb(dc) - 'scheduled_date' - 'updated_at' order by dc.id) into before_revisions
    from public.daily_cards dc where piece_id = piece0;
  select jsonb_agg(to_jsonb(a) order by a.id) into before_archive from public.archive_entries a
    where daily_card_id in (select id from public.daily_cards where piece_id = piece0);
  move_result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece0,
    'scheduled_date', d, 'target_scheduled_date', d + 1, 'idempotency_key', 'move-zero'));
  if move_result ? 'error' or move_result->>'position' <> '1' then raise exception 'move did not append: %', move_result; end if;
  if (select jsonb_agg(to_jsonb(dc) - 'scheduled_date' - 'updated_at' order by dc.id) from public.daily_cards dc where piece_id = piece0)
    is distinct from before_revisions then raise exception 'move changed revision work'; end if;
  if (select jsonb_agg(to_jsonb(a) order by a.id) from public.archive_entries a
    where daily_card_id in (select id from public.daily_cards where piece_id = piece0)) is distinct from before_archive then
    raise exception 'move changed archive decisions'; end if;
  if (select output_snapshot #>> '{daily_cards,0,scheduled_date}' from public.weekly_generation_runs where id = legacy_run) <> (d + 1)::text
    or (select daily_card_id from public.weekly_generation_day_jobs where id = target_job) <> target_card
    or (select status from public.weekly_generation_day_jobs where id = job_id) <> 'retrying' then
    raise exception 'move lost saved full-week output or queued job state'; end if;
  if exists (select 1 from public.daily_cards where piece_id = piece0 and scheduled_date <> d + 1)
    or (select scheduled_date from public.weekly_generation_day_jobs where id = job_id) <> d + 1
    or exists (select 1 from public.weekly_generation_runs where piece_id = piece0 and target_scheduled_date <> d + 1) then
    raise exception 'move left a revision or queued job behind';
  end if;
  if (select position from public.content_pieces where id = piece1) <> 0
    or (select current_revision_id from public.creator_days where workspace_id = w and creator_id = c and scheduled_date = d) <> card1
    or (select current_revision_id from public.creator_days where workspace_id = w and creator_id = c and scheduled_date = d + 1) <> target_card then
    raise exception 'move broke position zero or its mirror'; end if;
  result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece0,
    'scheduled_date', d, 'target_scheduled_date', d + 1, 'idempotency_key', 'move-zero'));
  if result - 'replayed' is distinct from move_result - 'replayed' or result->>'replayed' <> 'true' then
    raise exception 'move replay was not stable: %', result; end if;
  result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece0,
    'scheduled_date', d, 'target_scheduled_date', d + 2, 'idempotency_key', 'move-zero'));
  if result->>'error' is distinct from 'idempotency_key_conflict' then raise exception 'changed move key accepted: %', result; end if;
  result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece0,
    'scheduled_date', d, 'target_scheduled_date', d + 2, 'idempotency_key', 'stale-source'));
  if result->>'error' is distinct from 'piece_date_conflict' then raise exception 'stale source accepted: %', result; end if;
  result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', foreign_creator, 'piece_id', piece0,
    'scheduled_date', d + 1, 'target_scheduled_date', d, 'idempotency_key', 'foreign-move'));
  if result->>'error' is distinct from 'piece_scope_mismatch' then raise exception 'foreign move accepted: %', result; end if;
  result := public.move_content_piece(jsonb_build_object('workspace_id', gen_random_uuid(), 'creator_id', c, 'piece_id', piece0,
    'scheduled_date', d + 1, 'target_scheduled_date', d, 'idempotency_key', 'foreign-workspace'));
  if result->>'error' is distinct from 'piece_scope_mismatch' then raise exception 'foreign workspace move accepted: %', result; end if;
  result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece1,
    'scheduled_date', d, 'target_scheduled_date', d + 2, 'idempotency_key', 'move-last'));
  if result ? 'error' or result->>'position' <> '0'
    or exists(select 1 from public.creator_days where workspace_id = w and creator_id = c and scheduled_date = d) then
    raise exception 'last piece move left a source mirror: %', result; end if;
  result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece1,
    'scheduled_date', d + 2, 'target_scheduled_date', d + 2, 'idempotency_key', 'same-date'));
  if result ? 'error' or result->>'position' <> '0' then raise exception 'same date move reordered a piece: %', result; end if;
  result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', gen_random_uuid(),
    'scheduled_date', d, 'target_scheduled_date', d + 2, 'idempotency_key', 'missing-piece'));
  if result->>'error' is distinct from 'piece_not_found' then raise exception 'missing piece moved: %', result; end if;
  result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', 'bad',
    'scheduled_date', d, 'target_scheduled_date', d + 2, 'idempotency_key', 'bad-piece'));
  if result->>'error' is distinct from 'invalid_piece_id' then raise exception 'malformed piece moved: %', result; end if;
  result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece1,
    'scheduled_date', d + 2, 'target_scheduled_date', '2026-02-30', 'idempotency_key', 'bad-date'));
  if result->>'error' is distinct from 'invalid_move_piece_payload' then raise exception 'malformed date moved: %', result; end if;
  update public.content_pieces set removed_at = now() where id = piece1;
  result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece1,
    'scheduled_date', d + 2, 'target_scheduled_date', d, 'idempotency_key', 'removed-piece'));
  if result->>'error' is distinct from 'piece_removed' then raise exception 'removed piece moved: %', result; end if;
  result := public.start_day_generation(input || jsonb_build_object('piece_id', piece0, 'scheduled_date', d + 1, 'idempotency_key', 'busy-piece'));
  if result ? 'error' then raise exception 'busy piece generation failed: %', result; end if;
  result := public.move_content_piece(jsonb_build_object('workspace_id', w, 'creator_id', c, 'piece_id', piece0,
    'scheduled_date', d + 1, 'target_scheduled_date', d, 'idempotency_key', 'busy-move'));
  if result->>'error' is distinct from 'piece_generation_running'
    or (select scheduled_date from public.content_pieces where id = piece0) <> d + 1 then
    raise exception 'running piece moved: %', result; end if;
  if has_function_privilege('authenticated', 'public.move_content_piece(jsonb)', 'EXECUTE')
    or has_function_privilege('anon', 'public.move_content_piece(jsonb)', 'EXECUTE')
    or not has_function_privilege('service_role', 'public.move_content_piece(jsonb)', 'EXECUTE')
    or has_table_privilege('service_role', 'public.content_piece_moves', 'INSERT') then raise exception 'move grants are unsafe'; end if;

end;
$$;
set constraints all immediate;
rollback;
