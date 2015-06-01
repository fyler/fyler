%% Copyright
-module(fyler_pool).
-author("palkan").
-include("../include/log.hrl").
-include("../include/handlers.hrl").
-include("fyler.hrl").

-behaviour(gen_server).

-define(TRY_NEXT_TIMEOUT, 1500).
-define(POOL_BUSY_TIMEOUT, 5000).
-define(POLL_SERVER_TIMEOUT, 30000).

%% API
-export([start_link/0]).

-export([run_task/2, cancel_task/1, disable/0, enable/0]).

%% gen_server
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).

%% API
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% gen_server callbacks
-record(state, {
  enabled = true :: boolean(),
  busy = false :: boolean(),
  category ::atom(),
  server_node ::atom(),
  connected = false ::false|true|pending,
  storage_dir :: string(),
  aws_bucket :: string(),
  max_active = 1 ::non_neg_integer(),
  buf_size = 0 :: non_neg_integer(),
  max_buf_size = 1 :: non_neg_integer(),
  tasks = queue:new() :: queue:queue(task()),
  active_tasks = [] :: list(task()),
  finished_tasks = [] :: list({atom(), task(), stats()}),
  pids = #{} :: #{reference() => pid()}
}).

init(_Args) ->
  net_kernel:monitor_nodes(true),

  ?D("Starting fyler pool"),
  Dir = ?Config(storage_dir, "ff"),
  ok = filelib:ensure_dir(Dir),
  case file:make_dir(Dir) of
    ok -> ok;
    {error, eexist} -> ok
  end,
  
  Server = ?Config(server_name, null),
  ?D({server, Server}),

  self() ! connect_to_server,

  ulitos_app:ensure_loaded(?Handlers),

  Category = ?Config(category, undefined),

  case Category of
    video -> media:start();
    _ -> ok
  end,

  MaxActive = ?Config(max_active, 1),

  MaxBufSize = ?Config(max_buf_size, 1),

  lager:md([{context, {[{category, Category}, {max_active, MaxActive}]}}]),

  State = #state{
    storage_dir = Dir,
    category = Category,
    server_node = Server,
    max_active = MaxActive,
    max_buf_size = MaxBufSize
  },

  {ok, State}.


%% @doc
%% Run new task.
%% @end

-spec run_task(task(), reference()) -> ok|false.

run_task(Task, Ref) ->
  gen_server:call(?MODULE, {run_task, Task, Ref}).

%% @doc
%% Cancel the task
%% @end

cancel_task(TaskId) ->
  gen_server:call(?MODULE, {cancel_task, TaskId}).

%% @doc
%% Stop running tasks and queue them.
%% @end

-spec disable() -> ok|false.

disable() ->
  gen_server:call(?MODULE, {enabled, false}).

%% @doc
%% Enable running tasks and run tasks from queue.
%% @end

-spec enable() -> ok|false.

enable() ->
  gen_server:call(?MODULE, {enabled, true}).

handle_call({run_task, Task, Ref}, _From, #state{} = State) ->
  self() ! {try_task, Task, Ref},
  {reply, ok, State, timeout(State)};

handle_call({cancel_task, TaskId}, _From, #state{tasks = Tasks, active_tasks = Active, pids = Pids} = State) ->
  case lists:keyfind(TaskId, #task.id, Active) of
    #task{worker = Ref} ->
      Pid = maps:get(Ref, Pids),
      try fyler_sup:stop_worker(Pid)
      catch
        _:_ -> ok
      end,
      {reply, ok, State, timeout(State)};
    _ ->
      NewTasks = queue:filter(fun(#task{id = Id}) when Id == TaskId -> false; (_) -> true end, Tasks),
      NewState = State#state{tasks = NewTasks, buf_size = queue:len(NewTasks)},
      {reply, ok, NewState, timeout(NewState)}
  end;

handle_call({enabled, true}, _From, #state{enabled = false, connected = Connected, busy = Busy} = State) ->
  if Connected and not Busy
    -> pool_enabled(State);
    true -> ok
  end,

  {reply, ok, State#state{enabled = true}, timeout(State)};

handle_call({enabled, false}, _From, #state{enabled = true, connected = Connected, busy = Busy} = State) ->

  if Connected and not Busy
    -> pool_disabled(State);
    true -> ok
  end,

  {reply, ok, State#state{enabled = false}, timeout(State)};

handle_call({enabled, true}, _From, #state{enabled = true} = State) ->
  {reply, false, State, timeout(State)};

handle_call({enabled, false}, _From, #state{enabled = false} = State) ->
  {reply, false, State, timeout(State)};

handle_call({state, N}, _From, State) ->
  {reply, element(N, State), State, timeout(State)};

handle_call(_Request, _From, State) ->
  ?D(_Request),
  {reply, unknown, State, timeout(State)}.


handle_cast({task_failed, Task, Stats}, #state{connected = true} = State) ->
  ?E({task_failed, Task}),
  fyler_event:task_failed(Task, Stats),
  {noreply, State, timeout(State)};

handle_cast({task_completed, Task, Stats}, #state{connected = true} = State) ->
  ?D({task_completed, Task}),
  fyler_event:task_completed(Task, Stats),
  {noreply, State, timeout(State)};


handle_cast({_, #task{}, #job_stats{}} = Data, #state{finished_tasks = Finished} = State) ->
  ?D({task_done}),
  {noreply, State#state{finished_tasks = [Data|Finished]}, timeout(State)};

handle_cast(_Request, State) ->
  ?D(_Request),
  {noreply, State, timeout(State)}.

handle_info(pool_accepted, #state{finished_tasks = Finished} = State) ->
  [gen_server:cast(self(), T) || T <- Finished],
  {noreply, State#state{connected = true, finished_tasks = []}, timeout(State)};

handle_info(connect_to_server, #state{server_node = Node, category = Category, enabled = Enabled,
  busy = Busy} = State) ->

  ?D({connecting_to_node, Node}),
  Connected = case net_kernel:connect_node(Node) of
                true ->
                  global:sync(),
                  {fyler_server, Node} ! {pool_connected, node(), Category, (Enabled and not Busy)},
                  pending;
                _ -> ?E(server_not_found),
                      erlang:send_after(?POLL_SERVER_TIMEOUT, self(), connect_to_server),
                      false
              end,
  {noreply, State#state{connected = Connected}, timeout(State)};

handle_info({try_task, _Task, Ref}, #state{category = Category, server_node = Server, buf_size = Size,
  max_buf_size = Size, enabled = false} = State) ->

  {fyler_server, Server} ! {task_rejected, Ref, node(), Category},
  {noreply, State, timeout(State)};

handle_info({try_task, _Task, Ref}, #state{category = Category, server_node = Server, buf_size = Size,
  max_buf_size = Size, busy = true} = State) ->

  {fyler_server, Server} ! {task_rejected, Ref, node(), Category},
  {noreply, State, timeout(State)};

handle_info({try_task, Task, Ref}, #state{tasks = Tasks, buf_size = BufSize, category = Category,
  server_node = Server, enabled = false} = State) ->

  {fyler_server, Server} ! {task_accepted, Ref, node(), Category},
  NewState = State#state{tasks = queue:in(Task, Tasks), buf_size = BufSize + 1},
  {noreply, NewState, timeout(NewState)};

handle_info({try_task, Task, Ref}, #state{tasks = Tasks, buf_size = BufSize, category = Category,
  server_node = Server, busy = true} = State) ->

  {fyler_server, Server} ! {task_accepted, Ref, node(), Category},
  NewState = State#state{tasks = queue:in(Task, Tasks), buf_size = BufSize + 1},
  {noreply, NewState, timeout(NewState)};

handle_info({try_task, Task, Ref}, #state{connected = Connected, tasks = Tasks, buf_size = BufSize,
  category = Category, server_node = Server} = State) ->

  {fyler_server, Server} ! {task_accepted, Ref, node(), Category},
  NewState = #state{busy = Busy} = next_task(State#state{tasks = queue:in(Task, Tasks), buf_size = BufSize + 1}),
  if
    Busy and Connected -> pool_disabled(NewState);
    true -> ok
  end,
  {noreply, NewState, timeout(NewState)};

handle_info({'DOWN', Ref, process, _Pid, Reason}, #state{connected = Connected, enabled = Enabled, max_active = Max,
  active_tasks = Active, pids = Pids, busy = Busy} = State) ->

  ?D({down, Reason}),
  NewActive = case lists:keyfind(Ref, #task.worker, Active) of
                #task{} = Task ->
                  cleanup_task_files(Task),
                  case Reason of
                    normal -> ok;
                    killed -> fyler_event:task_aborted(Task);
                    Other -> fyler_event:task_failed(Task, #job_stats{error_msg = Other})
                  end,
                  lists:keydelete(Ref, #task.worker, Active);
                _ -> Active
              end,
  NewState =
  if
    Enabled ->
      NewState_ = #state{busy = NewBusy} = next_task(State#state{active_tasks = NewActive}),
      if
        Connected and not NewBusy and Busy -> pool_enabled(NewState_);
        true -> ok
      end,
      NewState_;
    true ->
      NewBusy = length(NewActive) >= Max,
      State#state{active_tasks = NewActive, busy = NewBusy}
  end,
  {noreply, NewState#state{pids = maps:remove(Ref, Pids)}, timeout(NewState)};

handle_info({nodedown, Node}, #state{server_node = Node}=State) ->
  fyler_monitor:stop_monitor(),
  erlang:send_after(?POLL_SERVER_TIMEOUT, self(), connect_to_server),
  {noreply, State#state{connected = false}, timeout(State)};

handle_info(timeout, #state{connected = Connected, enabled = true, busy = false} = State) ->
  NewState = #state{busy = NewBusy} = next_task(State),
  if
    Connected and NewBusy -> pool_disabled(NewState);
    true -> ok
  end,
  {noreply, NewState, timeout(NewState)};

handle_info(timeout, State) ->
  {noreply, State, timeout(State)};

handle_info(Info, State) ->
  ?D(Info),
  {noreply, State, timeout(State)}.

terminate(shutdown, _State) ->
  ok;


terminate(_Reason, _State) ->
  ?D(_Reason),
  fyler_monitor:stop_monitor(),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%%% private functions %%%
cleanup_task_files(#task{file = #file{dir = Dir}})->
  ?D({cleanup, Dir}),
  ulitos_file:recursively_del_dir(Dir).

pool_enabled(#state{server_node = Server, category = Category}) ->
  ?D(pool_enabled),
  fyler_event:pool_enabled(node(), Category),
  {fyler_server, Server} ! {pool_enabled, node(), true}.

pool_disabled(#state{server_node = Server, category = Category}) ->
  ?D(pool_disabled),
  fyler_event:pool_disabled(node(), Category),
  {fyler_server, Server} ! {pool_enabled, node(), false}.

next_task(#state{buf_size = 0, active_tasks = Active, max_active = Max} = State) ->
  State#state{busy = length(Active) >= Max};

next_task(#state{max_active = Max, tasks = Tasks, buf_size = BufSize,
  active_tasks = Active, storage_dir = Dir, pids = Pids} = State) ->

  #task{file=#file{dir = UniqDir, tmp_path = Path} = File} = Task = queue:get(Tasks),
  TmpDir = filename:join(Dir, UniqDir),

  case filelib:ensure_dir(TmpDir ++ "/") of
    ok -> ok;
    {error, eexist} -> ok
  end,

  NewTask = Task#task{file = File#file{dir = TmpDir, tmp_path = filename:join(Dir, Path)}},
  {ok, Pid} = fyler_sup:start_worker(NewTask),
  Ref = erlang:monitor(process, Pid),
  NewActive = lists:keystore(Ref, #task.worker, Active, NewTask#task{worker = Ref}),
  Busy = length(NewActive) >= Max,
  NewPids = maps:put(Ref, Pid, Pids),
  State#state{active_tasks = NewActive, tasks = queue:drop(Tasks), buf_size = BufSize - 1, pids = NewPids, busy = Busy}.

timeout(#state{buf_size = 0}) ->
  infinity;

timeout(_) ->
  ?TRY_NEXT_TIMEOUT.


-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

-define(setup(F), {setup, fun setup_/0, fun cleanup_/1, F}).

-define(task(Id), #task{id = Id, file = #file{tmp_path = "file", dir = "test" ++ integer_to_list(Id), is_aws = true, url ="https://test.s3.amazonaws.com/test.smth"}, type = do_nothing, category=test}).
-define(failed_task(Id), #task{id=Id, file = #file{tmp_path = "file", dir = "fail_test" ++ integer_to_list(Id), is_aws = true, url ="https://test.s3.amazonaws.com/test.smth"}, type = do_fail, category=test}).


setup_() ->
  lager:start(),
  application:set_env(fyler, config, "fyler.config.test.pool"),
  application:set_env(fyler, max_active, 1),
  meck:new(aws_cli, [non_strict]),
  meck:expect(aws_cli, copy_folder, fun(_, _, _) -> timer:sleep(1000) end),
  meck:expect(aws_cli, copy_object, fun(_, _) -> timer:sleep(1000) end),
  meck:expect(aws_cli, dir_exists, fun(_) -> true end),
  filelib:ensure_dir("./tmp"),
  file:make_dir("./tmp"),
  file:write_file("./tmp/file", <<"0">>),
  fyler:start().

cleanup_(_) ->
  meck:unload(aws_cli),
  application:stop(lager),
  fyler:stop().

max_active_test_() ->
  [
    {"should have only one active task",
    ?setup(
      fun max_active_t_/1
      )
    },
    {"should not start new task after enabled if max active reached",
    ?setup(
      fun max_active_enabled_t_/1
      )
    },
    {"should start again after tasks empty",
    ?setup(
      fun max_active_again_t_/1
      )
    }
  ].

max_active_t_(_) ->
  fyler_pool:run_task(?task(1), make_ref()),
  fyler_pool:run_task(?task(2), make_ref()),
  fyler_pool:run_task(?task(3), make_ref()),
  [
    ?_assertEqual(1, length(gen_server:call(fyler_pool, {state, #state.active_tasks}))),
    ?_assertEqual(1, queue:len(gen_server:call(fyler_pool, {state, #state.tasks}))),
    ?_assertEqual(true, gen_server:call(fyler_pool, {state, #state.busy}))
  ].

max_active_enabled_t_(_) ->
  fyler_pool:run_task(?task(1), make_ref()),
  gen_server:call(fyler_pool, {enabled, false}),
  fyler_pool:run_task(?task(2), make_ref()),
  fyler_pool:run_task(?task(3), make_ref()),
  gen_server:call(fyler_pool, {enabled, true}),
  [
    ?_assertEqual(1, length(gen_server:call(fyler_pool, {state, #state.active_tasks}))),
    ?_assertEqual(1, queue:len(gen_server:call(fyler_pool, {state, #state.tasks})))
  ].

max_active_again_t_(_) ->
  fyler_pool:run_task(?task(1), make_ref()),
  fyler_pool:run_task(?task(2), make_ref()),
  timer:sleep(10000),
  fyler_pool:run_task(?task(2), make_ref()),
  [
    ?_assertEqual(1, length(gen_server:call(fyler_pool, {state, #state.active_tasks}))),
    ?_assertEqual(0, queue:len(gen_server:call(fyler_pool, {state, #state.tasks})))
  ].


failing_task_test_() ->
  [
    {"should handle worker 'DOWN' on system error",
    ?setup(
      fun system_fail_t_/1
      )
    }
  ].

system_fail_t_(_) ->
  fyler_pool:run_task(?failed_task(1), make_ref()),
  timer:sleep(5000),
  [
    ?_assertEqual(0, length(gen_server:call(fyler_pool, {state, #state.active_tasks}))),
    ?_assertEqual(0, queue:len(gen_server:call(fyler_pool, {state, #state.tasks})))
  ].

next_task_test_() ->
  [
    {"should return the same state",
    ?setup(
      fun next_task_empty_t_/1
      )
    },
    {"should choose one task",
      ?setup(
        fun next_task_t_/1
      )
    }
  ].

next_task_empty_t_(_) ->
  State1 = #state{buf_size = 0, active_tasks = [1], max_active = 1},
  State2 = #state{buf_size = 0, active_tasks = [], max_active = 1},
  ?_assertEqual(State1#state{busy = true}, next_task(State1)),
  ?_assertEqual(State2#state{busy = false}, next_task(State2)).

next_task_t_(_) ->
  State1 = #state{buf_size = 1, tasks = queue:in(?task(1), queue:new()), active_tasks = [], max_active = 1},
  ?_assertMatch(#state{busy = true, buf_size = 0, active_tasks = [_]}, next_task(State1)).

-endif.