%% Copyright
-module(fyler_server).
-author("palkan").
-include("../include/log.hrl").
-include("fyler.hrl").

-behaviour(gen_server).

%% API
-export([start_link/0]).

-export([run_task/3]).

%% gen_server
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).

%% API
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% gen_server callbacks
-record(state, {
  cowboy_pid :: pid(),
  listener ::pid(),
  storage_dir :: string(),
  tasks = [] :: list(task()),
  active_tasks = [] :: list(task())
}).

init(_Args) ->
  ?D("Starting fyler webserver"),
  Dir = ?Config(storage_dir, "tmp"),
  filelib:ensure_dir(Dir),

  {ok,Http} = start_http_server(),

  {ok,Events} = start_event_listener(),

  {ok, #state{cowboy_pid = Http, listener = Events, storage_dir = Dir}}.


%% @doc
%% Run new task.
%% @end

-spec run_task(string(), string(), list()) -> ok|false.

run_task(URL, Type, Options) ->
  gen_server:call(?MODULE, {run_task, URL, Type, Options}).


handle_call({run_task, URL, Type, Options}, _From, #state{storage_dir = Dir, tasks = Tasks} = State) ->
  case path_to_name_ext(URL) of
    {Name, Ext} ->
      TmpName = Dir ++ Name ++ "." ++ Ext,
      Task = #task{type = list_to_atom(Type), options = Options, file = #file{extension = Ext, url = URL, name = Name, tmp_path = TmpName}},
      fyler_monitor:start_monitor(),
      {ok, Pid} = fyler_sup:start_worker(Task),
      ?D({worker_sup, Pid}),
      Ref = erlang:monitor(process,Pid),
      NewTasks = lists:keystore(Ref,#task.worker,Tasks,Task#task{worker = Ref}),
      {reply, ok, State#state{tasks = NewTasks}};
    _ ->
      ?D({bad_url, URL}),
      {reply, false, State}
  end;


handle_call(_Request, _From, State) ->
  ?D(_Request),
  {reply, unknown, State}.

handle_cast(_Request, State) ->
  ?D(_Request),
  {noreply, State}.

handle_info({'DOWN',Ref,process,_Pid,normal}, #state{tasks = Tasks} = State) ->
  NewTasks = case lists:keyfind(Ref,#task.worker,Tasks) of
              #task{} -> lists:keydelete(Ref,#task.worker,Tasks);
               _ -> Tasks
             end,
  if length(NewTasks) == 0
    -> ?D(no_more_tasks),
       fyler_monitor:stop_monitor();
    true -> ok
  end,
  {noreply, State#state{tasks = NewTasks}};

handle_info({'DOWN',Ref,process,_Pid,{failed, Reason}}, #state{tasks = Tasks} = State) ->
  ?D({job_failed,Reason}),
  NewTasks = case lists:keyfind(Ref,#task.worker,Tasks) of
               #task{} -> lists:keydelete(Ref,#task.worker,Tasks);
               _ -> Tasks
             end,
  if length(NewTasks) == 0
    -> ?D(no_more_tasks),
    fyler_monitor:stop_monitor();
    true -> ok
  end,
  {noreply, State#state{tasks = NewTasks}};

handle_info(Info, State) ->
  ?D(Info),
  {noreply, State}.

terminate(_Reason, _State) ->
  ?D(_Reason),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


start_http_server() ->
  Dispatch = cowboy_router:compile([
    {'_', [
      {"/", index_handler, []},
      {"/api/tasks", task_handler, []},
      {'_', notfound_handler, []}
    ]}
  ]),
  Port = ?Config(http_port, 8008),
  cowboy:start_http(http_listener, 100,
    [{port, Port}],
    [{env, [{dispatch, Dispatch}]}]
  ).


start_event_listener() ->
  ?D(start_event_listener),
  Pid = spawn_link(fyler_event_listener, listen, []),
  {ok,Pid}.

path_to_name_ext(Path) ->
  {ok, Re} = re:compile("[^:]+://.+/([^/]+)\\.([^\\.]+)"),
  case re:run(Path, Re, [{capture, all, list}]) of
    {match, [_, Name, Ext]} ->
      {Name,Ext};
    _ ->
      false
  end.



-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").


path_to_test() ->
  ?assertEqual({"data", "ext"}, path_to_name_ext("http://qwe/data.ext")),
  ?assertEqual({"cpi", "txt"}, path_to_name_ext("http://dev2.teachbase.ru/app/cpi.txt")),
  ?assertEqual({"da.ta", "ext"}, path_to_name_ext("http://qwe/qwe/qwr/da.ta.ext")),
  ?assertEqual(false, path_to_name_ext("qwr/data.ext")).

-endif.
