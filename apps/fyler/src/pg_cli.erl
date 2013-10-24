-module(pg_cli).
-include("../include/log.hrl").
-include("fyler.hrl").

%% API
-export([squery/1, equery/1, equery/2]).


%% @doc
%% Make psql query
%% @end

squery(Sql) ->
  poolboy:transaction(?PG_POOL, fun(Worker) ->
    gen_server:call(Worker, {squery, Sql})
  end).

%% @doc
%% Make psql extended query
%% @end


equery(Stmt) -> equery(Stmt,[]).

equery(Stmt, Params) ->
  poolboy:transaction(?PG_POOL, fun(Worker) ->
    gen_server:call(Worker, {equery, Stmt, Params})
  end).