alter table public.archive_entries
  drop constraint archive_entries_decision_check;

alter table public.archive_entries
  add constraint archive_entries_decision_check
  check (decision in ('shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally'));
