-- Keep weekly_plans.updated_at in sync when a manager marks a draft card ready/backup/open.
-- read-content picks the working draft by week relevance and updated_at, so stale plans
-- must not win over the plan the manager just edited.

create or replace function public.touch_weekly_plan_on_daily_card_review_state()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE'
     and old.review_state is distinct from new.review_state then
    update public.weekly_plans
       set updated_at = now()
     where id = new.weekly_plan_id
       and workspace_id = new.workspace_id
       and creator_id = new.creator_id;
  end if;

  return new;
end;
$$;

drop trigger if exists daily_cards_touch_weekly_plan_on_review_state
  on public.daily_cards;

create trigger daily_cards_touch_weekly_plan_on_review_state
  after update of review_state on public.daily_cards
  for each row
  execute function public.touch_weekly_plan_on_daily_card_review_state();
