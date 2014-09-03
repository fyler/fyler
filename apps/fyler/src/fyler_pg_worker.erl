-module(fyler_pg_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).
-include("../include/log.hrl").
-include("fyler.hrl").

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).

-record(state, {conn}).

start_link(Args) ->
  gen_server:start_link(?MODULE, Args, []).

init(_) ->
  Hostname = ?Config(pg_host, false),
  Database = ?Config(pg_db, false),
  Username = ?Config(pg_user, false),
  Password = ?Config(pg_pass, false),
  Conn = case Database of
    false -> ?D({no_database}), false;
    _ ->
      {ok, Connection} = pgsql:connect(Hostname, Username, Password, [
        {database, Database}
      ]),
      Connection
  end,
  {ok, #state{conn=Conn}}.


handle_call(_, _, #state{conn = false}=State) ->
  {reply, false, State};

handle_call({squery, Sql}, _From, #state{conn=Conn}=State) ->
  {reply, pgsql:squery(Conn, Sql), State};
handle_call({equery, Stmt, Params}, _From, #state{conn=Conn}=State) ->
  {reply, pgsql:equery(Conn, Stmt, Params), State};
handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_,#state{conn = false}) ->
  ok;

terminate(_Reason, #state{conn=Conn}) ->
  ok = pgsql:close(Conn),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
