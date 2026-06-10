alter table public.weekly_generation_runs
  add column if not exists generation_scope text not null default 'week'
    check (generation_scope in ('week', 'day')),
  add column if not exists target_daily_card_id uuid
    references public.daily_cards(id) on delete set null,
  add column if not exists target_scheduled_date date;

create index if not exists weekly_generation_runs_day_target_idx
  on public.weekly_generation_runs(
    workspace_id,
    creator_id,
    target_scheduled_date,
    created_at desc
  )
  where generation_scope = 'day';

create index if not exists weekly_generation_runs_target_card_idx
  on public.weekly_generation_runs(target_daily_card_id, created_at desc)
  where target_daily_card_id is not null;
