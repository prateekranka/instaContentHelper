alter function public.touch_weekly_plan_on_daily_card_review_state() set search_path = '';
alter function public.stage_day_job_output(uuid, text, integer, jsonb) set search_path = '';
alter function public.claim_queued_day_job(uuid, text, text, integer, integer) set search_path = '';
alter function public.reclaim_stale_day_job(uuid, text, text, integer, integer, integer) set search_path = '';
alter function public.weekly_generation_runs_set_updated_at() set search_path = '';

revoke execute on function public.touch_weekly_plan_on_daily_card_review_state(),
  public.weekly_generation_runs_set_updated_at() from public, anon, authenticated;
grant execute on function public.touch_weekly_plan_on_daily_card_review_state(),
  public.weekly_generation_runs_set_updated_at() to service_role;

create index creator_days_generation_run_id_idx
  on public.creator_days(generation_run_id);

create index creator_days_current_revision_fk_idx
  on public.creator_days(workspace_id, creator_id, current_revision_id);

create index archive_entries_visible_workspace_date_idx
  on public.archive_entries(workspace_id, creator_id, archive_date desc)
  where decision in ('shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally');
