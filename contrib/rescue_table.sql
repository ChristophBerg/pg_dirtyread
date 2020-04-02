create or replace function rescue_table(relname regclass, savename name default null, "create" boolean default true)
returns text
as $$
declare
  pages int;
  page int;
  ctid tid;
  row_count bigint;
  good_tuples bigint := 0;
  bad_pages bigint := 0;
  bad_tuples bigint := 0;
  sql_state text;
  error text;
begin
  if savename is null then
    savename := relname || '_rescue';
  end if;
  if rescue_table.create then
    execute format('CREATE TABLE %I (LIKE %I)', savename, relname);
  end if;

  select pg_relation_size(relname) / current_setting('block_size')::int into pages;

  for page in 0 .. pages-1 loop
    if page % 10000 = 0 then
      raise notice '%: page % of %', relname, page, pages;
    end if;

    begin

      for ctid in select t_ctid from heap_page_items(get_raw_page(relname::text, page)) loop
        begin
          execute format('INSERT INTO %I SELECT * FROM %I WHERE ctid=%L', savename, relname, ctid);
          get diagnostics row_count = ROW_COUNT;
          good_tuples := good_tuples + row_count;
        exception -- bad tuple
          when others then
            get stacked diagnostics sql_state := RETURNED_SQLSTATE;
            get stacked diagnostics error := MESSAGE_TEXT;
            raise notice 'Skipping ctid %: %: %', ctid, sql_state, error;
            bad_tuples := bad_tuples + 1;
        end;
      end loop;

    exception -- bad page
      when others then
        get stacked diagnostics sql_state := RETURNED_SQLSTATE;
        get stacked diagnostics error := MESSAGE_TEXT;
        raise notice 'Skipping page %: %: %', page, sql_state, error;
        bad_pages := bad_pages + 1;
    end;

  end loop;

  error := format('rescue_table %I into %I: %s of %s pages are bad, %s bad tuples, %s tuples copied',
    relname, savename, bad_pages, pages, bad_tuples, good_tuples);
  raise log '%', error;
  return error;
end;
$$ language plpgsql;

comment on function rescue_table(regclass, name, boolean) is
  'copy all good tuples from a table to another one';
