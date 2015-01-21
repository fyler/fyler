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

-export([task_completed/2, task_aborted/1, task_failed/2, pool_enabled/2, pool_disabled/2, pool_connected/2, pool_down/2, high_idle_time/1]).

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


task_completed(#task{category = Category} = Task, Stats) ->
  gen_event:notify({global, ?MODULE}, #fevent{type = complete, node=node(), category = Category, task = Task,stats = Stats}).


%% @doc Send when task job is aborted.
%% @end

task_aborted(#task{category = Category} = Task) ->
  gen_event:notify({global, ?MODULE}, #fevent{type = aborted, node=node(), category = Category, task = Task}).


%% @doc Send when task job is failed.
%% @end

task_failed(#task{category = Category} = Task, #job_stats{error_msg = Error} = Stats) ->
  gen_event:notify({global, ?MODULE}, #fevent{type = failed, node=node(), category = Category, task = Task, error = Error, stats = Stats});


task_failed(Task, Error) ->
  ?E({task_failed, Task, unknown_error, Error}).


%% @doc
%% @end

pool_enabled(Node, Category) ->
  gen_event:notify({global, ?MODULE}, #fevent{node = Node, type = pool_enabled, category = Category}).

%% @doc
%% @end

pool_disabled(Node, Category) ->
  gen_event:notify({global, ?MODULE}, #fevent{node = Node, type = pool_disabled, category = Category}).

%% @doc
%% @end

pool_connected(Node, Category) ->
  gen_event:notify({global, ?MODULE}, #fevent{node = Node, type = pool_connected, category = Category}).

%% @doc
%% @end

pool_down(Node, Category) ->
  gen_event:notify({global, ?MODULE}, #fevent{node = Node, type = pool_down, category = Category}).

%% @doc
%% @end

high_idle_time(Category) ->
  gen_event:notify({global, ?MODULE}, #fevent{type = high_idle_time, category = Category}).

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
