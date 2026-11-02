-- Instagram account insights for the "How you're doing" surface.
-- A per-creator connection (long-lived token, used server-side only) plus
-- account-level snapshots used to compute week-over-week deltas.
-- Both tables are service-role only: RLS is enabled with no policies, so the
-- device/anon clients can never read the stored access token.

create table public.creator_instagram_connections (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  creator_id uuid not null references public.creators(id) on delete cascade,
  ig_user_id text not null,
  username text,
  account_type text not null default 'unknown'
    check (account_type in ('business', 'media_creator', 'personal', 'unknown')),
  -- Long-lived Instagram token. Used only by service-role edge functions and
  -- never returned to the device. (Vault/pgsodium encryption is a later hardening.)
  access_token text not null,
  token_expires_at timestamptz,
  scopes text,
  connected_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, creator_id)
);

create index creator_instagram_connections_active_idx
  on public.creator_instagram_connections (workspace_id, creator_id)
  where revoked_at is null;

create trigger creator_instagram_connections_set_updated_at
  before update on public.creator_instagram_connections
  for each row execute function public.set_updated_at();

create table public.creator_account_insight_snapshots (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  creator_id uuid not null references public.creators(id) on delete cascade,
  captured_at timestamptz not null default now(),
  followers_count integer,
  reach_7d integer,
  saves_7d integer,
  metric_source text not null default 'api'
    check (metric_source in ('api', 'manual', 'sample')),
  data_quality text not null default 'complete'
    check (data_quality in ('complete', 'partial', 'estimated')),
  created_at timestamptz not null default now()
);

create index creator_account_insight_snapshots_recent_idx
  on public.creator_account_insight_snapshots (workspace_id, creator_id, captured_at desc);

alter table public.creator_instagram_connections enable row level security;
alter table public.creator_account_insight_snapshots enable row level security;

comment on table public.creator_instagram_connections is
  'Per-creator Instagram (Business Login) connection. access_token is a long-lived token used server-side only and never returned to the device. RLS enabled with no policies = service-role only.';
comment on table public.creator_account_insight_snapshots is
  'Account-level insight snapshots (followers / 7-day reach / 7-day saves) captured per fetch; week-over-week deltas are derived from consecutive snapshots.';
