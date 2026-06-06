create or replace function public.write_content(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action text := payload->>'action';
  v_workspace_id uuid := (payload->>'workspace_id')::uuid;
  v_creator_id uuid := (payload->>'creator_id')::uuid;
  v_member_id uuid := (payload->>'member_id')::uuid;
  v_daily_card_id uuid;
  v_idea_id uuid;
  v_weekly_plan_id uuid;
  v_decision_status text;
  v_output_line text;
  v_has_post_thumbnail boolean;
  v_archive_date date;
  v_decision_at timestamptz;
  v_daily_card record;
  v_archive_entry record;
  v_idea record;
begin
  if v_action = 'complete_today' then
    begin
      v_daily_card_id := (payload->>'daily_card_id')::uuid;
      v_decision_status := payload #>> '{decision,status}';
      v_decision_at := coalesce(nullif(payload->>'decision_at', '')::timestamptz, now());

      update public.daily_cards
      set
        status = v_decision_status,
        decision_at = v_decision_at,
        completed_by_member_id = v_member_id
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and id = v_daily_card_id
      returning id, status, decision_at, completed_by_member_id
      into v_daily_card;

      if not found then
        return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
      end if;

      return jsonb_build_object(
        'action', v_action,
        'daily_card', jsonb_build_object(
          'id', v_daily_card.id,
          'status', v_daily_card.status,
          'decision_at', v_daily_card.decision_at,
          'completed_by_member_id', v_daily_card.completed_by_member_id
        )
      );
    exception
      when others then
        return jsonb_build_object('error', 'complete_today_failed', 'status', 500);
    end;
  end if;

  if v_action = 'upsert_archive_decision' then
    begin
      v_daily_card_id := (payload->>'daily_card_id')::uuid;
      v_archive_date := (payload->>'archive_date')::date;
      v_decision_status := payload->>'decision';
      v_output_line := payload->>'output_line';
      v_has_post_thumbnail := (payload->>'has_post_thumbnail')::boolean;

      perform 1
      from public.daily_cards
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and id = v_daily_card_id;

      if not found then
        return jsonb_build_object('error', 'daily_card_not_found', 'status', 404);
      end if;

      insert into public.archive_entries (
        workspace_id,
        creator_id,
        daily_card_id,
        archive_date,
        decision,
        output_line,
        has_post_thumbnail
      )
      values (
        v_workspace_id,
        v_creator_id,
        v_daily_card_id,
        v_archive_date,
        v_decision_status,
        v_output_line,
        v_has_post_thumbnail
      )
      on conflict (daily_card_id) do update
      set
        archive_date = excluded.archive_date,
        decision = excluded.decision,
        output_line = excluded.output_line,
        has_post_thumbnail = excluded.has_post_thumbnail
      returning
        id,
        daily_card_id,
        archive_date,
        decision,
        output_line,
        has_post_thumbnail
      into v_archive_entry;

      return jsonb_build_object(
        'action', v_action,
        'archive_entry', jsonb_build_object(
          'id', v_archive_entry.id,
          'daily_card_id', v_archive_entry.daily_card_id,
          'archive_date', v_archive_entry.archive_date,
          'decision', v_archive_entry.decision,
          'output_line', v_archive_entry.output_line,
          'has_post_thumbnail', v_archive_entry.has_post_thumbnail
        )
      );
    exception
      when others then
        return jsonb_build_object('error', 'archive_upsert_failed', 'status', 500);
    end;
  end if;

  if v_action = 'select_idea_for_next_open_day' then
    begin
      v_idea_id := (payload->>'idea_id')::uuid;

      if nullif(payload->>'weekly_plan_id', '') is not null then
        v_weekly_plan_id := (payload->>'weekly_plan_id')::uuid;

        perform 1
        from public.weekly_plans
        where workspace_id = v_workspace_id
          and creator_id = v_creator_id
          and id = v_weekly_plan_id;

        if not found then
          return jsonb_build_object('error', 'select_idea_failed', 'status', 404);
        end if;
      end if;

      select
        id,
        title,
        summary,
        suggested_use,
        shootability
      from public.ideas
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and id = v_idea_id
      into v_idea;

      if not found then
        return jsonb_build_object('error', 'idea_not_found', 'status', 404);
      end if;

      select
        id,
        scheduled_date
      from public.daily_cards
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and (v_weekly_plan_id is null or weekly_plan_id = v_weekly_plan_id)
        and status = 'draft'
      order by scheduled_date asc
      limit 1
      into v_daily_card;

      if not found then
        return jsonb_build_object('error', 'select_idea_failed', 'status', 404);
      end if;

      update public.daily_cards
      set
        origin_idea_id = v_idea.id,
        status = 'published',
        title = v_idea.title,
        why_today = coalesce(v_idea.summary, v_idea.suggested_use, 'Prepared from idea bank.'),
        content_pillar = 'idea',
        shootability = coalesce(nullif(v_idea.shootability, ''), 'easy'),
        estimated_shoot_minutes = case
          when estimated_shoot_minutes is null or estimated_shoot_minutes = 0 then 10
          else estimated_shoot_minutes
        end,
        source_note = 'Selected from idea bank.'
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and id = v_daily_card.id
      returning id, status, decision_at, completed_by_member_id
      into v_daily_card;

      update public.ideas
      set status = 'scheduled'
      where workspace_id = v_workspace_id
        and creator_id = v_creator_id
        and id = v_idea_id
      returning id, status
      into v_idea;

      return jsonb_build_object(
        'action', v_action,
        'daily_card', jsonb_build_object(
          'id', v_daily_card.id,
          'status', v_daily_card.status,
          'decision_at', v_daily_card.decision_at,
          'completed_by_member_id', v_daily_card.completed_by_member_id
        ),
        'idea', jsonb_build_object(
          'id', v_idea.id,
          'status', v_idea.status
        )
      );
    exception
      when others then
        return jsonb_build_object('error', 'select_idea_failed', 'status', 500);
    end;
  end if;

  return jsonb_build_object('error', 'select_idea_failed', 'status', 400);
end;
$$;

grant execute on function public.write_content(jsonb) to service_role;
