-module(fyler_listener_to_monitor).

-behaviour(gen_event).

-include("log.hrl").
-include("fyler.hrl").

%% gen_event callbacks
-export([init/1,
  handle_event/2,
  handle_call/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-record(state, {category :: atom(),
                monitor :: pid()}).


%%%===================================================================
%%% gen_event callbacks
%%%===================================================================

init([Category, MonitorPid]) ->
  {ok, #state{category = Category, monitor = MonitorPid}}.

handle_event(#fevent{type = high_idle_time, category = Category}, #state{category = Category, monitor = Monitor} = State) ->
  gen_fsm:send_event(Monitor, high_idle_time),
  {ok, State};

handle_event(#fevent{type = pool_connected, node = Node, category = Category}, #state{category = Category, monitor = Monitor} = State) ->
  gen_fsm:send_event(Monitor, {pool_connected, Node}),
  {ok, State};

handle_event(#fevent{type = pool_down, node = Node, category = Category}, #state{category = Category, monitor = Monitor} = State) ->
  gen_fsm:send_event(Monitor, {pool_down, Node}),
  {ok, State};

handle_event(#fevent{type = pool_enable, node = Node, category = Category}, #state{category = Category, monitor = Monitor} = State) ->
  gen_fsm:send_event(Monitor, {pool_enable, Node}),
  {ok, State};

handle_event(#fevent{type = pool_disable, node = Node, category = Category}, #state{category = Category, monitor = Monitor} = State) ->
  gen_fsm:send_event(Monitor, {pool_disable, Node}),
  {ok, State};

handle_event(_Event, State) ->
  {ok, State}.

handle_call(_Request, State) ->
  Reply = ok,
  {ok, Reply, State}.

handle_info(_Info, State) ->
  {ok, State}.

terminate(_Arg, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
