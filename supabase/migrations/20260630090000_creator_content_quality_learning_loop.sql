-- Creator Content Quality + Learning Loop foundation.
-- Passive storage only: no Edge Function, generation prompt, or OpenAI contract changes.

create table public.content_quality_scores (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  daily_card_id uuid,
  quality_version text not null,
  scoring_version text not null,
  hard_gate_version text not null,
  overall_score numeric(5, 2) not null check (overall_score between 0 and 100),
  category_scores jsonb not null default '{}'::jsonb,
  weakest_categories text[] not null default '{}',
  suggested_improvements jsonb not null default '[]'::jsonb,
  hard_gate_result jsonb not null default '{}'::jsonb,
  publish_recommendation text not null
    check (publish_recommendation in ('recommend_publish', 'improve_weakest_section', 'rewrite_before_shooting', 'do_not_publish')),
  score_label text not null
    check (score_label in ('strong', 'good', 'rewrite', 'weak', 'blocked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, daily_card_id)
    references public.daily_cards(workspace_id, creator_id, id) on delete cascade,
  unique (workspace_id, creator_id, daily_card_id, quality_version)
);

create table public.post_publish_raw_metrics (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  content_id uuid not null,
  daily_card_id uuid,
  account_id text,
  instagram_media_id text,
  format text not null check (format in ('reel', 'story', 'post', 'carousel')),
  content_pillar text,
  hook_type text,
  cta_type text,
  generated_quality_score numeric(5, 2) check (generated_quality_score between 0 and 100),
  prompt_version text,
  quality_version text,
  published_at timestamptz,
  collected_at timestamptz not null default now(),
  metric_window text not null check (metric_window in ('1h', '6h', '24h', '72h', '7d', '30d')),
  followers_at_publish integer check (followers_at_publish is null or followers_at_publish >= 0),
  followers_at_collection integer check (followers_at_collection is null or followers_at_collection >= 0),
  duration_sec numeric(8, 2) check (duration_sec is null or duration_sec >= 0),
  scene_count integer check (scene_count is null or scene_count >= 0),
  has_voiceover boolean,
  has_face boolean,
  has_captions boolean,
  audio_type text not null default 'unknown'
    check (audio_type in ('original', 'trending', 'licensed', 'silent', 'voiceover', 'unknown')),
  audio_id text,
  primary_metric_goal text not null
    check (primary_metric_goal in ('reach', 'saves', 'sends', 'shares', 'follows', 'comments', 'link_taps', 'trust', 'brand_collab', 'community')),
  secondary_metric_goal text
    check (secondary_metric_goal is null or secondary_metric_goal in ('reach', 'saves', 'sends', 'shares', 'follows', 'comments', 'link_taps', 'trust', 'brand_collab', 'community')),
  paid_or_boosted boolean not null default false,
  metric_source text not null check (metric_source in ('api', 'manual', 'screenshot', 'mixed')),
  data_quality text not null check (data_quality in ('complete', 'partial', 'estimated')),
  views integer check (views is null or views >= 0),
  reach integer check (reach is null or reach >= 0),
  follower_reach integer check (follower_reach is null or follower_reach >= 0),
  non_follower_reach integer check (non_follower_reach is null or non_follower_reach >= 0),
  replays integer check (replays is null or replays >= 0),
  impressions integer check (impressions is null or impressions >= 0),
  likes integer check (likes is null or likes >= 0),
  comments integer check (comments is null or comments >= 0),
  saves integer check (saves is null or saves >= 0),
  shares integer check (shares is null or shares >= 0),
  sends integer check (sends is null or sends >= 0),
  total_interactions integer check (total_interactions is null or total_interactions >= 0),
  follows integer check (follows is null or follows >= 0),
  profile_visits integer check (profile_visits is null or profile_visits >= 0),
  profile_link_taps integer check (profile_link_taps is null or profile_link_taps >= 0),
  website_taps integer check (website_taps is null or website_taps >= 0),
  reel_watch_time numeric(12, 2) check (reel_watch_time is null or reel_watch_time >= 0),
  reel_average_watch_time numeric(8, 2) check (reel_average_watch_time is null or reel_average_watch_time >= 0),
  reel_skip_rate numeric(8, 6) check (reel_skip_rate is null or reel_skip_rate between 0 and 1),
  story_reach integer check (story_reach is null or story_reach >= 0),
  story_replies integer check (story_replies is null or story_replies >= 0),
  story_exits integer check (story_exits is null or story_exits >= 0),
  story_taps_forward integer check (story_taps_forward is null or story_taps_forward >= 0),
  story_taps_back integer check (story_taps_back is null or story_taps_back >= 0),
  story_sticker_taps integer check (story_sticker_taps is null or story_sticker_taps >= 0),
  story_completion_rate numeric(8, 6) check (story_completion_rate is null or story_completion_rate between 0 and 1),
  first_frame_reach integer check (first_frame_reach is null or first_frame_reach >= 0),
  final_frame_reach integer check (final_frame_reach is null or final_frame_reach >= 0),
  comment_quality_score numeric(3, 2) check (comment_quality_score is null or comment_quality_score between 1 and 5),
  meaningful_comment_count integer check (meaningful_comment_count is null or meaningful_comment_count >= 0),
  question_comment_count integer check (question_comment_count is null or question_comment_count >= 0),
  target_audience_comment_count integer check (target_audience_comment_count is null or target_audience_comment_count >= 0),
  negative_comment_count integer check (negative_comment_count is null or negative_comment_count >= 0),
  comment_sentiment text not null default 'unknown'
    check (comment_sentiment in ('positive', 'mixed', 'negative', 'unknown')),
  audience_fit_score numeric(3, 2) check (audience_fit_score is null or audience_fit_score between 1 and 5),
  brand_fit_score numeric(3, 2) check (brand_fit_score is null or brand_fit_score between 1 and 5),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  foreign key (daily_card_id)
    references public.daily_cards(id) on delete set null
);

create table public.post_publish_derived_metrics (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  raw_metrics_id uuid not null references public.post_publish_raw_metrics(id) on delete cascade,
  derived_version text not null,
  weighted_engagement_weights_version text not null,
  metric_source text not null check (metric_source in ('api', 'manual', 'screenshot', 'mixed')),
  data_quality text not null check (data_quality in ('complete', 'partial', 'estimated')),
  paid_or_boosted boolean not null default false,
  distribution jsonb not null default '{}'::jsonb,
  retention jsonb not null default '{}'::jsonb,
  engagement jsonb not null default '{}'::jsonb,
  durable_value jsonb not null default '{}'::jsonb,
  social_spread jsonb not null default '{}'::jsonb,
  conversion jsonb not null default '{}'::jsonb,
  stories jsonb not null default '{}'::jsonb,
  quality jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (raw_metrics_id, derived_version)
);

create table public.post_publish_performance_scores (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  raw_metrics_id uuid not null references public.post_publish_raw_metrics(id) on delete cascade,
  derived_metrics_id uuid references public.post_publish_derived_metrics(id) on delete set null,
  primary_metric_goal text not null
    check (primary_metric_goal in ('reach', 'saves', 'sends', 'shares', 'follows', 'comments', 'link_taps', 'trust', 'brand_collab', 'community')),
  secondary_metric_goal text
    check (secondary_metric_goal is null or secondary_metric_goal in ('reach', 'saves', 'sends', 'shares', 'follows', 'comments', 'link_taps', 'trust', 'brand_collab', 'community')),
  weights_version text not null,
  performance_score numeric(5, 2) check (performance_score is null or performance_score between 0 and 100),
  goal_fit_result text not null
    check (goal_fit_result in ('strong', 'aligned', 'mixed', 'weak', 'insufficient_data')),
  strongest_signals jsonb not null default '[]'::jsonb,
  weakest_signals jsonb not null default '[]'::jsonb,
  diagnosis text,
  recommended_next_action text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (raw_metrics_id, primary_metric_goal, weights_version)
);

create table public.creator_metric_baselines (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  baseline_version text not null,
  baseline_scope text not null,
  format text check (format is null or format in ('reel', 'story', 'post', 'carousel')),
  content_pillar text,
  hook_type text,
  duration_band text,
  sample_count integer not null check (sample_count >= 0),
  confidence text not null check (confidence in ('none', 'insufficient', 'partial', 'reliable')),
  includes_paid boolean not null default false,
  median_metrics jsonb not null default '{}'::jsonb,
  top_25_percent_metrics jsonb not null default '{}'::jsonb,
  top_10_percent_metrics jsonb not null default '{}'::jsonb,
  computed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade
);

create table public.learning_loop_diagnoses (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  raw_metrics_id uuid references public.post_publish_raw_metrics(id) on delete cascade,
  performance_score_id uuid references public.post_publish_performance_scores(id) on delete set null,
  baseline_id uuid references public.creator_metric_baselines(id) on delete set null,
  classification_version text not null,
  outcome_category text not null
    check (outcome_category in ('high_reach_high_quality', 'high_reach_low_quality', 'low_reach_high_quality', 'low_reach_low_quality')),
  meaning text not null,
  next_action text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade
);

create table public.story_sequences (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  content_id uuid not null,
  daily_card_id uuid,
  raw_metrics_id uuid references public.post_publish_raw_metrics(id) on delete set null,
  sequence_date date,
  sequence_goal text,
  completion_rate numeric(8, 6) check (completion_rate is null or completion_rate between 0 and 1),
  metric_source text not null check (metric_source in ('api', 'manual', 'screenshot', 'mixed')),
  data_quality text not null check (data_quality in ('complete', 'partial', 'estimated')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  foreign key (daily_card_id)
    references public.daily_cards(id) on delete set null
);

create table public.story_frame_metrics (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  story_sequence_id uuid not null references public.story_sequences(id) on delete cascade,
  story_frame_id uuid not null default gen_random_uuid(),
  frame_index integer not null check (frame_index >= 0),
  frame_type text not null default 'unknown'
    check (frame_type in ('photo', 'video', 'poll', 'question', 'link', 'repost', 'unknown')),
  frame_goal text not null default 'unknown'
    check (frame_goal in ('reply', 'tap', 'continue', 'link', 'trust', 'unknown')),
  reach integer check (reach is null or reach >= 0),
  exits integer check (exits is null or exits >= 0),
  taps_forward integer check (taps_forward is null or taps_forward >= 0),
  taps_back integer check (taps_back is null or taps_back >= 0),
  replies integer check (replies is null or replies >= 0),
  sticker_taps integer check (sticker_taps is null or sticker_taps >= 0),
  link_taps integer check (link_taps is null or link_taps >= 0),
  derived_metrics jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (story_sequence_id, frame_index)
);

create table public.trend_sources (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  source_type text not null
    check (source_type in ('instagram_reel_link', 'competitor_post', 'trending_audio_note', 'screenshot', 'caption', 'brand_brief', 'content_note')),
  source_url text,
  observed_pattern text,
  why_it_worked text,
  creator_fit_score numeric(5, 2) check (creator_fit_score is null or creator_fit_score between 0 and 100),
  audience_fit_score numeric(5, 2) check (audience_fit_score is null or audience_fit_score between 0 and 100),
  adaptation_risk text,
  suggested_creator_angle text,
  ignore_reason text,
  label text not null
    check (label in ('use_now', 'adapt_carefully', 'ignore', 'save_for_later')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade
);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'content_quality_scores',
    'post_publish_raw_metrics',
    'post_publish_derived_metrics',
    'post_publish_performance_scores',
    'creator_metric_baselines',
    'learning_loop_diagnoses',
    'story_sequences',
    'story_frame_metrics',
    'trend_sources'
  ]
  loop
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      table_name || '_set_updated_at',
      table_name
    );
    execute format('alter table public.%I enable row level security', table_name);
    execute format('alter table public.%I force row level security', table_name);
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select public.is_workspace_member(workspace_id)))',
      table_name || '_select_for_workspace',
      table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((select public.member_has_workspace_role(workspace_id, array[''owner'', ''editor''])))',
      table_name || '_insert_for_admins',
      table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using ((select public.member_has_workspace_role(workspace_id, array[''owner'', ''editor'']))) with check ((select public.member_has_workspace_role(workspace_id, array[''owner'', ''editor''])))',
      table_name || '_update_for_admins',
      table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using ((select public.member_has_workspace_role(workspace_id, array[''owner''])))',
      table_name || '_delete_for_owners',
      table_name
    );
  end loop;
end $$;

create index content_quality_scores_card_idx
  on public.content_quality_scores(workspace_id, creator_id, daily_card_id, quality_version);
create index post_publish_raw_metrics_creator_window_idx
  on public.post_publish_raw_metrics(creator_id, metric_window, collected_at desc);
create index post_publish_raw_metrics_card_idx
  on public.post_publish_raw_metrics(workspace_id, creator_id, daily_card_id);
create index post_publish_raw_metrics_organic_idx
  on public.post_publish_raw_metrics(creator_id, format, collected_at desc)
  where paid_or_boosted = false;
create index post_publish_derived_metrics_raw_idx
  on public.post_publish_derived_metrics(raw_metrics_id, derived_version);
create index post_publish_performance_scores_goal_idx
  on public.post_publish_performance_scores(creator_id, primary_metric_goal, created_at desc);
create index creator_metric_baselines_lookup_idx
  on public.creator_metric_baselines(creator_id, baseline_scope, format, content_pillar, hook_type, duration_band, computed_at desc);
create index learning_loop_diagnoses_creator_idx
  on public.learning_loop_diagnoses(creator_id, outcome_category, created_at desc);
create index story_sequences_card_idx
  on public.story_sequences(workspace_id, creator_id, daily_card_id);
create index story_frame_metrics_sequence_idx
  on public.story_frame_metrics(story_sequence_id, frame_index);
create index trend_sources_creator_label_idx
  on public.trend_sources(creator_id, label, created_at desc);

grant select, insert, update, delete on
  public.content_quality_scores,
  public.post_publish_raw_metrics,
  public.post_publish_derived_metrics,
  public.post_publish_performance_scores,
  public.creator_metric_baselines,
  public.learning_loop_diagnoses,
  public.story_sequences,
  public.story_frame_metrics,
  public.trend_sources
to authenticated;

grant all privileges on
  public.content_quality_scores,
  public.post_publish_raw_metrics,
  public.post_publish_derived_metrics,
  public.post_publish_performance_scores,
  public.creator_metric_baselines,
  public.learning_loop_diagnoses,
  public.story_sequences,
  public.story_frame_metrics,
  public.trend_sources
to service_role;

comment on table public.content_quality_scores is
  'Versioned pre-publish quality scores and hard gate results. Safety/brand/platform gates are not weighted score categories.';
comment on table public.post_publish_raw_metrics is
  'Nullable raw post-publish metrics from API, manual entry, screenshots, or mixed sources. Unknown stays null.';
comment on table public.post_publish_derived_metrics is
  'Versioned grouped analytics output derived from raw metrics with zero/null safe formulas.';
comment on table public.creator_metric_baselines is
  'Creator-specific baseline snapshots with insufficient, partial, or reliable confidence.';
