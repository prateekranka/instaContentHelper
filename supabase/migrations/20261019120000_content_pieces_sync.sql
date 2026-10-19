-- Creator content pieces: several independent pieces per date, each stored as
-- the client's versioned document. Revision guards optimistic concurrency;
-- sync_sequence is a monotonic cursor for incremental pulls.

create sequence if not exists public.content_pieces_sync_sequence;

create table if not exists public.content_pieces (
  id uuid primary key,
  workspace_id uuid not null,
  creator_id uuid not null,
  scheduled_date date not null,
  document jsonb not null,
  revision bigint not null default 1 check (revision >= 1),
  sync_sequence bigint not null default nextval('public.content_pieces_sync_sequence'),
  updated_by_member_id uuid references public.members(id) on delete set null,
  client_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  check (jsonb_typeof(document) = 'object'),
  check (pg_column_size(document) <= 524288)
);

create index if not exists content_pieces_creator_sequence_idx
  on public.content_pieces (workspace_id, creator_id, sync_sequence);

create index if not exists content_pieces_creator_date_idx
  on public.content_pieces (workspace_id, creator_id, scheduled_date);

create or replace function public.content_pieces_touch_sync()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.sync_sequence := nextval('public.content_pieces_sync_sequence');
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists content_pieces_touch_sync on public.content_pieces;
create trigger content_pieces_touch_sync
  before update on public.content_pieces
  for each row execute function public.content_pieces_touch_sync();

alter table public.content_pieces enable row level security;
alter table public.content_pieces force row level security;

revoke all on table public.content_pieces from public, anon, authenticated;
grant all privileges on table public.content_pieces to service_role;
grant usage, select on sequence public.content_pieces_sync_sequence to service_role;

comment on table public.content_pieces is
  'Creator content pieces synced from devices through the sync-pieces edge function.';
comment on column public.content_pieces.document is
  'Client piece document: versions, shots, captures, final media metadata and posting records.';
comment on column public.content_pieces.revision is
  'Incremented on every accepted write; clients send the revision they edited.';
