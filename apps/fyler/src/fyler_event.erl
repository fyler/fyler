%% Copyright
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

-export([task_completed/2,task_failed/2]).

start_link() ->
  ?D(start_fevent),
  {ok, Pid} = gen_event:start_link({local, ?MODULE}),
  {ok, Pid}.

stop_handlers() ->
  [gen_event:delete_handler(?MODULE, Handler, []) || Handler <- gen_event:which_handlers(?MODULE)].

%% @doc Dispatch event to listener
%% @end

-spec notify(any()) -> ok.

notify(Event) ->
  gen_event:notify(?MODULE, Event).


%% @doc
%% @end

-spec add_handler(any(), [any()]) -> ok.

add_handler(Handler, Args) ->
  gen_event:add_handler(?MODULE, Handler, Args).


%% @doc
%% @end

-spec add_sup_handler(any(), [any()]) -> ok.

add_sup_handler(Handler, Args) ->
  gen_event:add_sup_handler(?MODULE, Handler, Args).

%% @doc
%% @end

-spec remove_handler(any()) -> ok.

remove_handler(Handler) ->
  gen_event:delete_handler(?MODULE, Handler,[]).


%% @doc Send when task job is finished successfully.
%% @end


task_completed(Task, Stats) ->
  gen_event:notify(?MODULE, #fevent{type = complete,task = Task,stats = Stats}),
  fyler_server:send_response(Task,Stats,success).

%% @doc Send when task job is failed.
%% @end

task_failed(Task, Error) ->
  gen_event:notify(?MODULE, #fevent{type = failed,task = Task,error = Error}),
  fyler_server:send_response(Task,undefined,failed).


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
