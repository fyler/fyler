%% Copyright
-module(fyler_system_listener).
-author("palkan").
-behaviour(gen_event).
-include("../include/log.hrl").
-include("fyler.hrl").

%% API
-export([listen/0]).

-export([init/1, handle_event/2, handle_call/2, handle_info/2, code_change/3,
  terminate/2]).


listen() ->
  gen_event:add_sup_handler(alarm_handler, ?MODULE, []),
  receive
    Msg -> ?D({listen, Msg})
  end.

init(_Args) ->
  ?D({alarm_handler_set}),
  {ok,[]}.

handle_event({set_alarm,{system_memory_high_watermark,_}},S) ->
  case ?Config(role,false) of
    pool -> fyler_pool:disable();
    _ -> ok
  end,
  {ok,S};

handle_event({clear_alarm,system_memory_high_watermark},S) ->
  case ?Config(role,false) of
    pool -> fyler_pool:enable();
    _ -> ok
  end,
  {ok,S};

handle_event(_Event, Pid) ->
  ?D([alarm_event, _Event]),
  {ok, Pid}.

handle_call(_, State) ->
  {ok, ok, State}.

handle_info(_Info, State) ->
  ?D([alarm_info, _Info]),
  {ok, State}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

terminate(_Reason, _State) ->
  ok.