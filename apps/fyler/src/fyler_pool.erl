%% Copyright
-module(fyler_pool).
-author("palkan").
-include("../include/log.hrl").
-include("../include/handlers.hrl").
-include("fyler.hrl").

-behaviour(gen_server).

-define(TRY_NEXT_TIMEOUT, 1500).
-define(POLL_SERVER_TIMEOUT, 30000).


-define(APPS, [os_mon]).

%% API
-export([start_link/0]).

-export([run_task/1, disable/0, enable/0]).

%% gen_server
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).

%% API
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% gen_server callbacks
-record(state, {
  enabled = true :: boolean(),
  server_node ::atom(),
  connected = false ::false|true|pending,
  storage_dir :: string(),
  aws_bucket :: string(),
  tasks = queue:new() :: queue(),
  active_tasks = [] :: list(task()),
  finished_tasks = [] ::list({atom(),task(),stats()})
}).

init(_Args) ->
  net_kernel:monitor_nodes(true),
  ulitos_app:ensure_started(?APPS),
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

  {ok, #state{storage_dir = Dir ++ "/",  server_node = Server}}.


%% @doc
%% Run new task.
%% @end

-spec run_task(task()) -> ok|false.

run_task(Task) ->
  gen_server:call(?MODULE, {run_task, Task}).

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
  NewTasks = queue:in(Task, Tasks),
  if Enabled
    -> self() ! next_task;
    true -> ok
  end,
  {reply, ok, State#state{tasks = NewTasks}};

handle_call({enabled, true}, _From, #state{enabled = false, connected = Connected} = State) ->
  self() ! next_task,
  erlang:send_after(?TRY_NEXT_TIMEOUT, self(), try_next_task),

  if Connected
    ->  fyler_event:pool_enabled();
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

handle_call({move_to_aws, Bucket, DirName, []}, _From, State) ->
  Start = ulitos:timestamp(),
  aws_cli:copy_folder(DirName, "s3://" ++ Bucket ++ "/" ++ DirName),
  {reply, ulitos:timestamp() - Start, State};

handle_call({move_to_aws, Bucket, DirName,TargetDir}, _From, State) ->
  Start = ulitos:timestamp(),
  aws_cli:copy_folder(DirName, "s3://" ++ Bucket ++ "/" ++ TargetDir),
  {reply, ulitos:timestamp() - Start, State};

handle_call(_Request, _From, State) ->
  ?D(_Request),
  {reply, unknown, State}.


handle_cast({task_failed,Task,Stats},#state{connected = true}=State) ->
  ?D({task_failed,Task}),
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


handle_info(connect_to_server, #state{server_node = Node,enabled = Enabled,active_tasks = Tasks} = State) ->
  Connected = case net_kernel:connect(Node) of
                true ->
                  {fyler_server,Node} ! {pool_connected,node(),Enabled,length(Tasks)},
                  pending;
                _ -> ?D(server_no_found),
                      erlang:send_after(?POLL_SERVER_TIMEOUT,self(),connect_to_server),
                      false
              end,
  {noreply,State#state{connected = Connected}};


handle_info(next_task, #state{tasks = Tasks, active_tasks = Active} = State) ->
  {NewTasks, NewActive} = case queue:out(Tasks) of
                            {empty, _} -> fyler_monitor:stop_monitor(),
                              {Tasks, Active};
                            {{value, #task{file=#file{dir = Dir}}=Task}, Tasks2} -> fyler_monitor:start_monitor(),
                              ok = file:make_dir(Dir),
                              {ok, Pid} = fyler_sup:start_worker(Task),
                              Ref = erlang:monitor(process, Pid),
                              Active2 = lists:keystore(Ref, #task.worker, Active, Task#task{worker = Ref}),
                              {Tasks2, Active2}
                          end,
  {noreply, State#state{active_tasks = NewActive, tasks = NewTasks}};


handle_info(try_next_task, #state{enabled = false} = State) ->
  {noreply, State};

handle_info(try_next_task, #state{tasks = Tasks} = State) ->
  Empty = queue:is_empty(Tasks),
  if Empty
    -> ok;
    true -> self() ! next_task,
      erlang:send_after(?TRY_NEXT_TIMEOUT, self(), try_next_task)
  end,
  {noreply, State};


handle_info({'DOWN', Ref, process, _Pid, normal}, #state{enabled = Enabled, active_tasks = Active} = State) ->
  NewActive = case lists:keyfind(Ref, #task.worker, Active) of
                #task{} -> lists:keydelete(Ref, #task.worker, Active);
                _ -> Active
              end,
  if Enabled
    -> self() ! next_task;
    true -> ok
  end,
  {noreply, State#state{active_tasks = NewActive}};

handle_info({'DOWN', Ref, process, _Pid, Other}, #state{enabled = Enabled, active_tasks = Active} = State) ->
  NewActive = case lists:keyfind(Ref, #task.worker, Active) of
                #task{} = Task -> fyler_event:task_failed(Task, Other),
                  lists:keydelete(Ref, #task.worker, Active);
                _ -> Active
              end,
  if Enabled
    -> self() ! next_task;
    true -> ok
  end,
  {noreply, State#state{active_tasks = NewActive}};


handle_info({nodedown,Node},#state{server_node = Node}=State) ->
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

