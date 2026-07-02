alter table public.daily_cards
  add column if not exists storyboard_thumbnail_assets jsonb not null default '[]'::jsonb;

comment on column public.daily_cards.storyboard_thumbnail_assets is
  'Cached generated storyboard thumbnail metadata keyed by zero-based storyboard row index.';

insert into storage.buckets (id, name, public)
values ('storyboard-thumbnails', 'storyboard-thumbnails', true)
on conflict (id) do update
set public = excluded.public;
