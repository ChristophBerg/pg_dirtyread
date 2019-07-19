-- read all good tuples from a table, skipping over all tuples that trigger an error

create or replace function read_table(relname regclass)
returns setof record
as $$
declare
  pages int;
  page int := 0;
  item int;
  r record;
  sql_state text;
  error text;
begin
  select pg_relation_size(relname) / current_setting('block_size')::int into pages;

  <<pageloop>>
  while page < pages loop
    item := 1;

    <<itemloop>>
    while true loop

      begin
        execute format('SELECT * FROM %I WHERE ctid=''(%s,%s)'' ', relname, page, item) into r;
        if r is null then
          exit itemloop;
        end if;
        return next r;
      exception
        when others then
          get stacked diagnostics sql_state := RETURNED_SQLSTATE;
          get stacked diagnostics error := MESSAGE_TEXT;
          raise notice 'Skipping ctid (%,%): %: %', page, item, sql_state, error;
      end;

      item := item + 1;
    end loop;

    page := page + 1;
  end loop;
end;
$$ language plpgsql;

-- return ctids of all tuples in a table that trigger an error
create or replace function bad_tuples(relname regclass)
returns table (ctid tid, sqlstate text, sqlerrm text)
as $$
declare
  pages int;
  page int := 0;
  item int;
  r record;
begin
  SELECT pg_relation_size(relname) / current_setting('block_size')::int INTO pages;

  <<pageloop>>
  while page < pages loop
    item := 1;

    <<itemloop>>
    while true loop

      begin
        execute format('SELECT * FROM %I WHERE ctid=''(%s,%s)'' ', relname, page, item) into r;
        if r is null then
          exit itemloop;
        end if;
      exception
        when others then
          ctid := format('(%s,%s)', page, item);
          bad_tuples.sqlstate := sqlstate;
          bad_tuples.sqlerrm := sqlerrm;
          return next;
      end;

      item := item + 1;
    end loop;

    page := page + 1;
  end loop;
end;
$$ language plpgsql;

