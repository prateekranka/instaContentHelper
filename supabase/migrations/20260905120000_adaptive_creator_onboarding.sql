-- Adaptive creator onboarding: additive columns on creator_profiles.
-- Backfill established for legacy profiles with positioning or pillars.

alter table public.creator_profiles
  add column if not exists onboarding_state text not null default 'new'
    check (onboarding_state in ('new', 'partial', 'established')),
  add column if not exists onboarding_step integer,
  add column if not exists onboarding_version integer not null default 1,
  add column if not exists onboarding_completed_at timestamptz,
  add column if not exists starting_point text
    check (starting_point is null or starting_point in ('just_starting', 'already_posting')),
  add column if not exists custom_subjects jsonb not null default '[]'::jsonb,
  add column if not exists taste_example_ids jsonb not null default '[]'::jsonb,
  add column if not exists production_formats jsonb not null default '[]'::jsonb,
  add column if not exists time_to_create text
    check (time_to_create is null or time_to_create in ('five_to_ten', 'ten_to_thirty', 'thirty_plus')),
  add column if not exists on_camera_restrictions jsonb not null default '{}'::jsonb,
  add column if not exists recent_context jsonb not null default '[]'::jsonb,
  add column if not exists creator_note text,
  add column if not exists first_idea_handoff jsonb not null default '{}'::jsonb;

update public.creator_profiles
set onboarding_state = 'established',
    onboarding_completed_at = coalesce(onboarding_completed_at, updated_at)
where status = 'active'
  and onboarding_state = 'new'
  and (
    length(trim(coalesce(positioning, ''))) > 0
    or jsonb_array_length(coalesce(content_pillars, '[]'::jsonb)) > 0
  );
