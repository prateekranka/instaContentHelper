create table if not exists public.weekly_generation_runs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  creator_id uuid not null,
  weekly_setup_id uuid references public.weekly_setups(id) on delete set null,
  weekly_plan_id uuid references public.weekly_plans(id) on delete set null,
  requested_by_member_id uuid references public.members(id) on delete set null,
  status text not null default 'running'
    check (status in ('running', 'completed', 'failed')),
  model text,
  prompt_version text not null,
  input_snapshot jsonb not null default '{}'::jsonb,
  output_snapshot jsonb not null default '{}'::jsonb,
  warnings jsonb not null default '[]'::jsonb,
  assumptions jsonb not null default '[]'::jsonb,
  error_code text,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade
);

create index if not exists weekly_generation_runs_workspace_creator_created_idx
  on public.weekly_generation_runs(workspace_id, creator_id, created_at desc);

create index if not exists weekly_generation_runs_creator_setup_idx
  on public.weekly_generation_runs(creator_id, weekly_setup_id, created_at desc);

create index if not exists weekly_generation_runs_weekly_plan_idx
  on public.weekly_generation_runs(weekly_plan_id);

create index if not exists weekly_generation_runs_status_idx
  on public.weekly_generation_runs(status, created_at desc);
