-module(fyler_category_manager).
-behaviour(gen_fsm).

-include("../include/log.hrl").
-include("fyler.hrl").

-define(REGEX, "\"PrivateIpAddress\": \"(?<ip>[^\"]*)\"").
-define(NODE(Category, Ip), list_to_atom(lists:flatten(io_lib:format("fyler_~p_pool@~s", [Category, Ip])))).
-define(TIMEOUT, 60000).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([
  start_link/1,
  run_task/2,
  cancel_task/2,
  task_accepted/3,
  task_rejected/3,
  pool_connected/2,
  pool_down/2,
  pool_enabled/2,
  pool_disabled/2
]).

%% ------------------------------------------------------------------
%% gen_fsm Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_event/3,
         handle_sync_event/4, handle_info/3,
         terminate/3, code_change/4]).

-export([start/2, zero/2, tasks/2, pools/2]).

-record(state, {
  category :: atom(),
  retasks = fyler_queue:new() :: fyler_queue:fyler_queue(task()),
  tasks = fyler_queue:new() :: fyler_queue:fyler_queue(task()),
  task_filter = [] :: [task()],
  pools = [] :: [{atom(), enabled | disabled | {pending, reference(), non_neg_integer()}}],
  passive_pools = [] :: [atom()],
  index = 0 :: non_neg_integer(),
  priorities = #{} :: #{atom() => pos_integer()},
  node_to_id = #{} :: #{atom() => iolist()},
  check_ref :: reference()
}).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Category) ->
  gen_fsm:start_link(?MODULE, [Category], []).

run_task(Manager, #task{} = Task) ->
  gen_fsm:send_event(Manager, {run, Task}).

cancel_task(Manager, Id) ->
  gen_fsm:send_event(Manager, {cancel, Id}).

task_accepted(Manager, Ref, Node) ->
  gen_fsm:send_event(Manager, {task_accepted, Ref, Node}).

task_rejected(Manager, Ref, Node) ->
  gen_fsm:send_event(Manager, {task_rejected, Ref, Node}).

pool_connected(Manager, Node) ->
  gen_fsm:send_event(Manager, {pool_connected, Node}).

pool_down(Manager, Node) ->
  gen_fsm:send_event(Manager, {pool_down, Node}).

pool_enabled(Manager, Node) ->
  gen_fsm:send_event(Manager, {pool_enabled, Node}).

pool_disabled(Manager, Node) ->
  gen_fsm:send_event(Manager, {pool_disabled, Node}).

%% ------------------------------------------------------------------
%% gen_fsm Function Definitions
%% ------------------------------------------------------------------

init([Category]) ->
  self() ! start,
  {ok, start, #state{category = Category}}.

start(Event, #state{} = State) ->
  {next_state, NextState, NewState} = start_(Event, State),
  apply_state(NextState, start, NewState#state{check_ref = undefined}).

zero({check, Ref}, #state{check_ref = Ref} = State) ->
  zero(check, State);

zero({check, _}, State) ->
  {next_state, zero, State};

zero(Event, #state{} = State) ->
  {next_state, NextState, NewState} = zero_(Event, State),
  case NextState of
    zero ->
      {next_state, NextState, NewState};
    NextState ->
      apply_state(NextState, start, NewState#state{check_ref = undefined})
  end.

pools({check, Ref}, #state{check_ref = Ref} = State) ->
  pools(check, State);

pools({check, _}, State) ->
  {next_state, pools, State};

pools(Event, #state{} = State) ->
  {next_state, NextState, NewState} = pools_(Event, State),
  case NextState of
    pools ->
      {next_state, NextState, NewState};
    NextState ->
      apply_state(NextState, start, NewState#state{check_ref = undefined})
  end.

tasks({check, Ref}, #state{check_ref = Ref} = State) ->
  tasks(check, State);

tasks({check, _}, State) ->
  {next_state, tasks, State};

tasks(Event, #state{} = State) ->
  {next_state, NextState, NewState} = tasks_(Event, State),
  case NextState of
    tasks ->
      {next_state, NextState, NewState};
    NextState ->
      apply_state(NextState, start, NewState#state{check_ref = undefined})
  end.

start_(start, #state{category = Category} = State) ->
  Priorities = maps:get(priorities, ?Config(Category, #{}), #{}),
  FreeNodes =
    fun
      (#pool{node = Node, enabled = true, category = C}, List) when C == Category -> [{Node, enabled} | List];
      (#pool{node = Node, enabled = false, category = C}, List) when C == Category -> [{Node, disabled} | List];
      (_, List) -> List
    end,
  Pools = ets:foldl(FreeNodes, [], ?T_POOLS),
  case ets:info(Category) of
    undefined ->
      ets:new(Category, [public, named_table, {keypos, #current_task.id}, {heir, whereis(fyler_server), ok}]);
    _ ->
      ok
  end,
  NextState =
    case is_enabled(Pools) of
      true -> pools;
      false -> zero
    end,

  InstanceList = maps:get(instances, ?Config(Category, #{}), []),
  {ok, Re} = re:compile(?REGEX),
  IdToNode =
    fun
      (Id, {Map, Nodes}) ->
        case re:run(aws_cli:instance(Id), Re, [{capture, [ip], list}]) of
          {match, [Ip]} ->
            Node = ?NODE(Category, Ip),
            {maps:put(Node, Id, Map), [Node | Nodes]};
          nomatch ->
            {Map, Nodes}
        end
    end,
  {NodeToId, AllNodes} = lists:foldl(IdToNode, {#{}, []}, InstanceList),
  PassiveNodes = lists:subtract(AllNodes, Pools),
  NewState = State#state{pools = Pools, passive_pools = PassiveNodes, priorities = Priorities, node_to_id = NodeToId},
  {next_state, NextState, NewState}.

zero_(start, State) ->
  {next_state, zero, State};

zero_({run, #task{priority = Priority} = Task}, #state{tasks = Tasks, priorities = Priorities} = State) ->
  NumPriority = maps:get(Priority, Priorities, 1),
  update_ets(Task),
  {next_state, tasks, State#state{tasks = fyler_queue:in(Task, NumPriority, Tasks)}};

zero_({task_rejected, Ref, Node}, #state{category = Category, retasks = ReTasks, pools = Pools} = State) ->
  case status(Node, Pools) of
    {pending, Ref, Id} ->
      NewPools = enable(Node, Pools),
      case task(Category, Id) of
        undefined ->
          {next_state, zero, State#state{pools = NewPools}};
        Task ->
          {NextState, NewState} = choose_pool(State#state{retasks = fyler_queue:in(Task, ReTasks), pools = NewPools}),
          {next_state, NextState, NewState}
      end;
    _ ->
      {next_state, zero, State}
  end;

zero_({pool_connected, Node}, #state{pools = Pools, passive_pools = PassivePools} = State) ->
  {next_state, pools, State#state{pools = connect(Node, Pools), passive_pools = lists:delete(Node, PassivePools)}};

zero_({pool_enabled, Node}, #state{pools = Pools} = State) ->
  NewPools = enable(Node, Pools),
  {next_state, pools, State#state{pools = NewPools}};

zero_({task_accepted, Ref, Node}, #state{pools = Pools} = State) ->
  case status(Node, Pools) of
    {pending, Ref, _Id} ->
      NewPools = enable(Node, Pools),
      {next_state, pools, State#state{pools = NewPools}};
    _ ->
      {next_state, zero, State}
  end;

zero_({pool_disabled, Node}, #state{category = Category, retasks = ReTasks, pools = Pools} = State) ->
  NewPools = disable(Node, Pools),
  case status(Node, Pools) of
    {pending, _Ref, Id} ->
      case task(Category, Id) of
        undefined ->
          {next_state, zero, State#state{pools = NewPools}};
        Task ->
          rpc:cast(Node, fyler_pool, cancel_task, [Id]),
          {next_state, tasks, State#state{retasks = fyler_queue:in(Task, ReTasks), pools = NewPools}}
      end;
    _ ->
      {next_state, zero, State#state{pools = NewPools}}
  end;

zero_({pool_down, Node}, #state{category = Category, retasks = ReTasks, pools = Pools,
  passive_pools = PassivePools} = State) ->

  NewReTasks = restart_tasks(Category, ReTasks, Node),
  NewState = State#state{pools = delete(Node, Pools), passive_pools = [Node|PassivePools]},
  case fyler_queue:is_empty(NewReTasks) of
    true ->
      {next_state, zero, NewState};
    false ->
      {next_state, tasks, NewState#state{retasks = NewReTasks}}
  end;

zero_({cancel_task, Id}, #state{category = Category} = State) ->
  case ets:lookup(Category, Id) of
    [#current_task{pool = Node, status = progress}] ->
      ets:delete(Category, Id),
      rpc:cast(Node, fyler_pool, cancel_task, [Id]);
    _ ->
      ok
  end,
  {next_state, zero, State}.

pools_(start, #state{pools = [_]} = State) ->
  {next_state, pools, State};

pools_(start, #state{} = State) ->
  {next_state, pools, send_check(State)};

pools_(check, #state{pools = [_]} = State) ->
  {next_state, pools, State};

pools_(check, #state{pools = [{Pool, _}|_], node_to_id = NodeToId} = State) ->
  stop_pool(Pool, NodeToId),
  {next_state, pools, send_check(State)};

pools_({pool_connected, Node}, #state{pools = [Pool], passive_pools = PassivePools} = State) ->
  NewState = State#state{pools = connect(Node, [Pool]), passive_pools = lists:delete(Node, PassivePools)},
  {next_state, pools, send_check(NewState)};

pools_({pool_connected, Node}, #state{pools = Pools, passive_pools = PassivePools} = State) ->
  {next_state, pools, State#state{pools = connect(Node, Pools), passive_pools = lists:delete(Node, PassivePools)}};

pools_({pool_enabled, Node}, #state{pools = Pools} = State) ->
  {next_state, pools, State#state{pools = enable(Node, Pools)}};

pools_({task_accepted, Ref, Node}, #state{pools = Pools} = State) ->
  NewPools =
    case status(Node, Pools) of
      {pending, Ref, _Id} ->
        enable(Node, Pools);
      _ ->
        Pools
    end,
  {next_state, pools, State#state{pools = NewPools}};

pools_({pool_disabled, Node}, #state{category = Category, retasks = ReTasks, pools = Pools} = State) ->
  NewPools = disable(Node, Pools),
  NextState1 =
    case is_enabled(NewPools) of
      true -> pools;
      false -> zero
    end,
  NewState1 = State#state{pools = NewPools},
  {NextState, NewState} =
  case status(Node, Pools) of
    {pending, _Ref, Id} ->
      case task(Category, Id) of
        undefined ->
          {NextState1, NewState1};
        Task ->
          rpc:cast(Node, fyler_pool, cancel_task, [Id]),
          choose_pool(NewState1#state{retasks = fyler_queue:in(Task, ReTasks)})
      end;
    enabled ->
      {NextState1, NewState1}
  end,
  {next_state, NextState, NewState};

pools_({pool_down, Node}, #state{category = Category, retasks = ReTasks, pools = Pools,
  passive_pools = PassivePools} = State) ->

  NewReTasks = restart_tasks(Category, ReTasks, Node),
  State1 = State#state{retasks = NewReTasks, pools = delete(Node, Pools), passive_pools = [Node|PassivePools]},
  {NextState, NewState} = choose_pool(State1),
  {next_state, NextState, NewState};

pools_({task_rejected, Ref, Node}, #state{category = Category, retasks = ReTasks, pools = Pools} = State) ->
  case status(Node, Pools) of
    {pending, Ref, Id} ->
      NewPools = enable(Node, Pools),
      case task(Category, Id) of
        undefined ->
          {next_state, pools, State#state{pools = NewPools}};
        Task ->
          {NextState, NewState} = choose_pool(State#state{retasks = fyler_queue:in(Task, ReTasks), pools = NewPools}),
          {next_state, NextState, NewState}
      end;
    _ ->
      {next_state, pools, State}
  end;

pools_({run, #task{priority = Priority} = Task}, #state{tasks = Tasks, priorities = Priorities} = State) ->
  update_ets(Task),
  NumPriority = maps:get(Priority, Priorities, 1),
  NewTasks = fyler_queue:in(Task, NumPriority, Tasks),
  {NextState, NewState} = choose_pool(State#state{tasks = NewTasks}),
  {next_state, NextState, NewState};

pools_({cancel_task, Id}, #state{category = Category} = State) ->
  case ets:lookup(Category, Id) of
    [#current_task{pool = Node, status = progress}] ->
      ets:delete(Category, Id),
      rpc:cast(Node, fyler_pool, cancel_task, [Id]);
    [#current_task{status = queued}] ->
      ets:delete(Category, Id);
    _ ->
      ok
  end,
  {next_state, pools, State}.

tasks_(start, State) ->
  {next_state, tasks, send_check(State)};

tasks_(check, #state{passive_pools = []} = State) ->
  {next_state, tasks, send_check(State)};

tasks_(check, #state{passive_pools = Pools, node_to_id = NodeToId} = State) ->
  start_pool(lists:last(Pools), NodeToId),
  {next_state, tasks, send_check(State)};

tasks_({pool_connected, Node}, #state{pools = Pools, passive_pools = PassivePools} = State) ->
  State1 = State#state{pools = connect(Node, Pools), passive_pools = lists:delete(Node, PassivePools)},
  {NextState, NewState} = choose_pool(State1),
  {next_state, NextState, NewState};

tasks_({pool_enabled, Node}, #state{pools = Pools} = State) ->
  {NextState, NewState} = choose_pool(State#state{pools = enable(Node, Pools)}),
  {next_state, NextState, NewState};

tasks_({pool_down, Node}, #state{category = Category, retasks = ReTasks, pools = Pools, passive_pools = []} = State) ->
  NewReTasks = restart_tasks(Category, ReTasks, Node),
  {next_state, tasks, State#state{retasks = NewReTasks, pools = delete(Node, Pools), passive_pools = [Node]}};

tasks_({pool_down, Node}, #state{category = Category, retasks = ReTasks, pools = Pools,
  passive_pools = PassivePools} = State) ->

  NewReTasks = restart_tasks(Category, ReTasks, Node),
  NewState = State#state{retasks = NewReTasks, pools = delete(Node, Pools), passive_pools = [Node|PassivePools]},
  {next_state, tasks, NewState};

tasks_({pool_disabled, Node}, #state{category = Category, retasks = ReTasks, pools = Pools} = State) ->
  NewPools = disable(Node, Pools),
  case status(Node, Pools) of
    {pending, _Ref, Id} ->
      case task(Category, Id) of
        undefined ->
          {next_state, tasks, State#state{pools = NewPools}};
        Task ->
          rpc:cast(Node, fyler_pool, cancel_task, [Id]),
          {next_state, tasks, State#state{retasks = fyler_queue:in(Task, ReTasks), pools = NewPools}}
      end;
    _ ->
      {next_state, tasks, State#state{pools = NewPools}}
  end;

tasks_({task_accepted, Ref, Node}, #state{pools = Pools} = State) ->
  case status(Node, Pools) of
    {pending, Ref, _Id} ->
      {NextState, NewState} = choose_pool(State#state{pools = enable(Node, Pools)}),
      {next_state, NextState, NewState};
    _ ->
      {next_state, tasks, State}
  end;

tasks_({task_rejected, Ref, Node}, #state{category = Category, retasks = ReTasks, pools = Pools} = State) ->
  case status(Node, Pools) of
    {pending, Ref, Id} ->
      NewPools = enable(Node, Pools),
      case task(Category, Id) of
        undefined ->
          {next_state, tasks, State#state{pools = NewPools}};
        Task ->
          {NextState, NewState} = choose_pool(State#state{retasks = fyler_queue:in(Task, ReTasks), pools = NewPools}),
          {next_state, NextState, NewState}
      end;
    _ ->
      {next_state, tasks, State#state{pools = Pools}}
  end;

tasks_({run, #task{priority = Priority} = Task}, #state{tasks = Tasks, priorities = Priorities} = State) ->
  update_ets(Task),
  NumPriority = maps:get(Priority, Priorities, 1),
  {next_state, tasks, State#state{tasks = fyler_queue:in(Task, NumPriority, Tasks)}};

tasks_({cancel_task, Id}, #state{category = Category} = State) ->
  case ets:lookup(Category, Id) of
    [#current_task{pool = Node, status = progress}] ->
      ets:delete(Category, Id),
      rpc:cast(Node, fyler_pool, cancel_task, [Id]);
    [#current_task{status = queued}] ->
      ets:delete(Category, Id);
    _ ->
      ok
  end,
  {next_state, tasks, State}.

handle_event(_Event, StateName, State) ->
  {next_state, StateName, State}.

handle_sync_event(_Event, _From, StateName, State) ->
  {reply, ok, StateName, State}.

handle_info(start, start, State) ->
  start(start, State);

handle_info(zero, start, State) ->
  start(start, State);

handle_info({check, Ref}, zero, State) ->
  zero({check, Ref}, State);

handle_info({check, Ref}, pools, State) ->
  pools({check, Ref}, State);

handle_info({check, Ref}, tasks, State) ->
  tasks({check, Ref}, State);

handle_info(_Info, StateName, State) ->
  {next_state, StateName, State}.

terminate(_Reason, _StateName, _State) ->
  ok.

code_change(_OldVsn, StateName, State, _Extra) ->
  {ok, StateName, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

apply_state(start, Event, State) ->
  start(Event, State);

apply_state(zero, Event, State) ->
  zero(Event, State);

apply_state(pools, Event, State) ->
  pools(Event, State);

apply_state(tasks, Event, State) ->
  tasks(Event, State).

%% @doc Choose pool

choose_pool(#state{retasks = ReTasks, tasks = Tasks, pools = Pools} = State) ->
  {NextState, [NewReTasks, NewTasks], NewPools} = choose_pool([ReTasks, Tasks], Pools, [], []),
  {NextState, State#state{retasks = NewReTasks, tasks = NewTasks, pools = NewPools}}.

choose_pool([Queue|Queues], [{Node, enabled}|Pools], QueueAcc, PoolsAcc) ->
  case fyler_queue:out(Queue) of
    {empty, Queue} ->
      choose_pool(Queues, [{Node, enabled}|Pools], [Queue|QueueAcc], PoolsAcc);
    {{value, Task}, NewQueue} ->
      case send_to_pool(Node, Task) of
        {Ref, Id} -> choose_pool([NewQueue|Queues], Pools, QueueAcc, [{Node, {pending, Ref, Id}}|PoolsAcc]);
        _ -> choose_pool([NewQueue|Queues], [{Node, enabled}|Pools], QueueAcc, PoolsAcc)
      end
  end;

choose_pool([Queue|Queues], [{Node, Status}|Pools], QueueAcc, PoolsAcc) ->
  choose_pool([Queue|Queues], Pools, QueueAcc, [{Node, Status}|PoolsAcc]);

choose_pool([], Pools, QueueAcc, PoolsAcc) ->
  {pools, lists:reverse(QueueAcc), Pools ++ lists:reverse(PoolsAcc)};

choose_pool(Queues, [], QueueAcc, PoolsAcc) ->
  NewState =
    case lists:any(fun(Q) -> not fyler_queue:is_empty(Q) end, Queues) of
      false ->
        zero;
      true ->
        tasks
    end,
  {NewState, lists:reverse(QueueAcc) ++ Queues, lists:reverse(PoolsAcc)}.

%% @doc Get task from ets by id

task(Category, Id) ->
  case ets:lookup(Category, Id) of
    [#current_task{task = Task}] ->
      Task;
    _ ->
      undefined
  end.

%% @doc Restart tasks

restart_tasks(Category, Queue, Node) ->
  Tasks = ets:match_object(Category, #current_task{pool = Node, _= '_'}),
  In = fun(#current_task{task = Task}, Q) -> fyler_queue:in(Task, Q) end,
  lists:foldl(In, Queue, Tasks).

%% @doc Send task to remote pool

send_to_pool(Node, Task = #task{category = Category, id = Id}) ->
  case task(Category, Id) of
    undefined ->
      undefined;
    _ ->
      update_ets(Node, Task),
      Ref = make_ref(),
      rpc:cast(Node, fyler_pool, run_task, [Task, Ref]),
      {Ref, Id}
  end.

update_ets(Task) ->
  update_ets(undefined, Task).

update_ets(Node, #task{id = Id, type = Type, category = Category, file = #file{url = Url}} = Task) ->
  Status =
      case Node of
          undefined -> queued;
          _ -> progress
      end,
  ets:insert(Category, #current_task{id = Id, task = Task, type = Type, url = Url, pool = Node, status = Status}).

enable(Node, Pools) ->
  lists:keyreplace(Node, 1, Pools, {Node, enabled}).

disable(Node, Pools) ->
  lists:keyreplace(Node, 1, Pools, {Node, disabled}).

delete(Node, Pools) ->
  lists:keydelete(Node, 1, Pools).

connect(Node, Pools) ->
  [{Node, enabled}|Pools].

status(Node, Pools) ->
  case lists:keyfind(Node, 1, Pools) of
    {Node, Status} ->
      Status;
    _ ->
      disabled
  end.

is_enabled([]) ->
  false;

is_enabled([{_, enabled}|_]) ->
  true;

is_enabled([{_, _}|Pools]) ->
  is_enabled(Pools).

send_check(State) ->
  Ref = make_ref(),
  erlang:send_after(?TIMEOUT, self(), {check, Ref}),
  State#state{check_ref = Ref}.

stop_pool([{Pool, enabled}|_], NodeToId) ->
  stop_pool(Pool, NodeToId);

stop_pool([_|Pools], NodeToId) ->
  stop_pool(Pools, NodeToId);

stop_pool(Pool, NodeToId) ->
  case maps:find(Pool, NodeToId) of
    error ->
      ok;
    {ok, Id} ->
      aws_cli:stop_instance(Id)
  end.

start_pool(Pool, NodeToId) ->
  case maps:find(Pool, NodeToId) of
    error ->
      ok;
    {ok, Id} ->
      aws_cli:start_instance(Id)
  end.

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

-define(setup(F), {setup, fun setup_/0, fun cleanup_/1, F}).

setup_() ->
  lager:start(),
  ets:new(video, [public, named_table, {keypos, #current_task.id}]).

cleanup_(_) ->
  ets:delete(video),
  application:stop(lager).

choose_pool_test_() ->
  [
    {"handle state without pools",
      ?setup(
        fun choose_pool_no_pool_t_/1
      )
    },
    {"handle state without tasks",
      ?setup(
        fun choose_pool_no_tasks_t_/1
      )
    },
    {"handle ordinary state",
      ?setup(
        fun choose_pool_t_/1
      )
    }
  ].

choose_pool_no_pool_t_(_) ->
  T = fun(Id) -> #task{id = Id, category = video, file = #file{}} end,
  Q = fun(Id) -> fyler_queue:in(T(Id), fyler_queue:new()) end,
  update_ets(T(1)),
  update_ets(T(2)),
  State1 = #state{},
  State2 = #state{retasks = Q(1)},
  State3 = #state{tasks = Q(1)},
  State4 = #state{retasks = Q(1), tasks = Q(2)},
  [
    ?_assertEqual({zero, State1}, choose_pool(State1)),
    ?_assertEqual({tasks, State2}, choose_pool(State2)),
    ?_assertEqual({tasks, State3}, choose_pool(State3)),
    ?_assertEqual({tasks, State4}, choose_pool(State4))
  ].

choose_pool_no_tasks_t_(_) ->
  State1 = #state{pools = [{a, disabled}]},
  State2 = #state{pools = [{b, enabled}]},
  State3 = #state{pools = [{a, disabled}, {b, enabled}]},
  [
    ?_assertEqual({zero, State1}, choose_pool(State1)),
    ?_assertEqual({pools, State2}, choose_pool(State2)),
    ?_assertMatch({pools, #state{pools = _}}, choose_pool(State3))
  ].

choose_pool_t_(_) ->
  T = fun(Id) -> #task{id = Id, category = video, file = #file{}} end,
  Q = fun(Id) -> fyler_queue:in(T(Id), fyler_queue:new()) end,
  update_ets(T(1)),
  update_ets(T(2)),
  State1 = #state{tasks = Q(1), pools = [{a, disabled}]},
  State2 = #state{tasks = Q(1), pools = [{b, enabled}]},
  State3 = #state{tasks = Q(1), pools = [{a, disabled}, {b, enabled}]},
  State4 = #state{tasks = Q(1), pools = [{a, enabled}, {b, enabled}]},
  State5 = #state{retasks = Q(2), pools = [{a, disabled}]},
  State6 = #state{retasks = Q(2), pools = [{b, enabled}]},
  State7 = #state{retasks = Q(2), tasks = Q(1), pools = [{a, enabled}, {b, enabled}]},
  [
    ?_assertEqual({tasks, State1}, choose_pool(State1)),
    ?_assertMatch({zero, #state{pools = [{b, {pending, _, 1}}]}}, choose_pool(State2)),
    ?_assertMatch({zero, #state{pools = [{a, disabled}, {b, {pending, _, 1}}]}}, choose_pool(State3)),
    ?_assertMatch({pools, #state{pools = [{b, enabled}, {a, {pending, _, 1}}]}}, choose_pool(State4)),
    ?_assertEqual({tasks, State5}, choose_pool(State5)),
    ?_assertMatch({zero, #state{pools = [{b, {pending, _, 2}}]}}, choose_pool(State6)),
    ?_assertMatch({zero, #state{pools = [{a, {pending, _, 2}}, {b, {pending, _, 1}}]}}, choose_pool(State7))
  ].

-endif.
