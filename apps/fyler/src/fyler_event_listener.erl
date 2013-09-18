%% Copyright
-module(fyler_event_listener).
-author("palkan").
-behaviour(gen_event).
-include("../include/log.hrl").
-include("fyler.hrl").

%% API
-export([listen/0, start_link/0]).

-export([init/1, handle_event/2, handle_call/2, handle_info/2, code_change/3,
  terminate/2]).

start_link() ->
  Pid = spawn_link(?MODULE, listen, []),
  {ok, Pid}.

listen() ->
  ?D(listen_task_events),
  fyler_event:add_sup_handler(?MODULE, []),
  receive
    Msg -> ?D({listen, Msg})
  end.

init(_Args) ->
  ?D({event_handler_set}),
  {ok,[]}.

handle_event(#fevent{type = complete, node = Node, task = #task{file = #file{url = Url}, type = Type} = Task, stats = #job_stats{time_spent = Time, download_time = DTime} = Stats}, State) ->
  ?D({task_complete, Type, Url, {time,Time},{download_time,DTime}}),
  ets:insert(?T_STATS,Stats),
  fyler_server:send_response(Task,Stats,success),
  gen_server:cast(fyler_server,{task_finished,Node}),
  {ok, State};

handle_event(#fevent{type = failed, node = Node, task = #task{file = #file{url = Url}, type = Type} = Task, error = Error, stats = Stats}, State) ->
  ?D({task_failed, Type, Url, Error}),
  ets:insert(?T_STATS,Stats),
  fyler_server:send_response(Task,undefined,failed),
  gen_server:cast(fyler_server,{task_finished,Node}),
  {ok, State};

handle_event(#fevent{type = pool_enabled, node = Node}, State) ->
  gen_server:cast(fyler_server,{pool_enabled,Node, true}),
  {ok, State};

handle_event(#fevent{type = pool_disabled, node = Node}, State) ->
  gen_server:cast(fyler_server,{pool_enabled,Node, false}),
  {ok, State};

handle_event(_Event, Pid) ->
  ?D([unknown_event, _Event]),
  {ok, Pid}.

handle_call(_, State) ->
  {ok, ok, State}.

handle_info(_, State) ->
  {ok, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

terminate(_Reason, _State) ->
  ok.