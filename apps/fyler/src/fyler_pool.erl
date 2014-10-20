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

-export([run_task/1, cancel_task/1, disable/0, enable/0]).

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
  tasks = queue:new() :: queue:queue(task()),
  active_tasks = [] :: list(task()),
  finished_tasks = [] ::list({atom(),task(),stats()}),
  pids = #{} :: #{reference() => pid()}
}).

init(_Args) ->
  net_kernel:monitor_nodes(true),

  ?D("Starting fyler pool"),
  Dir = ?Config(storage_dir, "ff"),
  ok = filelib:ensure_dir(Dir),
  case file:make_dir(Dir) of
    ok -> ok;
    {error,eexist} -> ok
  end,
  
  Server = ?Config(server_name,null),
  ?D({server,Server}),

  self() ! connect_to_server,

  ulitos_app:ensure_loaded(?Handlers),

  Category = ?Config(category,undefined),
  case Category of
    video -> media:start();
    _ -> ok
  end,

  MaxActive = ?Config(max_active,1),

  lager:md([{context, {[{category, Category}, {max_active, MaxActive}]}}]),

  {ok, #state{storage_dir = Dir,  category = Category, server_node = Server, max_active = MaxActive}}.


%% @doc
%% Run new task.
%% @end

-spec run_task(task()) -> ok|false.

run_task(Task) ->
  gen_server:call(?MODULE, {run_task, Task}).

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


handle_call({run_task, Task}, _From, #state{enabled = Enabled, tasks = Tasks} = State) ->
  fyler_monitor:start_monitor(),
  NewTasks = queue:in(Task, Tasks),
  if Enabled
    -> self() ! try_next_task;
    true -> ok
  end,
  {reply, ok, State#state{tasks = NewTasks}};

handle_call({cancel_task, TaskId}, _From, #state{tasks = Tasks, active_tasks = Active, pids = Pids} = State) ->
  case lists:keyfind(TaskId, #task.id, Active) of
    #task{worker = Ref} ->
      Pid = maps:get(Ref, Pids),
      try fyler_sup:stop_worker(Pid)
      catch
        _:_ -> ok
      end,
      {reply, ok, State};
    _ ->
      {reply, ok, State#state{tasks = queue:filter(fun(#task{id = Id}) when Id == TaskId -> false; (_) -> true end, Tasks)}}
  end;

handle_call({enabled, true}, _From, #state{enabled = false, connected = Connected, busy = Busy} = State) ->
  if Connected and not Busy
    ->  
      erlang:send_after(?TRY_NEXT_TIMEOUT, self(), try_next_task),
      fyler_event:pool_enabled();
    true -> ok
  end,

  {reply, ok, State#state{enabled = true}};

handle_call({enabled, false}, _From, #state{enabled = true,connected = Connected} = State) ->

  if Connected
    ->  fyler_event:pool_disabled();
    true -> ok
  end,

  {reply, ok, State#state{enabled = false}};

handle_call({enabled, true}, _From, #state{enabled = true} = State) -> {reply, false, State};
handle_call({enabled, false}, _From, #state{enabled = false} = State) -> {reply, false, State};

handle_call({state, N}, _From, State) ->
  {reply,element(N,State),State};

handle_call(_Request, _From, State) ->
  ?D(_Request),
  {reply, unknown, State}.


handle_cast({task_failed,Task,Stats},#state{connected = true}=State) ->
  ?E({task_failed,Task}),
  fyler_event:task_failed(Task,Stats),
  {noreply,State};

handle_cast({task_completed,Task,Stats},#state{connected = true}=State) ->
  ?D({task_completed,Task}),
  fyler_event:task_completed(Task,Stats),
  {noreply,State};


handle_cast({_,#task{},#job_stats{}} = Data,#state{finished_tasks = Finished} = State) ->
  ?D({task_done}),
  {noreply,State#state{finished_tasks = [Data|Finished]}};

handle_cast(_Request, State) ->
  ?D(_Request),
  {noreply, State}.

handle_info(pool_accepted,#state{finished_tasks = Finished} = State) ->
  [gen_server:cast(self(),T) || T <- Finished],
  {noreply,State#state{connected = true, finished_tasks = []}};


handle_info(connect_to_server, #state{server_node = Node, category = Category, enabled = Enabled,active_tasks = Tasks, busy = Busy} = State) ->
  ?D({connecting_to_node, Node}),
  Connected = case net_kernel:connect_node(Node) of
                true ->
                  {fyler_server,Node} ! {pool_connected,node(),Category,(Enabled and not Busy),length(Tasks)},
                  pending;
                _ -> ?E(server_not_found),
                      erlang:send_after(?POLL_SERVER_TIMEOUT,self(),connect_to_server),
                      false
              end,
  {noreply,State#state{connected = Connected}};


handle_info(next_task, #state{tasks = Tasks, active_tasks = Active, storage_dir = Dir, pids = Pids} = State) ->
  case queue:out(Tasks) of
    {empty, _} ->
      {noreply, State};
    {{value, #task{file=#file{dir = UniqDir, tmp_path = Path}=File}=Task}, NewTasks} ->
      TmpDir = filename:join(Dir, UniqDir),

      case file:make_dir(TmpDir) of
        ok -> ok;
        {error, eexist} -> ok
      end,

      NewTask = Task#task{file=File#file{dir = TmpDir, tmp_path = filename:join(Dir,Path)}},
      {ok, Pid} = fyler_sup:start_worker(NewTask),
      Ref = erlang:monitor(process, Pid),
      NewActive = lists:keystore(Ref, #task.worker, Active, NewTask#task{worker = Ref}),
      {noreply, State#state{active_tasks = NewActive, tasks = NewTasks, pids = maps:put(Ref, Pid, Pids)}}
  end;


handle_info(try_next_task, #state{enabled = false} = State) ->
  {noreply, State};

handle_info(try_next_task, #state{max_active = Max, active_tasks = Active, connected = Connected, busy = Busy} = State) when Max =< length(Active) ->
  ?D({pool_is_busy}),
  if Connected and not Busy
    ->
      fyler_event:pool_disabled();
    true -> ok
  end,

  if not Busy
    ->
      erlang:send_after(?POOL_BUSY_TIMEOUT, self(), try_next_task);
    true -> ok
  end,

  {noreply, State#state{busy = true}};

handle_info(try_next_task, #state{tasks = Tasks, connected = Connected, busy = Busy} = State) ->
  Empty = queue:is_empty(Tasks),
  NewBusy =
    if Empty
      -> 
        if Connected and Busy
          -> 
            fyler_event:pool_enabled(),
            false;
          true -> Busy
        end;
      true -> 
        self() ! next_task,
        erlang:send_after(?TRY_NEXT_TIMEOUT, self(), try_next_task),
        Busy
    end,
  {noreply, State#state{busy = NewBusy}};


handle_info({'DOWN', Ref, process, _Pid, normal}, #state{enabled = Enabled, active_tasks = Active, pids = Pids} = State) ->
  ?D({down_normal}),
  NewActive = case lists:keyfind(Ref, #task.worker, Active) of
                #task{} = Task ->
                  cleanup_task_files(Task),
                  lists:keydelete(Ref, #task.worker, Active);
                _ -> Active
              end,
  if Enabled
    -> self() ! next_task;
    true -> ok
  end,
  {noreply, State#state{active_tasks = NewActive, pids = maps:remove(Ref, Pids)}};

handle_info({'DOWN', Ref, process, _Pid, killed}, #state{enabled = Enabled, active_tasks = Active, pids = Pids} = State) ->
  ?D({down_killed}),
  NewActive = case lists:keyfind(Ref, #task.worker, Active) of
                #task{} = Task ->
                  cleanup_task_files(Task),
                  lists:keydelete(Ref, #task.worker, Active);
                _ -> Active
              end,
  if Enabled
    -> self() ! next_task;
    true -> ok
  end,
  {noreply, State#state{active_tasks = NewActive, pids = maps:remove(Ref, Pids)}};

handle_info({'DOWN', Ref, process, _Pid, Other}, #state{enabled = Enabled, active_tasks = Active, pids = Pids} = State) ->
  ?D({donw, Other}),
  NewActive = case lists:keyfind(Ref, #task.worker, Active) of
                #task{} = Task -> 
                  cleanup_task_files(Task),
                  fyler_event:task_failed(Task, Other),
                  lists:keydelete(Ref, #task.worker, Active);
                _ -> Active
              end,
  if Enabled
    -> self() ! next_task;
    true -> ok
  end,
  {noreply, State#state{active_tasks = NewActive, pids = maps:remove(Ref, Pids)}};


handle_info({nodedown,Node},#state{server_node = Node}=State) ->
  fyler_monitor:stop_monitor(),
  erlang:send_after(?POLL_SERVER_TIMEOUT, self(), connect_to_server),
  {noreply,State#state{connected = false}};


handle_info(Info, State) ->
  ?D(Info),
  {noreply, State}.

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


-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

-define(setup(F), {setup, fun setup_/0, fun cleanup_/1, F}).

-define(task(Id), #task{id=Id, file=#file{tmp_path = "file", dir = "test"++integer_to_list(Id), is_aws = true, url ="https://test.s3.amazonaws.com/test.smth"}, type=do_nothing, category=test}).
-define(failed_task(Id), #task{id=Id, file=#file{tmp_path = "file", dir = "fail_test"++integer_to_list(Id), is_aws = true, url ="https://test.s3.amazonaws.com/test.smth"}, type=do_fail, category=test}).


setup_() ->
  lager:start(),
  application:set_env(fyler,config,"fyler.config.test.pool"),
  application:set_env(fyler,max_active,1),
  meck:new(aws_cli,[non_strict]),
  meck:expect(aws_cli, copy_folder, fun(_,_) -> timer:sleep(2000) end),
  meck:expect(aws_cli, copy_object, fun(_,_) -> timer:sleep(2000) end),
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
    }
  ].

max_active_t_(_) ->
  fyler_pool:run_task(?task(1)),
  fyler_pool:run_task(?task(2)),
  fyler_pool:run_task(?task(3)),
  [
    ?_assertEqual(1, length(gen_server:call(fyler_pool,{state, #state.active_tasks}))),
    ?_assertEqual(2, queue:len(gen_server:call(fyler_pool,{state, #state.tasks}))),
    ?_assertEqual(true, gen_server:call(fyler_pool,{state, #state.busy}))
  ].

max_active_enabled_t_(_) ->
  fyler_pool:run_task(?task(1)),
  gen_server:call(fyler_pool, {enabled,false}),
  fyler_pool:run_task(?task(2)),
  fyler_pool:run_task(?task(3)),
  gen_server:call(fyler_pool, {enabled,true}),
  [
    ?_assertEqual(1, length(gen_server:call(fyler_pool,{state, #state.active_tasks}))),
    ?_assertEqual(2, queue:len(gen_server:call(fyler_pool,{state, #state.tasks})))
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
  fyler_pool:run_task(?failed_task(1)),
  timer:sleep(5000),
  [
    ?_assertEqual(0, length(gen_server:call(fyler_pool,{state, #state.active_tasks}))),
    ?_assertEqual(0, queue:len(gen_server:call(fyler_pool,{state, #state.tasks})))
  ].

-endif.