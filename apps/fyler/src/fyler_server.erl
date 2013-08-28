%% Copyright
-module(fyler_server).
-author("palkan").
-include("../include/log.hrl").

-behaviour(gen_server).

%% API
-export([start_link/0]).

%% gen_server
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).

%% API
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% gen_server callbacks
-record(state, {
  cowboy_pid ::pid()
}).

init(_Args) ->
  ?D("Starting fyler webserver"),
  Dispatch = cowboy_router:compile([
    {'_', [
      {"/", index_handler, []},
      {'_', notfound_handler, []}
    ]}
  ]),
  Port = 8008,
  {ok, Pid} = cowboy:start_http(http_listener, 100,
    [{port, Port}],
    [{env, [{dispatch, Dispatch}]}]
  ),
  {ok, #state{cowboy_pid = Pid}}.

handle_call(_Request, _From, State) ->
  {noreply, State}.

handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
