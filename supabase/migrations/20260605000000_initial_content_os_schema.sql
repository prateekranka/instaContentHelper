-- Creator Content OS V2 initial Supabase schema.
-- The app UI exposes only Creator in V1, but every product table is scoped by
-- workspace_id and creator_id so more creators/workspaces can be added later.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.creators (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  display_name text not null,
  handle text,
  default_timezone text not null default 'Asia/Kolkata',
  status text not null default 'active'
    check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, id)
);

create table public.members (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  auth_user_id uuid references auth.users(id) on delete set null,
  display_name text not null,
  role text not null
    check (role in ('owner', 'editor', 'creator', 'scout')),
  status text not null default 'active'
    check (status in ('active', 'revoked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, id)
);

create table public.device_invites (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  created_by_member_id uuid references public.members(id) on delete set null,
  code_hash text not null unique,
  role_granted text not null
    check (role_granted in ('owner', 'editor', 'creator', 'scout')),
  expires_at timestamptz not null,
  use_limit integer not null default 1 check (use_limit > 0),
  used_count integer not null default 0 check (used_count >= 0),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (used_count <= use_limit)
);

create table public.device_installations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  device_name text,
  platform text not null default 'ios' check (platform in ('ios')),
  token_hash text not null unique,
  paired_at timestamptz not null default now(),
  last_seen_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.creator_profiles (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  status text not null default 'draft'
    check (status in ('draft', 'active', 'superseded')),
  version integer not null default 1 check (version > 0),
  positioning text,
  voice_rules jsonb not null default '[]'::jsonb,
  content_pillars jsonb not null default '[]'::jsonb,
  preferred_hooks jsonb not null default '[]'::jsonb,
  caption_style text,
  never_say jsonb not null default '[]'::jsonb,
  weekly_routine jsonb not null default '{}'::jsonb,
  family_race_travel_context jsonb not null default '{}'::jsonb,
  brand_tone text,
  language_preferences jsonb not null default '{}'::jsonb,
  recurring_formats jsonb not null default '[]'::jsonb,
  trend_filter_rules jsonb not null default '{}'::jsonb,
  influencer_adaptation_rules jsonb not null default '{}'::jsonb,
  created_by_member_id uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (workspace_id, creator_id, id)
);

create table public.brand_briefs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  brand_name text not null,
  campaign_title text,
  deliverable text,
  due_date date,
  post_date date,
  review_deadline date,
  mandatory_points jsonb not null default '[]'::jsonb,
  must_avoid jsonb not null default '[]'::jsonb,
  required_tags text[] not null default '{}',
  disclosure_requirement text,
  tone text,
  approval_status text,
  usage_rights_notes text,
  payment_status text,
  notes text,
  status text not null default 'draft'
    check (status in ('draft', 'active', 'scheduled', 'awaiting_approval', 'approved', 'completed', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (workspace_id, creator_id, id)
);

create table public.collab_leads (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  brand_name text not null,
  category text,
  fit_notes text,
  contact_status_notes text,
  reference_links jsonb not null default '[]'::jsonb,
  status text not null default 'saved'
    check (status in ('saved', 'contacted', 'converted', 'dismissed', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade
);

create table public.key_moments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  name text not null,
  moment_date date not null,
  location text,
  kind text,
  content_angle text,
  required_scenes jsonb not null default '[]'::jsonb,
  pre_event_notes text,
  post_event_notes text,
  status text not null default 'upcoming'
    check (status in ('upcoming', 'active', 'completed', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (workspace_id, creator_id, id)
);

create table public.watchlists (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  name text not null,
  kind text,
  source_description text,
  provenance_notes text,
  last_reviewed_at timestamptz,
  status text not null default 'active'
    check (status in ('active', 'needs_review', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (workspace_id, creator_id, id)
);

create table public.benchmark_creators (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  handle text,
  display_name text,
  platform text,
  region text,
  niche_tags text[] not null default '{}',
  audience_tags text[] not null default '{}',
  relevance_notes text,
  priority_score integer check (priority_score between 0 and 100),
  creator_relevance_score numeric(5, 2) check (creator_relevance_score between 0 and 100),
  status text not null default 'candidate'
    check (status in ('candidate', 'active', 'poor_fit', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (workspace_id, creator_id, id)
);

create table public.watchlist_benchmark_creators (
  workspace_id uuid not null,
  creator_id uuid not null,
  watchlist_id uuid not null,
  benchmark_creator_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (watchlist_id, benchmark_creator_id),
  foreign key (workspace_id, creator_id, watchlist_id)
    references public.watchlists(workspace_id, creator_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, benchmark_creator_id)
    references public.benchmark_creators(workspace_id, creator_id, id) on delete cascade
);

create table public.source_references (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  benchmark_creator_id uuid,
  watchlist_id uuid,
  source_type text not null
    check (source_type in ('reel_link', 'audio_link', 'screenshot', 'screen_recording', 'manual_note', 'benchmark_post', 'import_row')),
  source_url text,
  storage_path text,
  manual_notes text,
  provenance jsonb not null default '{}'::jsonb,
  added_by_member_id uuid references public.members(id) on delete set null,
  analysis_confidence numeric(5, 2) check (analysis_confidence between 0 and 100),
  status text not null default 'added'
    check (status in ('added', 'analyzing', 'analyzed', 'confirmed', 'dismissed', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  foreign key (benchmark_creator_id)
    references public.benchmark_creators(id) on delete set null,
  foreign key (watchlist_id)
    references public.watchlists(id) on delete set null,
  unique (workspace_id, creator_id, id)
);

create table public.reference_extractions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  source_reference_id uuid not null,
  extraction_kind text not null
    check (extraction_kind in ('pattern', 'trend', 'audio_option', 'idea', 'brand_signal')),
  extracted_payload jsonb not null default '{}'::jsonb,
  confidence numeric(5, 2) check (confidence between 0 and 100),
  status text not null default 'candidate'
    check (status in ('candidate', 'confirmed', 'rejected')),
  reviewed_by_member_id uuid references public.members(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id, source_reference_id)
    references public.source_references(workspace_id, creator_id, id) on delete cascade
);

create table public.patterns (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  title text not null,
  pattern_type text,
  summary text,
  fit_notes text,
  avoid_notes text,
  creator_adaptation text,
  complexity_score integer check (complexity_score between 0 and 100),
  creator_fit_score numeric(5, 2) check (creator_fit_score between 0 and 100),
  status text not null default 'candidate'
    check (status in ('candidate', 'approved', 'rejected', 'used', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (workspace_id, creator_id, id)
);

create table public.pattern_references (
  workspace_id uuid not null,
  creator_id uuid not null,
  pattern_id uuid not null,
  source_reference_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (pattern_id, source_reference_id),
  foreign key (workspace_id, creator_id, pattern_id)
    references public.patterns(workspace_id, creator_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, source_reference_id)
    references public.source_references(workspace_id, creator_id, id) on delete cascade
);

create table public.trends (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  title text not null,
  summary text,
  first_seen_on date,
  last_seen_on date,
  region text,
  niche text,
  hook_pattern text,
  visual_pattern text,
  caption_pattern text,
  saturation_note text,
  timing_recommendation text,
  creator_adaptation text,
  creator_fit_score numeric(5, 2) check (creator_fit_score between 0 and 100),
  status text not null default 'candidate'
    check (status in ('candidate', 'approved', 'rejected', 'used', 'stale', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (workspace_id, creator_id, id),
  check (last_seen_on is null or first_seen_on is null or last_seen_on >= first_seen_on)
);

create table public.trend_references (
  workspace_id uuid not null,
  creator_id uuid not null,
  trend_id uuid not null,
  source_reference_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (trend_id, source_reference_id),
  foreign key (workspace_id, creator_id, trend_id)
    references public.trends(workspace_id, creator_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, source_reference_id)
    references public.source_references(workspace_id, creator_id, id) on delete cascade
);

create table public.audio_options (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  title text not null,
  artist_or_creator text,
  audio_url text,
  source_reel_url text,
  region_seen text,
  usage_notes text,
  availability_confidence text not null default 'unknown'
    check (availability_confidence in ('unknown', 'low', 'medium', 'high', 'verified')),
  verification_note text,
  fallback_audio_option_id uuid references public.audio_options(id) on delete set null,
  status text not null default 'candidate'
    check (status in ('candidate', 'verified_available', 'unavailable', 'used', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (workspace_id, creator_id, id)
);

create table public.trend_audio_options (
  workspace_id uuid not null,
  creator_id uuid not null,
  trend_id uuid not null,
  audio_option_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (trend_id, audio_option_id),
  foreign key (workspace_id, creator_id, trend_id)
    references public.trends(workspace_id, creator_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, audio_option_id)
    references public.audio_options(workspace_id, creator_id, id) on delete cascade
);

create table public.learning_summaries (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  period_start date not null,
  period_end date not null,
  status text not null default 'draft'
    check (status in ('draft', 'approved', 'superseded')),
  worked_well jsonb not null default '[]'::jsonb,
  did_not_work jsonb not null default '[]'::jsonb,
  voice_learnings jsonb not null default '[]'::jsonb,
  shootability_learnings jsonb not null default '[]'::jsonb,
  brand_learnings jsonb not null default '[]'::jsonb,
  trend_learnings jsonb not null default '[]'::jsonb,
  next_week_recommendations jsonb not null default '[]'::jsonb,
  generated_from jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (workspace_id, creator_id, id),
  check (period_end >= period_start)
);

create table public.ideas (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  title text not null,
  summary text,
  tags text[] not null default '{}',
  suggested_use text,
  shootability text,
  fit_score numeric(5, 2) check (fit_score between 0 and 100),
  notes text,
  source_reference_id uuid,
  source_pattern_id uuid,
  source_trend_id uuid,
  source_audio_option_id uuid,
  source_brand_brief_id uuid,
  source_key_moment_id uuid,
  source_learning_summary_id uuid,
  status text not null default 'saved'
    check (status in ('saved', 'scheduled', 'used', 'dismissed', 'archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  foreign key (source_reference_id)
    references public.source_references(id) on delete set null,
  foreign key (source_pattern_id)
    references public.patterns(id) on delete set null,
  foreign key (source_trend_id)
    references public.trends(id) on delete set null,
  foreign key (source_audio_option_id)
    references public.audio_options(id) on delete set null,
  foreign key (source_brand_brief_id)
    references public.brand_briefs(id) on delete set null,
  foreign key (source_key_moment_id)
    references public.key_moments(id) on delete set null,
  foreign key (source_learning_summary_id)
    references public.learning_summaries(id) on delete set null,
  unique (workspace_id, creator_id, id)
);

create table public.weekly_setups (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  creator_profile_id uuid references public.creator_profiles(id) on delete set null,
  week_start_date date not null,
  status text not null default 'empty'
    check (status in ('empty', 'in_progress', 'ready_to_generate', 'used', 'archived')),
  location text,
  workout_race_schedule jsonb not null default '[]'::jsonb,
  family_travel_moments jsonb not null default '[]'::jsonb,
  energy_constraints jsonb not null default '[]'::jsonb,
  shooting_constraints jsonb not null default '[]'::jsonb,
  no_go_topics jsonb not null default '[]'::jsonb,
  selected_sources jsonb not null default '[]'::jsonb,
  notes text,
  created_by_member_id uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  unique (workspace_id, creator_id, id),
  unique (creator_id, week_start_date)
);

create table public.weekly_setup_sources (
  workspace_id uuid not null,
  creator_id uuid not null,
  weekly_setup_id uuid not null,
  source_kind text not null
    check (source_kind in ('reference', 'pattern', 'trend', 'audio_option', 'idea', 'brand_brief', 'key_moment')),
  source_id uuid not null,
  note text,
  created_at timestamptz not null default now(),
  primary key (weekly_setup_id, source_kind, source_id),
  foreign key (workspace_id, creator_id, weekly_setup_id)
    references public.weekly_setups(workspace_id, creator_id, id) on delete cascade
);

create table public.weekly_plans (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  weekly_setup_id uuid,
  creator_profile_id uuid references public.creator_profiles(id) on delete set null,
  week_start_date date not null,
  status text not null default 'draft'
    check (status in ('draft', 'reviewed', 'published', 'archived', 'replaced')),
  strategy_summary text,
  warnings jsonb not null default '[]'::jsonb,
  assumptions jsonb not null default '[]'::jsonb,
  is_soft_locked boolean not null default false,
  published_at timestamptz,
  replaced_by_weekly_plan_id uuid references public.weekly_plans(id) on delete set null,
  created_by_member_id uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  foreign key (weekly_setup_id)
    references public.weekly_setups(id) on delete set null,
  unique (workspace_id, creator_id, id)
);

create table public.daily_cards (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  weekly_plan_id uuid not null,
  origin_idea_id uuid,
  brand_brief_id uuid,
  key_moment_id uuid,
  scheduled_date date not null,
  status text not null default 'draft'
    check (status in ('draft', 'published', 'in_decision', 'shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally', 'archived')),
  title text not null,
  why_today text,
  growth_job text,
  content_pillar text,
  shootability text,
  estimated_shoot_minutes integer check (estimated_shoot_minutes is null or estimated_shoot_minutes >= 0),
  energy_required text,
  language_mode text,
  scene_list jsonb not null default '[]'::jsonb,
  script text,
  no_voiceover_version text,
  on_screen_text jsonb not null default '[]'::jsonb,
  caption text,
  cta text,
  hashtags text[] not null default '{}',
  cover_text text,
  post_instructions jsonb not null default '{}'::jsonb,
  brand_event_notes text,
  backup_story jsonb not null default '{}'::jsonb,
  backup_caption_only jsonb not null default '{}'::jsonb,
  audio_option_id uuid,
  audio_fallback_id uuid,
  creator_fit_score numeric(5, 2) check (creator_fit_score between 0 and 100),
  risk_notes jsonb not null default '[]'::jsonb,
  assumptions jsonb not null default '[]'::jsonb,
  source_note text,
  decision_at timestamptz,
  completed_by_member_id uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id, weekly_plan_id)
    references public.weekly_plans(workspace_id, creator_id, id) on delete cascade,
  foreign key (origin_idea_id)
    references public.ideas(id) on delete set null,
  foreign key (brand_brief_id)
    references public.brand_briefs(id) on delete set null,
  foreign key (key_moment_id)
    references public.key_moments(id) on delete set null,
  foreign key (audio_option_id)
    references public.audio_options(id) on delete set null,
  foreign key (audio_fallback_id)
    references public.audio_options(id) on delete set null,
  unique (weekly_plan_id, scheduled_date),
  unique (workspace_id, creator_id, id)
);

create table public.daily_card_patterns (
  workspace_id uuid not null,
  creator_id uuid not null,
  daily_card_id uuid not null,
  pattern_id uuid not null,
  reason text,
  created_at timestamptz not null default now(),
  primary key (daily_card_id, pattern_id),
  foreign key (workspace_id, creator_id, daily_card_id)
    references public.daily_cards(workspace_id, creator_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, pattern_id)
    references public.patterns(workspace_id, creator_id, id) on delete cascade
);

create table public.daily_card_trends (
  workspace_id uuid not null,
  creator_id uuid not null,
  daily_card_id uuid not null,
  trend_id uuid not null,
  reason text,
  created_at timestamptz not null default now(),
  primary key (daily_card_id, trend_id),
  foreign key (workspace_id, creator_id, daily_card_id)
    references public.daily_cards(workspace_id, creator_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, trend_id)
    references public.trends(workspace_id, creator_id, id) on delete cascade
);

create table public.daily_card_references (
  workspace_id uuid not null,
  creator_id uuid not null,
  daily_card_id uuid not null,
  source_reference_id uuid not null,
  reason text,
  created_at timestamptz not null default now(),
  primary key (daily_card_id, source_reference_id),
  foreign key (workspace_id, creator_id, daily_card_id)
    references public.daily_cards(workspace_id, creator_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, source_reference_id)
    references public.source_references(workspace_id, creator_id, id) on delete cascade
);

create table public.card_alternatives (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  daily_card_id uuid not null,
  reason_requested text not null,
  changed_fields jsonb not null default '[]'::jsonb,
  package jsonb not null default '{}'::jsonb,
  explanation text,
  lost_requirements jsonb not null default '[]'::jsonb,
  created_by_member_id uuid references public.members(id) on delete set null,
  status text not null default 'proposed'
    check (status in ('proposed', 'accepted', 'dismissed', 'expired')),
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id, daily_card_id)
    references public.daily_cards(workspace_id, creator_id, id) on delete cascade
);

create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  member_id uuid references public.members(id) on delete set null,
  daily_card_id uuid,
  pattern_id uuid,
  trend_id uuid,
  idea_id uuid,
  brand_brief_id uuid,
  tags text[] not null default '{}',
  note text,
  included_in_learning_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id)
    references public.creators(workspace_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, daily_card_id)
    references public.daily_cards(workspace_id, creator_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, pattern_id)
    references public.patterns(workspace_id, creator_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, trend_id)
    references public.trends(workspace_id, creator_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, idea_id)
    references public.ideas(workspace_id, creator_id, id) on delete cascade,
  foreign key (workspace_id, creator_id, brand_brief_id)
    references public.brand_briefs(workspace_id, creator_id, id) on delete cascade,
  check (num_nonnulls(daily_card_id, pattern_id, trend_id, idea_id, brand_brief_id) >= 1)
);

create table public.post_results (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  daily_card_id uuid not null,
  final_instagram_url text,
  manual_notes text,
  performance_snapshot jsonb not null default '{}'::jsonb,
  captured_at timestamptz,
  status text not null default 'not_linked'
    check (status in ('linked', 'not_linked', 'updated')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id, daily_card_id)
    references public.daily_cards(workspace_id, creator_id, id) on delete cascade,
  unique (daily_card_id)
);

create table public.archive_entries (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  creator_id uuid not null,
  daily_card_id uuid not null,
  post_result_id uuid references public.post_results(id) on delete set null,
  archive_date date not null,
  decision text not null
    check (decision in ('posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally')),
  output_line text,
  has_post_thumbnail boolean not null default false,
  thumbnail_storage_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (workspace_id, creator_id, daily_card_id)
    references public.daily_cards(workspace_id, creator_id, id) on delete cascade,
  unique (daily_card_id)
);

create table public.sync_events (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  creator_id uuid references public.creators(id) on delete cascade,
  member_id uuid references public.members(id) on delete set null,
  event_type text not null,
  subject_table text not null,
  subject_id uuid,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'workspaces',
    'creators',
    'members',
    'device_invites',
    'device_installations',
    'creator_profiles',
    'brand_briefs',
    'collab_leads',
    'key_moments',
    'watchlists',
    'benchmark_creators',
    'source_references',
    'reference_extractions',
    'patterns',
    'trends',
    'audio_options',
    'learning_summaries',
    'ideas',
    'weekly_setups',
    'weekly_plans',
    'daily_cards',
    'card_alternatives',
    'post_results',
    'archive_entries'
  ]
  loop
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      table_name || '_set_updated_at',
      table_name
    );
  end loop;
end $$;

create index creators_workspace_id_idx on public.creators(workspace_id);
create index members_workspace_auth_idx on public.members(workspace_id, auth_user_id) where status = 'active';
create index members_auth_user_id_idx on public.members(auth_user_id) where status = 'active';
create index device_invites_workspace_id_idx on public.device_invites(workspace_id);
create index device_invites_created_by_member_id_idx on public.device_invites(created_by_member_id);
create index device_installations_workspace_id_idx on public.device_installations(workspace_id);
create index device_installations_member_id_idx on public.device_installations(member_id);
create index creator_profiles_active_idx on public.creator_profiles(creator_id, version desc) where status = 'active';
create unique index creator_profiles_one_active_idx on public.creator_profiles(creator_id) where status = 'active';
create index creator_profiles_created_by_member_id_idx on public.creator_profiles(created_by_member_id);

create index collab_leads_workspace_creator_idx on public.collab_leads(workspace_id, creator_id);
create index brand_briefs_creator_status_idx on public.brand_briefs(creator_id, status, post_date);
create index key_moments_creator_date_idx on public.key_moments(creator_id, moment_date);
create index source_references_creator_status_created_idx on public.source_references(creator_id, status, created_at desc);
create index source_references_added_by_member_id_idx on public.source_references(added_by_member_id);
create index source_references_benchmark_creator_id_idx on public.source_references(benchmark_creator_id);
create index source_references_watchlist_id_idx on public.source_references(watchlist_id);
create index reference_extractions_reference_status_idx on public.reference_extractions(source_reference_id, status);
create index reference_extractions_workspace_creator_reference_idx
  on public.reference_extractions(workspace_id, creator_id, source_reference_id);
create index reference_extractions_reviewed_by_member_id_idx on public.reference_extractions(reviewed_by_member_id);
create index patterns_creator_status_updated_idx on public.patterns(creator_id, status, updated_at desc);
create index trends_creator_status_seen_idx on public.trends(creator_id, status, last_seen_on desc);
create index audio_options_creator_status_updated_idx on public.audio_options(creator_id, status, updated_at desc);
create index audio_options_fallback_audio_option_id_idx on public.audio_options(fallback_audio_option_id);
create index ideas_creator_status_updated_idx on public.ideas(creator_id, status, updated_at desc);
create index ideas_source_reference_id_idx on public.ideas(source_reference_id);
create index ideas_source_pattern_id_idx on public.ideas(source_pattern_id);
create index ideas_source_trend_id_idx on public.ideas(source_trend_id);
create index ideas_source_audio_option_id_idx on public.ideas(source_audio_option_id);
create index ideas_source_brand_brief_id_idx on public.ideas(source_brand_brief_id);
create index ideas_source_key_moment_id_idx on public.ideas(source_key_moment_id);
create index ideas_source_learning_summary_id_idx on public.ideas(source_learning_summary_id);

create index weekly_setups_creator_week_idx on public.weekly_setups(creator_id, week_start_date desc);
create index weekly_setups_creator_profile_id_idx on public.weekly_setups(creator_profile_id);
create index weekly_setups_created_by_member_id_idx on public.weekly_setups(created_by_member_id);
create index weekly_plans_creator_week_status_idx on public.weekly_plans(creator_id, week_start_date desc, status);
create index weekly_plans_weekly_setup_id_idx on public.weekly_plans(weekly_setup_id);
create index weekly_plans_creator_profile_id_idx on public.weekly_plans(creator_profile_id);
create index weekly_plans_replaced_by_weekly_plan_id_idx on public.weekly_plans(replaced_by_weekly_plan_id);
create index weekly_plans_created_by_member_id_idx on public.weekly_plans(created_by_member_id);
create unique index weekly_plans_one_published_week_idx
  on public.weekly_plans(creator_id, week_start_date)
  where status = 'published';
create index daily_cards_today_lookup_idx
  on public.daily_cards(creator_id, scheduled_date)
  where status in ('published', 'in_decision', 'shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally');
create index daily_cards_weekly_plan_idx on public.daily_cards(weekly_plan_id, scheduled_date);
create index daily_cards_origin_idea_id_idx on public.daily_cards(origin_idea_id);
create index daily_cards_brand_brief_id_idx on public.daily_cards(brand_brief_id);
create index daily_cards_key_moment_id_idx on public.daily_cards(key_moment_id);
create index daily_cards_audio_option_id_idx on public.daily_cards(audio_option_id);
create index daily_cards_audio_fallback_id_idx on public.daily_cards(audio_fallback_id);
create index daily_cards_completed_by_member_id_idx on public.daily_cards(completed_by_member_id);
create index card_alternatives_daily_card_status_idx on public.card_alternatives(daily_card_id, status, created_at desc);
create index card_alternatives_workspace_creator_card_idx on public.card_alternatives(workspace_id, creator_id, daily_card_id);
create index card_alternatives_created_by_member_id_idx on public.card_alternatives(created_by_member_id);
create index feedback_creator_created_idx on public.feedback(creator_id, created_at desc);
create index feedback_workspace_creator_idx on public.feedback(workspace_id, creator_id);
create index feedback_workspace_creator_card_idx on public.feedback(workspace_id, creator_id, daily_card_id);
create index feedback_workspace_creator_pattern_idx on public.feedback(workspace_id, creator_id, pattern_id);
create index feedback_workspace_creator_trend_idx on public.feedback(workspace_id, creator_id, trend_id);
create index feedback_workspace_creator_idea_idx on public.feedback(workspace_id, creator_id, idea_id);
create index feedback_workspace_creator_brand_idx on public.feedback(workspace_id, creator_id, brand_brief_id);
create index feedback_member_id_idx on public.feedback(member_id);
create index feedback_daily_card_id_idx on public.feedback(daily_card_id);
create index feedback_pattern_id_idx on public.feedback(pattern_id);
create index feedback_trend_id_idx on public.feedback(trend_id);
create index feedback_idea_id_idx on public.feedback(idea_id);
create index feedback_brand_brief_id_idx on public.feedback(brand_brief_id);
create index post_results_workspace_creator_card_idx on public.post_results(workspace_id, creator_id, daily_card_id);
create index archive_entries_creator_date_idx on public.archive_entries(creator_id, archive_date desc);
create index archive_entries_workspace_creator_card_idx on public.archive_entries(workspace_id, creator_id, daily_card_id);
create index archive_entries_post_result_id_idx on public.archive_entries(post_result_id);
create index sync_events_workspace_created_idx on public.sync_events(workspace_id, created_at desc);
create index sync_events_creator_id_idx on public.sync_events(creator_id);
create index sync_events_member_id_idx on public.sync_events(member_id);

create index watchlist_benchmark_creators_watchlist_fk_idx
  on public.watchlist_benchmark_creators(workspace_id, creator_id, watchlist_id);
create index watchlist_benchmark_creators_benchmark_fk_idx
  on public.watchlist_benchmark_creators(workspace_id, creator_id, benchmark_creator_id);
create index pattern_references_pattern_fk_idx
  on public.pattern_references(workspace_id, creator_id, pattern_id);
create index pattern_references_source_fk_idx
  on public.pattern_references(workspace_id, creator_id, source_reference_id);
create index trend_references_trend_fk_idx
  on public.trend_references(workspace_id, creator_id, trend_id);
create index trend_references_source_fk_idx
  on public.trend_references(workspace_id, creator_id, source_reference_id);
create index trend_audio_options_trend_fk_idx
  on public.trend_audio_options(workspace_id, creator_id, trend_id);
create index trend_audio_options_audio_fk_idx
  on public.trend_audio_options(workspace_id, creator_id, audio_option_id);
create index weekly_setup_sources_setup_fk_idx
  on public.weekly_setup_sources(workspace_id, creator_id, weekly_setup_id);
create index daily_card_patterns_card_fk_idx
  on public.daily_card_patterns(workspace_id, creator_id, daily_card_id);
create index daily_card_patterns_pattern_fk_idx
  on public.daily_card_patterns(workspace_id, creator_id, pattern_id);
create index daily_card_trends_card_fk_idx
  on public.daily_card_trends(workspace_id, creator_id, daily_card_id);
create index daily_card_trends_trend_fk_idx
  on public.daily_card_trends(workspace_id, creator_id, trend_id);
create index daily_card_references_card_fk_idx
  on public.daily_card_references(workspace_id, creator_id, daily_card_id);
create index daily_card_references_source_fk_idx
  on public.daily_card_references(workspace_id, creator_id, source_reference_id);

create or replace function public.is_workspace_member(target_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.members m
    where m.workspace_id = target_workspace_id
      and m.auth_user_id = (select auth.uid())
      and m.status = 'active'
  );
$$;

create or replace function public.member_has_workspace_role(target_workspace_id uuid, allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.members m
    where m.workspace_id = target_workspace_id
      and m.auth_user_id = (select auth.uid())
      and m.status = 'active'
      and m.role = any(allowed_roles)
  );
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'workspaces',
    'creators',
    'members',
    'device_invites',
    'device_installations',
    'creator_profiles',
    'brand_briefs',
    'collab_leads',
    'key_moments',
    'watchlists',
    'benchmark_creators',
    'watchlist_benchmark_creators',
    'source_references',
    'reference_extractions',
    'patterns',
    'pattern_references',
    'trends',
    'trend_references',
    'audio_options',
    'trend_audio_options',
    'learning_summaries',
    'ideas',
    'weekly_setups',
    'weekly_setup_sources',
    'weekly_plans',
    'daily_cards',
    'daily_card_patterns',
    'daily_card_trends',
    'daily_card_references',
    'card_alternatives',
    'feedback',
    'post_results',
    'archive_entries',
    'sync_events'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('alter table public.%I force row level security', table_name);
  end loop;
end $$;

create policy workspaces_select_for_members
  on public.workspaces
  for select
  to authenticated
  using ((select public.is_workspace_member(id)));

create policy workspaces_update_for_owners
  on public.workspaces
  for update
  to authenticated
  using ((select public.member_has_workspace_role(id, array['owner'])))
  with check ((select public.member_has_workspace_role(id, array['owner'])));

create policy members_select_for_workspace_members
  on public.members
  for select
  to authenticated
  using ((select public.is_workspace_member(workspace_id)));

create policy members_update_for_owners
  on public.members
  for update
  to authenticated
  using ((select public.member_has_workspace_role(workspace_id, array['owner'])))
  with check ((select public.member_has_workspace_role(workspace_id, array['owner'])));

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'creators',
    'creator_profiles',
    'brand_briefs',
    'collab_leads',
    'key_moments',
    'watchlists',
    'benchmark_creators',
    'watchlist_benchmark_creators',
    'source_references',
    'reference_extractions',
    'patterns',
    'pattern_references',
    'trends',
    'trend_references',
    'audio_options',
    'trend_audio_options',
    'learning_summaries',
    'ideas',
    'weekly_setups',
    'weekly_setup_sources',
    'weekly_plans',
    'daily_cards',
    'daily_card_patterns',
    'daily_card_trends',
    'daily_card_references',
    'card_alternatives',
    'feedback',
    'post_results',
    'archive_entries',
    'sync_events'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select public.is_workspace_member(workspace_id)))',
      table_name || '_select_for_workspace_members',
      table_name
    );
  end loop;
end $$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'device_invites',
    'device_installations'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select public.member_has_workspace_role(workspace_id, array[''owner'', ''editor''])))',
      table_name || '_select_for_admins',
      table_name
    );
  end loop;
end $$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'creators',
    'creator_profiles',
    'brand_briefs',
    'collab_leads',
    'key_moments',
    'watchlists',
    'benchmark_creators',
    'watchlist_benchmark_creators',
    'reference_extractions',
    'patterns',
    'pattern_references',
    'trends',
    'trend_references',
    'audio_options',
    'trend_audio_options',
    'learning_summaries',
    'ideas',
    'weekly_setups',
    'weekly_setup_sources',
    'weekly_plans',
    'daily_cards',
    'daily_card_patterns',
    'daily_card_trends',
    'daily_card_references',
    'card_alternatives',
    'post_results',
    'sync_events'
  ]
  loop
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
      'create policy %I on public.%I for delete to authenticated using ((select public.member_has_workspace_role(workspace_id, array[''owner'', ''editor''])))',
      table_name || '_delete_for_admins',
      table_name
    );
  end loop;
end $$;

create policy device_invites_insert_for_admins
  on public.device_invites
  for insert
  to authenticated
  with check ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor'])));

create policy device_invites_update_for_admins
  on public.device_invites
  for update
  to authenticated
  using ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor'])))
  with check ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor'])));

create policy device_invites_delete_for_owners
  on public.device_invites
  for delete
  to authenticated
  using ((select public.member_has_workspace_role(workspace_id, array['owner'])));

create policy source_references_insert_for_scouts
  on public.source_references
  for insert
  to authenticated
  with check ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor', 'scout'])));

create policy source_references_update_for_scouts
  on public.source_references
  for update
  to authenticated
  using ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor', 'scout'])))
  with check ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor', 'scout'])));

create policy feedback_insert_for_daily_users
  on public.feedback
  for insert
  to authenticated
  with check ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor', 'creator'])));

create policy feedback_update_for_daily_users
  on public.feedback
  for update
  to authenticated
  using ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor', 'creator'])))
  with check ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor', 'creator'])));

create policy archive_entries_insert_for_daily_users
  on public.archive_entries
  for insert
  to authenticated
  with check ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor', 'creator'])));

create policy archive_entries_update_for_daily_users
  on public.archive_entries
  for update
  to authenticated
  using ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor', 'creator'])))
  with check ((select public.member_has_workspace_role(workspace_id, array['owner', 'editor', 'creator'])));

comment on table public.source_references is
  'Product Reference. Named source_references to avoid using REFERENCES as a table identifier.';
comment on table public.daily_cards is
  'Published Daily Cards are the sync contract for Creator Today and offline cache.';
comment on table public.archive_entries is
  'Clean decision/output history. A completed day means Creator made a decision, not necessarily posted.';

grant usage on schema public to anon, authenticated, service_role;
grant all privileges on all tables in schema public to service_role;
grant all privileges on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;
