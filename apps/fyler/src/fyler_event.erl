%%% @doc
%%% Global event manager
%%% @end


-module(fyler_event).
-author("palkan").

-behaviour(gen_event).
-include("../include/log.hrl").
-include("fyler.hrl").

%% External API
-export([start_link/0, notify/1, add_handler/2, add_sup_handler/2, remove_handler/1]).
-export([stop_handlers/0]).

%% gen_event callbacks
-export([init/1, handle_call/2, handle_event/2, handle_info/2, terminate/2, code_change/3]).

-export([task_completed/2,task_failed/2, pool_enabled/0,pool_disabled/0]).

start_link() ->
  ?D(start_fevent),
  {ok, Pid} = gen_event:start_link({global, ?MODULE}),
  {ok, Pid}.

stop_handlers() ->
  [gen_event:delete_handler({global, ?MODULE}, Handler, []) || Handler <- gen_event:which_handlers({global, ?MODULE})].

%% @doc Dispatch event to listener
%% @end

-spec notify(any()) -> ok.

notify(Event) ->
  gen_event:notify({global, ?MODULE}, Event).


%% @doc
%% @end

-spec add_handler(any(), [any()]) -> ok.

add_handler(Handler, Args) ->
  gen_event:add_handler({global, ?MODULE}, Handler, Args).


%% @doc
%% @end

-spec add_sup_handler(any(), [any()]) -> ok.

add_sup_handler(Handler, Args) ->
  gen_event:add_sup_handler({global, ?MODULE}, Handler, Args).

%% @doc
%% @end

-spec remove_handler(any()) -> ok.

remove_handler(Handler) ->
  gen_event:delete_handler({global, ?MODULE}, Handler,[]).


%% @doc Send when task job is finished successfully.
%% @end


task_completed(Task, Stats) ->
  gen_event:notify({global, ?MODULE}, #fevent{type = complete, node=node(), task = Task,stats = Stats}).

%% @doc Send when task job is failed.
%% @end

task_failed(Task, #job_stats{error_msg = Error} = Stats) ->
  gen_event:notify({global, ?MODULE}, #fevent{type = failed,node=node(), task = Task,error = Error, stats = Stats}).


%% @doc
%% @end

pool_enabled() ->
  gen_event:notify({global, ?MODULE}, #fevent{node=node(), type = pool_enabled}).

%% @doc
%% @end

pool_disabled() ->
  gen_event:notify({global, ?MODULE}, #fevent{node=node(), type = pool_disabled}).


init([]) ->
  {ok, state}.


%% @private
handle_call(Request, State) ->
  {ok, Request, State}.

%% @private
handle_event(_Event, State) ->
  %?D({ems_event, Event}),
  {ok, State}.


%% @private
handle_info(_Info, State) ->
  {ok, State}.


%% @private
terminate(_Reason, _State) ->
  ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
