begin;
create schema piece_migration_fixture;
create table piece_migration_fixture.creators(workspace_id uuid, id uuid, primary key(workspace_id, id));
create table piece_migration_fixture.weekly_plans(id uuid primary key);
create table piece_migration_fixture.archive_entries(id uuid primary key);
create table piece_migration_fixture.weekly_generation_runs(
  id uuid primary key, workspace_id uuid, creator_id uuid, target_scheduled_date date,
  output_snapshot jsonb, status text, error_code text, idempotency_key text,
  completed_at timestamptz, updated_at timestamptz default now()
);
create table piece_migration_fixture.daily_cards(
  id uuid primary key, workspace_id uuid, creator_id uuid, scheduled_date date,
  title text, caption text, status text, is_current boolean not null,
  generation_run_id uuid, created_at timestamptz default now(), updated_at timestamptz default now(),
  unique(workspace_id, creator_id, id)
);
create unique index daily_cards_current_day_key on piece_migration_fixture.daily_cards(workspace_id, creator_id, scheduled_date) where is_current;
create unique index daily_cards_run_date_revision_key on piece_migration_fixture.daily_cards(generation_run_id, scheduled_date) where generation_run_id is not null;
create table piece_migration_fixture.creator_days(
  workspace_id uuid, creator_id uuid, scheduled_date date, current_revision_id uuid, generation_run_id uuid,
  updated_at timestamptz default now(), primary key(workspace_id, creator_id, scheduled_date)
);
create function piece_migration_fixture.protect_historical_revision() returns trigger language plpgsql as $$ begin return new; end; $$;
create trigger protect_historical_revision before update on piece_migration_fixture.daily_cards
  for each row execute function piece_migration_fixture.protect_historical_revision();
create function piece_migration_fixture.replace_day(payload jsonb) returns jsonb language sql as $$ select payload; $$;
insert into piece_migration_fixture.creators values('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222');
insert into piece_migration_fixture.weekly_generation_runs(id, workspace_id, creator_id, target_scheduled_date, status, output_snapshot)
  values('33333333-3333-4333-8333-333333333333', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', '2026-10-21', 'completed', '{"daily_card":{"title":"Current"},"daily_cards":[{"id":"44444444-4444-4444-8444-444444444444"}]}');
insert into piece_migration_fixture.daily_cards(id, workspace_id, creator_id, scheduled_date, title, caption, status, is_current)
  values('44444444-4444-4444-8444-444444444444', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', '2026-10-21', 'Current', 'Current caption', 'published', true),
    ('55555555-5555-4555-8555-555555555555', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', '2026-10-21', 'Previous', 'Previous caption', 'archived', false),
    ('66666666-6666-4666-8666-666666666666', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', '2026-10-23', 'Orphan current', 'Orphan caption', 'draft', true),
    ('77777777-7777-4777-8777-777777777777', '11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', '2026-10-23', 'Orphan history', 'Old orphan caption', 'archived', false);
insert into piece_migration_fixture.creator_days(workspace_id, creator_id, scheduled_date, current_revision_id, generation_run_id)
  values('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', '2026-10-21', '44444444-4444-4444-8444-444444444444', '33333333-3333-4333-8333-333333333333'),
    ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222', '2026-10-22', null, null);
create temporary table before_piece_revisions as select to_jsonb(dc) as revision from piece_migration_fixture.daily_cards dc;
__CONTENT_PIECES_MIGRATION__
do $$
begin
  if (select count(*) from piece_migration_fixture.content_pieces) <> 3
    or (select count(*) from piece_migration_fixture.daily_cards where piece_id is not null) <> 4
    or exists (select 1 from piece_migration_fixture.content_pieces where position <> 0) then
    raise exception 'migration lost dates or revisions';
  end if;
  if exists (select 1 from before_piece_revisions b where not exists (
    select 1 from piece_migration_fixture.daily_cards dc where to_jsonb(dc) - 'piece_id' = b.revision)) then
    raise exception 'migration changed revision content or identity';
  end if;
  if not exists (select 1 from piece_migration_fixture.content_pieces where scheduled_date = '2026-10-21'
    and current_revision_id = '44444444-4444-4444-8444-444444444444' and generation_run_id = '33333333-3333-4333-8333-333333333333') then
    raise exception 'migration lost the current revision or generation pointer';
  end if;
  if exists (select 1 from piece_migration_fixture.weekly_generation_runs
    where output_snapshot #>> '{daily_card,piece_id}' is distinct from piece_id::text
      or output_snapshot #>> '{daily_cards,0,piece_id}' is distinct from piece_id::text) then
    raise exception 'migration omitted piece IDs from saved generation responses';
  end if;
  if (select count(distinct piece_id) from piece_migration_fixture.daily_cards where scheduled_date = '2026-10-21') <> 1
    or (select count(distinct piece_id) from piece_migration_fixture.daily_cards where scheduled_date = '2026-10-23') <> 1 then
    raise exception 'migration split revisions for one date';
  end if;
end;
$$;
rollback;
