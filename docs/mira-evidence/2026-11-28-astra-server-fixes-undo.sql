\ir ../../supabase/migrations/20261128030000_mira_phase_e_jobs.sql

drop function if exists public.mira_cancel(uuid, uuid, uuid, uuid);
drop function if exists public.mira_start_shot_picture(uuid, uuid, uuid);
drop function if exists public.mira_claim_shot_pictures(uuid, uuid, integer, boolean);
