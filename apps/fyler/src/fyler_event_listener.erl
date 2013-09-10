%% Copyright
-module(fyler_event_listener).
-author("palkan").
-behaviour(gen_event).
-include("../include/log.hrl").
-include("fyler.hrl").

%% API
-export([listen/0]).

-export([init/1, handle_event/2, handle_call/2, handle_info/2, code_change/3,
  terminate/2]).


listen() ->
  ?D(listen_task_events),
  fyler_event:add_sup_handler(?MODULE, []),
  receive
    Msg -> ?D({listen, Msg})
  end.

init(_Args) ->
  ?D({event_handler_set}),
  {ok,[]}.

handle_event(#fevent{type = complete, task = #task{file = #file{url = Url}, type = Type}, stats = #job_stats{time_spent = Time, download_time = DTime}}, State) ->
  ?D({task_complete, Type, Url, {time,Time},{download_time,DTime}}),
  {ok, State};

handle_event(#fevent{type = failed, task = #task{file = #file{url = Url}, type = Type}, error = Error}, State) ->
  ?D({task_failed, Type, Url, Error}),
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