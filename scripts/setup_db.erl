#! /usr/local/bin/escript
%%! -pa ebin -pa deps/epgsql/ebin -pa deps/ulitos/ebin

main(_) ->
  case file:consult("apps/fyler/priv/fyler.config") of
    {ok,List} ->
            create_db(
              proplists:get_value(pg_host,List),
              proplists:get_value(pg_user,List),
              proplists:get_value(pg_pass,List),
              proplists:get_value(pg_db,List)
            );
      _ ->  io:format("Config not found~n")
  end.

create_db(undefined,_,_,_) -> io:format("Host is not provided,.~n");
create_db(_,undefined,_,_) -> io:format("User is not provided,.~n");
create_db(_,_,undefined,_) -> io:format("Pass is not provided,.~n");
create_db(_,_,_,undefined) -> io:format("Database is not provided,.~n");


create_db(Host,User,Pass,DB) ->
  {ok, PG} = pgsql:connect(Host, User, Pass, [{database,DB}]),
  {ok,_,_} = pgsql:squery(PG, "CREATE TABLE IF NOT EXISTS tasks
  (
    id  serial PRIMARY KEY,
    status  varchar(8),
    download_time integer,
    upload_time integer,
    file_size integer,
    file_path text,
    time_spent integer,
    result_path text,
    task_type varchar(20),
    error_msg text,
    ts date DEFAULT NOW()
  );"),
  io:format("Table 'tasks' created.~n"),
  pgsql:close(PG).