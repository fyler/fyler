%% Copyright
-module(fyler_pool_master).
-author("palkan").
-include("../include/log.hrl").
-include("fyler.hrl").

-behaviour(gen_server).

-define(TRY_NEXT_TIMEOUT, 1500).

%% Maximum time for waiting any pool to become enabled.
-define(IDLE_TIME_WM, 60000).

%% Limit on queue length. If it exceeds new pool instance should be started.
-define(QUEUE_LENGTH_WM, 30).

%% API
-export([start_link/1]).

%% gen_server
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).


%% gen_server callbacks
-record(state, {
  pools_active = [] ::list(),
  pools_busy = [] ::list(),
  type  ::atom(),
  busy_timer_ref = undefined,
  tasks = queue:new() ::queue:queue(task())
}).


%% API
start_link(Type) ->
  ?D({start_pool_master, Type}),
  gen_server:start_link({local, ?MODULE}, ?MODULE, [Type], []).

init(Type) ->
  ?D({pool_master_started,Type}),
  {ok, #state{type = Type}}.



handle_call({run_task, Task}, _From, #state{tasks = Tasks} = State) ->
  NewTasks = queue:in(Task, Tasks),
  self() ! try_next_task,
  {reply, ok, State#state{tasks = NewTasks}};

handle_call(pools, _From, #state{pools_active=Active, pools_busy = Busy} = State) ->
  {reply, Active++Busy, State};

handle_call(_Request, _From, State) ->
  ?D(_Request),
  {reply, unknown, State}.


handle_cast({pool_enabled, Node, true}, #state{pools_busy = Busy, pools_active = Active} = State) ->
  ?D({pool_enabled, Node}),
  case lists:keyfind(Node, #pool.node, Busy) of
    #pool{} = Pool ->
      NewPool = Pool#pool{enabled = true},
      self() ! try_next_task,
      {noreply, State#state{pools_active = lists:keystore(Node, #pool.node, Active, NewPool), pools_busy = lists:keydelete(Node, #pool.node, Busy)}};
    _ -> 
      ?E({pool_not_found, Node}),
      {noreply, State}
  end;


handle_cast({pool_enabled, Node, false}, #state{pools_active = Active, pools_busy = Busy} = State) ->
  ?D({pool_disabled, Node}),
  case lists:keyfind(Node, #pool.node, Active) of
    #pool{} = Pool ->
      NewPool = Pool#pool{enabled = false},
      {noreply, State#state{pools_busy = lists:keystore(Node, #pool.node, Busy, NewPool), pools_active = lists:keydelete(Node, #pool.node, Active)}};
    _ -> 
      ?E({pool_not_found, Node}),
      {noreply, State}
  end;


handle_cast(_Request, State) ->
  ?D(_Request),
  {noreply, State}.


handle_info({pool_connected, Node, Type, true, Num}, #state{pools_active = Pools} = State) ->
  NewPool = #pool{node = Node, type = Type, enabled = true, total_tasks = Num},
  NewPools = lists:keystore(Node, #pool.node, Pools, NewPool),
  self() ! try_next_task,
  {noreply, State#state{pools_active = NewPools}};

handle_info({pool_connected, Node, Type, false, Num}, #state{pools_busy = Pools} = State) ->
  NewPool = #pool{node = Node, type = Type, enabled = false, total_tasks = Num},
  NewPools = lists:keystore(Node, #pool.node, Pools, NewPool),
  {noreply, State#state{pools_busy = NewPools}};


handle_info({pool_disconnected, Node}, #state{pools_active = Active, pools_busy = Busy} = State) ->
  NewActive = lists:keydelete(Node, #pool.node, Active),
  NewBusy = lists:keydelete(Node, #pool.node, Busy),
  {noreply, State#state{pools_active = NewActive, pools_busy = NewBusy}};

handle_info(try_next_task, #state{pools_active = [], busy_timer_ref = undefined} = State) ->
  ?D(<<"All pools are busy; start timer to run new reserved instance">>),
  Ref = erlang:send_after(?IDLE_TIME_WM, self(), alarm_high_idle_time),
  {noreply, State#state{busy_timer_ref = Ref}};

handle_info(try_next_task, #state{pools_active = [], tasks = Tasks} = State) when length(Tasks) > ?QUEUE_LENGTH_WM ->
  ?D({<<"Queue is too big, start new instance">>, length(Tasks)}),
  self() ! {alarm_too_many_tasks},
  {noreply, State};


handle_info(try_next_task, #state{pools_active = Pools, busy_timer_ref = Ref} = State) when Ref /= undefined andalso length(Pools) > 0 ->
  erlang:cancel_timer(Ref),
  handle_info(try_next_task, State#state{busy_timer_ref = undefined});

handle_info(try_next_task, #state{type = Type, tasks = Tasks, pools_active = Pools} = State) ->
  {NewTasks, NewPools} = case queue:out(Tasks) of
                           {empty, _} -> ?D(no_more_tasks),
                             {Tasks, Pools};
                           {{value, Task}, Tasks2} ->
                             case choose_pool(Pools) of
                               #pool{node = Node, total_tasks = Total} = Pool ->
                                 rpc:cast(Node, fyler_pool, run_task, [Task]),
                                 {Tasks2, lists:keystore(Node, #pool.node, Pools, Pool#pool{total_tasks = Total + 1})};
                               _ -> {Tasks, Pools}
                             end
                         end,
  Empty = queue:is_empty(NewTasks),
  if Empty
    -> ?D({no_more_tasks, Type}), ok;
    true -> erlang:send_after(?TRY_NEXT_TIMEOUT, self(), try_next_task)
  end,
  {noreply, State#state{pools_active = NewPools, tasks = NewTasks}};

handle_info(alarm_high_idle_time, #state{type = Type} = State) ->
  ?D(<<"Too much time in idle state">>),
  fyler_server:start_pool(Type),
  {noreply, State#state{busy_timer_ref = undefined}};


handle_info(alarm_too_many_tasks, #state{type = Type} = State) ->
  ?D(<<"Too many open tasks!">>),
  fyler_server:start_pool(Type),
  {noreply, State};

handle_info(Info, State) ->
  ?D(Info),
  {noreply, State}.

terminate(_Reason, _State) ->
  ?D(_Reason),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%% @doc
%% Choose pool with the smallest number of total tasks
%% @end

-spec choose_pool(list(#pool{})) -> #pool{}|undefined.

choose_pool([]) ->
  undefined;

choose_pool(Pools) ->
  hd(lists:keysort(#pool.total_tasks, Pools)).


-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

choose_pool_test() ->
  Pool = #pool{node = a, total_tasks = 0},
  A = [
    #pool{node = a, total_tasks = 2},
    Pool
  ],
  ?assertEqual(Pool, choose_pool(A)),
  ?assertEqual(undefined, choose_pool([])).

-endif.