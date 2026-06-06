-- Reference Watchlist Import slice.
-- Adds canonical keys for import de-duping and a transactional confirm RPC.

alter table public.benchmark_creators
  add column if not exists normalized_handle text;

alter table public.source_references
  add column if not exists canonical_source_key text;

update public.benchmark_creators
set normalized_handle = lower(regexp_replace(regexp_replace(trim(handle), '^@', ''), '/+$', ''))
where normalized_handle is null
  and handle is not null
  and trim(handle) <> '';

alter table public.source_references
  drop constraint if exists source_references_status_check;

alter table public.source_references
  add constraint source_references_status_check
  check (status in ('added', 'needs_review', 'analyzing', 'analyzed', 'confirmed', 'dismissed', 'archived'));

create unique index if not exists benchmark_creators_unique_normalized_handle_idx
  on public.benchmark_creators(workspace_id, creator_id, lower(coalesce(platform, '')), normalized_handle)
  where normalized_handle is not null and normalized_handle <> '';

create unique index if not exists source_references_unique_canonical_source_idx
  on public.source_references(workspace_id, creator_id, source_type, canonical_source_key)
  where canonical_source_key is not null and canonical_source_key <> '';

create unique index if not exists watchlists_unique_active_name_idx
  on public.watchlists(workspace_id, creator_id, lower(name))
  where status = 'active';

create index if not exists benchmark_creators_review_queue_idx
  on public.benchmark_creators(workspace_id, creator_id, status, updated_at desc);

create index if not exists source_references_review_queue_idx
  on public.source_references(workspace_id, creator_id, status, updated_at desc);

create or replace function public.confirm_reference_import(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_workspace_id uuid := (payload->>'workspace_id')::uuid;
  requested_creator_id uuid := (payload->>'creator_id')::uuid;
  requested_member_id uuid := nullif(payload->>'member_id', '')::uuid;
  parser_version text := coalesce(payload->>'parser_version', 'reference-import-v1');
  import_source text := coalesce(payload->>'input_type', 'paste');
  filename text := nullif(payload->>'filename', '');
  preview_checksum text := nullif(payload->>'preview_checksum', '');
  row_item jsonb;
  watchlist_uuid uuid;
  creator_exists boolean;
  existing_benchmark_uuid uuid;
  existing_source_uuid uuid;
  imported_count integer := 0;
  needs_review_count integer := 0;
  duplicate_count integer := 0;
  invalid_count integer := 0;
  inserted_ids jsonb := '[]'::jsonb;
  row_state text;
  row_classification text;
  row_source_type text;
  row_status text;
  row_handle text;
  row_normalized_handle text;
  row_title text;
  row_url text;
  row_notes text;
  row_key text;
  row_provenance jsonb;
  inferred_account jsonb;
  inferred_handle text;
  inferred_normalized_handle text;
  inferred_benchmark_uuid uuid;
begin
  if requested_workspace_id is null or requested_creator_id is null then
    raise exception 'invalid_reference_import_payload';
  end if;

  if jsonb_typeof(payload->'rows') <> 'array' then
    raise exception 'invalid_reference_import_rows';
  end if;

  select exists (
    select 1
    from public.creators c
    where c.id = requested_creator_id
      and c.workspace_id = requested_workspace_id
      and c.status = 'active'
  ) into creator_exists;

  if not creator_exists then
    raise exception 'creator_not_found';
  end if;

  select id
  into watchlist_uuid
  from public.watchlists
  where workspace_id = requested_workspace_id
    and creator_id = requested_creator_id
    and lower(name) = 'inspiration'
    and status = 'active'
  order by created_at asc
  limit 1;

  if watchlist_uuid is null then
    insert into public.watchlists (
      workspace_id,
      creator_id,
      name,
      kind,
      source_description,
      provenance_notes,
      status
    )
    values (
      requested_workspace_id,
      requested_creator_id,
      'Inspiration',
      'reference_watchlist',
      'Manual import destination for inspiration accounts and links.',
      'Created by Reference Import.',
      'active'
    )
    returning id into watchlist_uuid;
  end if;

  for row_item in
    select value from jsonb_array_elements(payload->'rows')
  loop
    row_state := coalesce(row_item->>'preview_state', 'clean');
    row_classification := coalesce(row_item->>'classification', 'unknown');
    row_source_type := nullif(row_item->>'source_type', '');
    row_status := coalesce(row_item->>'status_on_confirm', 'needs_review');
    row_handle := nullif(row_item->>'handle', '');
    row_normalized_handle := nullif(row_item->>'normalized_handle', '');
    row_title := nullif(row_item->>'title', '');
    row_url := nullif(row_item->>'url', '');
    row_notes := nullif(row_item->>'notes', '');
    row_key := nullif(row_item->>'canonical_source_key', '');
    inferred_account := row_item->'inferred_account';
    row_provenance := coalesce(row_item->'provenance', '{}'::jsonb)
      || jsonb_build_object(
        'imported_at', now(),
        'import_source', import_source,
        'filename', filename,
        'parser_version', parser_version,
        'preview_checksum', preview_checksum
      );

    if row_state = 'duplicate' then
      duplicate_count := duplicate_count + 1;
      continue;
    elsif row_state = 'invalid' then
      invalid_count := invalid_count + 1;
      continue;
    elsif row_classification = 'account' and row_normalized_handle is not null then
      select id
      into existing_benchmark_uuid
      from public.benchmark_creators
      where workspace_id = requested_workspace_id
        and creator_id = requested_creator_id
        and lower(coalesce(platform, '')) = 'instagram'
        and normalized_handle = row_normalized_handle
      limit 1;

      if existing_benchmark_uuid is null then
        insert into public.benchmark_creators (
          workspace_id,
          creator_id,
          handle,
          normalized_handle,
          display_name,
          platform,
          region,
          niche_tags,
          audience_tags,
          relevance_notes,
          priority_score,
          mamta_relevance_score,
          status
        )
        values (
          requested_workspace_id,
          requested_creator_id,
          coalesce(row_handle, '@' || row_normalized_handle),
          row_normalized_handle,
          row_title,
          'instagram',
          nullif(row_item->>'region', ''),
          coalesce(
            array(select jsonb_array_elements_text(row_item->'tags')),
            '{}'
          ),
          '{}',
          row_notes,
          50,
          null,
          'active'
        )
        returning id into existing_benchmark_uuid;

        imported_count := imported_count + 1;
      else
        duplicate_count := duplicate_count + 1;
      end if;

      insert into public.watchlist_benchmark_creators (
        workspace_id,
        creator_id,
        watchlist_id,
        benchmark_creator_id
      )
      values (
        requested_workspace_id,
        requested_creator_id,
        watchlist_uuid,
        existing_benchmark_uuid
      )
      on conflict do nothing;

      inserted_ids := inserted_ids || jsonb_build_object(
        'kind', 'benchmark_creator',
        'id', existing_benchmark_uuid
      );
    elsif row_classification in ('reel', 'audio', 'unknown') then
      if row_source_type is null then
        row_source_type := case row_classification
          when 'audio' then 'audio_link'
          when 'reel' then 'reel_link'
          else 'import_row'
        end;
      end if;

      if row_key is not null then
        select id
        into existing_source_uuid
        from public.source_references
        where workspace_id = requested_workspace_id
          and creator_id = requested_creator_id
          and source_type = row_source_type
          and canonical_source_key = row_key
        limit 1;
      else
        existing_source_uuid := null;
      end if;

      if existing_source_uuid is null then
        insert into public.source_references (
          workspace_id,
          creator_id,
          watchlist_id,
          source_type,
          source_url,
          manual_notes,
          provenance,
          added_by_member_id,
          status,
          canonical_source_key
        )
        values (
          requested_workspace_id,
          requested_creator_id,
          watchlist_uuid,
          row_source_type,
          row_url,
          coalesce(row_notes, row_title),
          row_provenance,
          requested_member_id,
          case
            when row_status = 'confirmed' then 'confirmed'
            when row_status = 'needs_review' then 'needs_review'
            else 'needs_review'
          end,
          row_key
        )
        returning id into existing_source_uuid;

        if row_status = 'confirmed' then
          imported_count := imported_count + 1;
        else
          needs_review_count := needs_review_count + 1;
        end if;
      else
        duplicate_count := duplicate_count + 1;
      end if;

      inserted_ids := inserted_ids || jsonb_build_object(
        'kind', 'source_reference',
        'id', existing_source_uuid
      );

      if inferred_account is not null
        and jsonb_typeof(inferred_account) = 'object'
        and nullif(inferred_account->>'normalized_handle', '') is not null
      then
        inferred_normalized_handle := inferred_account->>'normalized_handle';
        inferred_handle := coalesce(nullif(inferred_account->>'handle', ''), '@' || inferred_normalized_handle);

        select id
        into inferred_benchmark_uuid
        from public.benchmark_creators
        where workspace_id = requested_workspace_id
          and creator_id = requested_creator_id
          and lower(coalesce(platform, '')) = 'instagram'
          and normalized_handle = inferred_normalized_handle
        limit 1;

        if inferred_benchmark_uuid is null then
          insert into public.benchmark_creators (
            workspace_id,
            creator_id,
            handle,
            normalized_handle,
            display_name,
            platform,
            region,
            niche_tags,
            audience_tags,
            relevance_notes,
            priority_score,
            mamta_relevance_score,
            status
          )
          values (
            requested_workspace_id,
            requested_creator_id,
            inferred_handle,
            inferred_normalized_handle,
            nullif(inferred_account->>'title', ''),
            'instagram',
            null,
            '{}',
            '{}',
            'Inferred from imported reference.',
            25,
            null,
            'candidate'
          )
          returning id into inferred_benchmark_uuid;

          needs_review_count := needs_review_count + 1;
        end if;

        insert into public.watchlist_benchmark_creators (
          workspace_id,
          creator_id,
          watchlist_id,
          benchmark_creator_id
        )
        values (
          requested_workspace_id,
          requested_creator_id,
          watchlist_uuid,
          inferred_benchmark_uuid
        )
        on conflict do nothing;

        if existing_source_uuid is not null then
          update public.source_references
          set benchmark_creator_id = inferred_benchmark_uuid
          where id = existing_source_uuid
            and benchmark_creator_id is null;
        end if;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'parser_version', parser_version,
    'destination', jsonb_build_object(
      'watchlist_id', watchlist_uuid,
      'watchlist_name', 'Inspiration'
    ),
    'counts', jsonb_build_object(
      'imported', imported_count,
      'needs_review', needs_review_count,
      'duplicates_skipped', duplicate_count,
      'invalid', invalid_count
    ),
    'inserted_ids', inserted_ids,
    'toast', format(
      'Imported %s. %s need review. %s duplicates skipped. %s could not be imported.',
      imported_count,
      needs_review_count,
      duplicate_count,
      invalid_count
    )
  );
end;
$$;

grant execute on function public.confirm_reference_import(jsonb) to service_role;
