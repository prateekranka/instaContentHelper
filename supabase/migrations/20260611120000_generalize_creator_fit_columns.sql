-- Generalize legacy creator-specific fit columns without retaining a product-specific name.
do $$
declare
  target_table text;
  legacy_column_name text;
begin
  foreach target_table in array array['patterns', 'trends', 'daily_cards']
  loop
    select columns.column_name
      into legacy_column_name
      from information_schema.columns
      where columns.table_schema = 'public'
        and columns.table_name = target_table
        and columns.column_name like '%\_fit_score' escape '\'
        and columns.column_name <> 'creator_fit_score'
      order by columns.ordinal_position
      limit 1;

    if legacy_column_name is not null then
      execute format(
        'alter table public.%I rename column %I to creator_fit_score',
        target_table,
        legacy_column_name
      );
    end if;

    legacy_column_name := null;
  end loop;
end
$$;

update public.workspaces
set name = 'Creator Content OS',
    updated_at = now()
where id = '425ce0e2-cf50-43a1-92aa-087a91c59ef7';

update public.creators
set display_name = 'Creator',
    handle = 'creator',
    updated_at = now()
where id = 'dbc7452d-c2ff-4d52-976f-734fad55f86b';
