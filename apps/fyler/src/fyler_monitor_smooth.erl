-module(fyler_monitor_smooth).
-author("ilia").

-behaviour(gen_fsm).

-include("fyler.hrl").
-include("log.hrl").

-define(TIMER, 6000).

%% API
-export([start_link/0]).

%% gen_fsm callbacks
-export([init/1,
  enabled/2,
  pre_enabled/2,
  disabled/2,
  handle_event/3,
  handle_sync_event/4,
  handle_info/3,
  terminate/3,
  code_change/4]).

-record(state, {category :: atom()}).

%%%===================================================================
%%% API
%%%===================================================================

start_link() ->
  gen_fsm:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

init([]) ->
  {ok, start, #state{}}.

pre_enabled(timeout, #state{category = Category} = State) ->
  fyler_event:pool_enabled_smooth(node(), Category),
  {next_state, enabled, State};

pre_enabled(_Event, State) ->
  {next_state, pre_enabled, State}.

enabled(_Event, State) ->
  {next_state, enabled, State}.

disabled(_Event, State) ->
  {next_state, disabled, State}.

handle_sync_event(_Event, _From, StateName, State) ->
  {reply, undefined, StateName, State}.

handle_event(enabled, disabled, State) ->
  {next_state, pre_enabled, State, ?TIMER};

handle_event(disabled, pre_enabled, State) ->
  {next_state, disabled, State};

handle_event(disabled, enabled, #state{category = Category} = State) ->
  fyler_event:pool_disabled_smooth(node(), Category),
  {next_state, disabled, State};

handle_event(_Event, StateName, State) ->
  {next_state, StateName, State}.

handle_info({category, Category}, start, #state{} = State) ->
  {next_state, enabled, State#state{category = Category}};

handle_info(_Info, StateName, State) ->
  {next_state, StateName, State}.

terminate(_Reason, _StateName, _State) ->
  ok.

code_change(_OldVsn, StateName, State, _Extra) ->
  {ok, StateName, State}.
