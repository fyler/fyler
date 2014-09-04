%% Copyright
-module(fyler_server).
-author("palkan").
-include("../include/log.hrl").
-include("fyler.hrl").

-behaviour(gen_server).

-define(TRY_NEXT_TIMEOUT, 1500).

%% Maximum time for waiting any pool to become enabled.
-define(IDLE_TIME_WM, 60000).

%% Limit on queue length. If it exceeds new pool instance should be started.
-define(QUEUE_LENGTH_WM, 30).


%% store session info
-define(T_SESSIONS, fyler_auth_sessions).

-define(SESSION_EXP_TIME, 300000).

-define(APPS, [ranch, cowlib, cowboy, mimetypes, ibrowse]).

%% API
-export([start_link/0]).

-export([run_task/3, clear_stats/0, pools/0, current_tasks/0, send_response/3, authorize/2, is_authorized/1, tasks_stats/0, save_task_stats/1]).

%% gen_server
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).


-record(ets_session, {
  session_id :: string(),
  expiration_date :: non_neg_integer()
}).


%% gen_server callbacks
-record(state, {
  cowboy_pid :: pid(),
  aws_bucket :: string(),
  aws_dir :: string(),
  pool_nodes = #{} ::#{atom() => atom()},
  busy_timers = #{},
  tasks_count = 1 :: non_neg_integer(),
  tasks = #{} ::#{atom() => queue:queue(task())}
}).


%% API
start_link() ->
  ?D("Starting fyler webserver"),
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init(_Args) ->

  net_kernel:monitor_nodes(true),

  ulitos_app:ensure_started(?APPS),

  ?D("fyler webserver started"),

  ets:new(?T_STATS, [public, named_table, {keypos, #current_task.id}]),

  ets:new(?T_POOLS, [public, named_table, {keypos, #pool.node}]),

  ets:new(?T_SESSIONS, [private, named_table, {keypos, #ets_session.session_id}]),

  Http = case start_http_server() of
    {ok,Pid} -> Pid;
    {error, {already_started, Pid_}} -> Pid_
  end,

  Buckets = ?Config(aws_s3_bucket, []),

  AwsDir = ?Config(aws_dir, "fyler/"),

  ?I({server_start, AwsDir, Buckets}),

  {ok, #state{cowboy_pid = Http, aws_bucket = Buckets, aws_dir = AwsDir}}.


%% @doc
%% Authorize user and create new session
%% @end


-spec authorize(Login :: binary(), Pass :: binary()) -> false|{ok, Token :: string()}.

authorize(Login, Pass) ->
  case ?Config(auth_pass, null) of
    null -> gen_server:call(?MODULE, create_session);
    PassHash -> L = ?Config(auth_login, none),
      case ulitos:binary_to_hex(crypto:hash(md5, binary_to_list(Pass))) == PassHash andalso binary_to_list(Login) == L of
        true -> gen_server:call(?MODULE, create_session);
        _ -> false
      end
  end.


%% @doc
%% @end

-spec is_authorized(Token :: binary()) -> boolean().

is_authorized(Token) ->
  gen_server:call(?MODULE, {is_authorized, binary_to_list(Token)}).


%% @doc
%% Remove all records from statistics ets.
%% @end

-spec clear_stats() -> true.

clear_stats() ->
  ets:delete_all_objects(?T_STATS).


%% @doc
%% Return list of pools
%% @end

pools() ->
  [fyler_utils:pool_to_proplist(Pool) || Pool <- gen_server:call(?MODULE, pools)].

%% @doc
%% Return list of pools available
%% @end

current_tasks() ->
  [fyler_utils:current_task_to_proplist(Task) || Task <- ets:tab2list(?T_STATS)].


%% @doc
%% Return a list of last 50 tasks completed as #job_stats{}.
%% @end

-spec tasks_stats() -> list(#job_stats{}).

tasks_stats() ->
  Values = case pg_cli:equery("select * from tasks order by id desc limit 50") of
             {ok, _, List} -> List;
             Other -> ?D({pg_query_failed, Other})
           end,
  [fyler_utils:stats_to_proplist(fyler_utils:task_record_to_proplist(V)) || V <- Values].


%% @doc
%% Save task statistics to pg
%% @end

-spec save_task_stats(#job_stats{}) -> any().

save_task_stats(#job_stats{} = Stats) ->
  ValuesString = fyler_utils:stats_to_pg_string(Stats),
  case pg_cli:equery("insert into tasks (status,download_time,upload_time,file_size,file_path,time_spent,result_path,task_type,error_msg) values (" ++ ValuesString ++ ")") of
    {ok, _} -> ok;
    Other -> ?D({pg_query_failed, Other})
  end.


%% @doc
%% Run new task.
%% @end

-spec run_task(string(), string(), list()) -> ok|false.

run_task(URL, Type, Options) ->
  gen_server:call(?MODULE, {run_task, URL, Type, Options}).


handle_call({run_task, URL, Type, Options}, _From, #state{tasks = Tasks, aws_bucket = Buckets, aws_dir = AwsDir, tasks_count = TCount} = State) ->
  case parse_url(URL, Buckets) of
    {true, Bucket, Path, Name, Ext} ->
      %% generate temp uniq name
      UniqueDir = uniqueId() ++ "_" ++ Name,
      TmpName = filename:join(UniqueDir, Name ++ "." ++ Ext),

      ?D(Options),

      Callback = proplists:get_value(callback, Options, undefined),
      TargetDir = case proplists:get_value(target_dir, Options) of
                    undefined -> filename:join(AwsDir,UniqueDir);
                    TargetDir_ -> case parse_url_dir(binary_to_list(TargetDir_), Buckets) of
                                    {true, TargetPath} -> TargetPath;
                                    _ -> ?D({wrong_target_dir, TargetDir_}), filename:join(AwsDir,UniqueDir)
                                  end
                  end,

      Handler = list_to_atom(Type),

      Category = erlang:apply(Handler,category,[]),

      Task = #task{id = TCount, type = Handler, category = Category, options = Options, callback = Callback, file = #file{extension = Ext, target_dir = TargetDir, bucket = Bucket, is_aws = true, url = Path, name = Name, dir = UniqueDir, tmp_path = TmpName}},
      
      NewTasks = add_task(Task, Tasks),

      Len = queue:len(maps:get(Category,NewTasks)),

      if Len > ?QUEUE_LENGTH_WM
        -> self() ! {alarm_too_many_tasks, Category};
        true -> ok
      end, 

      ets:insert(?T_STATS, #current_task{id = TCount, type = list_to_atom(Type), url = Path, status = queued}),

      self() ! {try_next_task, Category},

      {reply, ok, State#state{tasks = NewTasks, tasks_count = TCount + 1}};
    _ -> ?D({bad_url, URL, Buckets}),
      {reply, false, State}
  end;

handle_call(tasks,_From,#state{tasks = Tasks}=State) ->
  {reply, Tasks, State};

handle_call(create_session, _From, #state{} = State) ->
  random:seed(now()),
  Token = ulitos:random_string(16),
  ets:insert(?T_SESSIONS, #ets_session{expiration_date = ulitos:timestamp() + ?SESSION_EXP_TIME, session_id = Token}),
  erlang:send_after(?SESSION_EXP_TIME, self(), {session_expired, Token}),
  {reply, {ok, Token}, State};

handle_call({is_authorized, Token}, _From, #state{} = State) ->
  Reply = case ets:lookup(?T_SESSIONS, Token) of
            [#ets_session{}] -> true;
            _ -> {false,<<"">>}
          end,
  {reply, Reply, State};


handle_call(pools, _From, State) ->
  {reply, ets:tab2list(?T_POOLS), State};


handle_call(_Request, _From, State) ->
  ?D(_Request),
  {reply, unknown, State}.


handle_cast({pool_enabled, Node, Enabled}, State) ->
  ?D({pool_enabled, Node}),
  case ets:lookup(?T_POOLS,Node) of
    [#pool{category = Category} = Pool] ->
      if Enabled 
        -> self() ! {try_next_task, Category};
        true -> ok
      end,
      ets:insert(?T_POOLS, Pool#pool{enabled = Enabled}),
      {noreply, State};
    _ -> {noreply, State}
  end;

handle_cast({task_finished, Node}, State) ->
  decriment_tasks_num(Node),
  {noreply, State};

handle_cast(_Request, State) ->
  ?D(_Request),
  {noreply, State}.

handle_info({session_expired, Token}, State) ->
  ets:delete(?T_SESSIONS, Token),
  {noreply, State};

handle_info({pool_connected, Node, Category, Enabled, Num}, #state{tasks = Tasks} = State) ->
  ?D({pool_connected, Node, Category, Enabled, Num}),
  Pool = #pool{node = Node, active_tasks_num = Num, category = Category, enabled = Enabled},

  {fyler_pool, Node} ! pool_accepted,

  NewTasks = case ets:lookup(?T_POOLS,Node) of
    [#pool{}] -> handle_dead_pool(Node,Tasks);
    _ -> Tasks
  end,

  ets:insert(?T_POOLS, Pool),
  if Enabled 
    ->  
      self() ! {try_next_task, Category};
    true -> ok
  end,
  {noreply, State#state{tasks = NewTasks}};

handle_info({try_next_task, Category}, #state{tasks = Tasks, busy_timers = Timers}=State) ->
  List = maps:get(Category,Tasks,queue:new()),
  {NewTasks,NewTimers,NewList} = case queue:out(List) of
    {empty, _} -> ?D(no_more_tasks),
                  {Tasks,Timers,List};
    {{value, #task{id = TaskId, type = TaskType, file = #file{url = TaskUrl}} = Task}, List2} ->
      case choose_pool(Category) of
        #pool{node = Node, active_tasks_num = Num, total_tasks = Total} = Pool ->
          send_to_pool(Node,Task),
          ets:insert(?T_STATS, #current_task{id = TaskId, task = Task, type = TaskType, url = TaskUrl, pool = Node, status = progress}),
          ets:insert(?T_POOLS, Pool#pool{active_tasks_num = Num + 1, total_tasks = Total + 1}),
          Timers_ = remove_timer(Category,Timers),
          {maps:update(Category,List2,Tasks),Timers_,List2};
        _ -> 
          Timers_ = add_timer(Category,Timers),
          {Tasks, Timers_,List2}
      end
  end,
  Empty = queue:is_empty(NewList),
  if Empty
    -> ok;
    true -> erlang:send_after(?TRY_NEXT_TIMEOUT, self(), try_next_task)
  end,
  {noreply, State#state{tasks=NewTasks, busy_timers = NewTimers}};

handle_info({alarm_high_idle_time, Type}, State) ->
  ?E({high_idle_time,Type}),
  {noreply, State};

handle_info({alarm_too_many_tasks, Type}, State) ->
  ?E({too_many_tasks,Type}),
  {noreply, State};

handle_info({nodedown, Node}, #state{tasks = Tasks} = State) ->
  ?D({nodedown, Node}),
  NewTasks = case ets:lookup(?T_POOLS, Node) of 
    [#pool{}] ->
      handle_dead_pool(Node,Tasks);
    _ -> 
      ?D({unknown_node, Node}),
      Tasks
  end,
  {noreply, State#state{tasks = NewTasks}};

handle_info(Info, State) ->
  ?D(Info),
  {noreply, State}.

terminate(_Reason,_State) ->
  ?D(_Reason),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

handle_dead_pool(Node,Tasks) ->
  ets:delete(?T_POOLS,Node),
  case ets:match_object(?T_STATS, #current_task{pool = Node, _ = '_'}) of
    [] -> 
      ?I({"No active tasks in dead pool",Node}), 
      Tasks;
    Tasks_ -> 
      ?I({"Pool died with active tasks; restarting...",Node}),
      Tasks2 = restart_tasks(Tasks_, Tasks),
      [self() ! {try_next_task, Category} || Category <- maps:keys(Tasks2)],
      Tasks2
  end.

%% @doc Send task to remote pool
send_to_pool(Node,Task) ->
  rpc:cast(Node, fyler_pool, run_task, [Task]).

%% @doc
%% Send response to task initiator as HTTP Post with params <code>status = success|failed</code> and <code>path</code - path to download file if success.
%% @end

-spec send_response(task(), stats(), success|failed) -> ok|list()|binary().

send_response(#task{callback = undefined}, _, _) ->
  ok;

send_response(#task{callback = Callback, file = #file{is_aws = true, bucket = Bucket, target_dir = Dir}}, #job_stats{result_path = Path}, success) ->
  ibrowse:send_req(binary_to_list(Callback), [{"Content-Type", "application/x-www-form-urlencoded"}], post, "status=ok&aws=true&bucket=" ++ Bucket ++ "&data=" ++ jiffy:encode({[{path, Path}, {dir, list_to_binary(Dir)}]}), []);

send_response(#task{callback = Callback}, _, failed) ->
  ibrowse:send_req(binary_to_list(Callback), [{"Content-Type", "application/x-www-form-urlencoded"}], post, "status=failed", []).

start_http_server() ->
  Dispatch = cowboy_router:compile([
    {'_', [
      {"/", index_handler, []},
      {"/stats", stats_handler, []},
      {"/tasks", tasks_handler, []},
      {"/pools", pools_handler, []},
      {"/api/auth", auth_handler, []},
      {"/api/tasks", task_handler, []},
      {'_', notfound_handler, []}
    ]}
  ]),
  Port = ?Config(http_port, 8008),
  cowboy:start_http(http_listener, 100,
    [{port, Port}],
    [{env, [{dispatch, Dispatch}]}]
  ).


%% @doc
%% Choose pool by type.
%% @end

-spec choose_pool(atom()) -> #pool{}|undefined.

choose_pool(Type) ->
  choose_pool_from_list(ets:match_object(?T_POOLS, #pool{category = Type, enabled = true, _ = '_'})).

choose_pool_from_list([]) ->
  undefined;

choose_pool_from_list(Pools) ->
  hd(lists:keysort(#pool.total_tasks, Pools)).


add_timer(Type,Timers) ->
  case maps:find(Type,Timers) of
    error ->  Ref = erlang:send_after(?IDLE_TIME_WM, self(), {alarm_high_idle_time, Type}),
              maps:put(Type,Ref,Timers);
    _ -> Timers
  end.

remove_timer(Type,Timers) ->
  case maps:find(Type,Timers) of
    error ->  Timers;
    {_,Ref} -> erlang:cancel_timer(Ref),
              maps:remove(Type,Timers)
  end.

%% @doc
%% Add task to category queue
%% @end

-spec add_task(task(),map()) -> map().

add_task(#task{category = Cat}=Task,Tasks) ->
  case maps:find(Cat,Tasks) of
    error -> maps:put(Cat,queue:from_list([Task]),Tasks);
    {ok, Q} -> maps:update(Cat,queue:in(Task,Q),Tasks)
  end.

%% @doc
%% Add tasks to the queue again.
%% @end

-spec restart_tasks(list(#current_task{}), map()) -> map().

restart_tasks([], Tasks) -> ?I("All tasks restarted."), Tasks;

restart_tasks([#current_task{task = Task}|T], Old) ->
  ?D({restarting_task, Task}),
  restart_tasks(T, add_task(Task,Old)).


-spec decriment_tasks_num(atom()) -> N::non_neg_integer()|false.

decriment_tasks_num(Node) ->
  case ets:lookup(?T_POOLS, Node) of
    [#pool{active_tasks_num = N} = Pool] when N > 0 ->
      ets:insert(?T_POOLS, Pool#pool{active_tasks_num = N-1}),
      N-1;
    _ -> false
  end.

%%% @doc
%%% @end

-spec parse_url(string(),list(string())) -> {IsAws::boolean(),Bucket::string()|boolean(), Path::string(),Name::string(),Ext::string()}.

parse_url(Path, Buckets) ->
  {ok, Re} = re:compile("[^:]+://.+/([^/]+)\\.([^\\.]+)"),
  case re:run(Path, Re, [{capture, all, list}]) of
    {match, [_, Name, Ext]} ->
      {ok, Re2} = re:compile("[^:]+://([^\\.]+)\\.s3[^\\.]*\\.amazonaws\\.com/(.+)"),
      {IsAws, Bucket,Path2} = case re:run(Path, Re2, [{capture, all, list}]) of
        {match, [_, Bucket_, Path_]} ->
          {true, Bucket_, Path_};
        _ -> {ok, Re3} = re:compile("[^:]+://s3[^\\.]*\\.amazonaws\\.com/([^/]+)/(.+)"),
          case re:run(Path, Re3, [{capture, all, list}]) of
            {match, [_, Bucket_, Path_]} -> {true, Bucket_, Path_};
            _ -> {false, false, Path}
          end
      end,

      case IsAws of
        false -> {false,false,Path,Name,Ext};
        _ -> case lists:member(Bucket,Buckets) of
               true -> {true,Bucket,Bucket++"/"++Path2,Name,Ext};
               false -> {false,false,Path,Name,Ext}
             end
      end;
    _ ->
      false
  end.


parse_url_dir(Path, Bucket) ->
  {ok, Re2} = re:compile("[^:]+://" ++ Bucket ++ "\\.s3\\.amazonaws\\.com/(.+)"),
  case re:run(Path, Re2, [{capture, all, list}]) of
    {match, [_, Path2]} -> {true, Path2};
    _ -> {ok, Re3} = re:compile("[^:]+://([^/\\.]+).s3\\-[^\\.]+\\.amazonaws\\.com/(.+)"),
      case re:run(Path, Re3, [{capture, all, list}]) of
        {match, [_, Bucket, Path2]} -> {true, Path2};
        _ -> {false, Path}
      end
  end.

-spec uniqueId() -> string().

uniqueId() ->
  {Mega, S, Micro} = erlang:now(),
  integer_to_list(Mega * 1000000000000 + S * 1000000 + Micro).



-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

-define(setup(F), {setup, fun setup_/0, fun cleanup_/1, F}).

path_to_test() ->
  ?assertEqual({false, false, "http://qwe/data.ext", "data", "ext"}, parse_url("http://qwe/data.ext", [])),
  ?assertEqual({false, false, "http://dev2.teachbase.ru/app/cpi.txt", "cpi", "txt"}, parse_url("http://dev2.teachbase.ru/app/cpi.txt", [])),
  ?assertEqual({false, false, "https://qwe/qwe/qwr/da.ta.ext", "da.ta", "ext"}, parse_url("https://qwe/qwe/qwr/da.ta.ext", ["qwo"])),
  ?assertEqual({true, "qwe", "qwe/da.ta.ext", "da.ta", "ext"}, parse_url("http://qwe.s3-eu-west-1.amazonaws.com/da.ta.ext", ["qwe"])),
  ?assertEqual({true, "qwe", "qwe/da.ta.ext", "da.ta", "ext"}, parse_url("https://s3-eu-west-1.amazonaws.com/qwe/da.ta.ext", ["qwe"])),
  ?assertEqual({true, "qwe", "qwe/da.ta.ext", "da.ta", "ext"}, parse_url("http://qwe.s3.amazonaws.com/da.ta.ext", ["qwe", "qwo"])),
  ?assertEqual({true, "qwe", "qwe/path/to/object/da.ta.ext", "da.ta", "ext"}, parse_url("http://qwe.s3-eu-west-1.amazonaws.com/path/to/object/da.ta.ext", ["qwe"])),
  ?assertEqual({false, false, "http://qwe.s3-eu-west-1.amazonaws.com/path/to/object/da.ta.ext", "da.ta", "ext"}, parse_url("http://qwe.s3-eu-west-1.amazonaws.com/path/to/object/da.ta.ext", "q")),
  ?assertEqual(false, parse_url("qwr/data.ext", [])).


dir_url_test() ->
  ?assertEqual({true, "recordings/2/record_17/stream_1/"}, parse_url_dir("https://devtbupload.s3.amazonaws.com/recordings/2/record_17/stream_1/", "devtbupload")),
  ?assertEqual({true, "recordings/2/record_17/stream_1/"}, parse_url_dir("http://devtbupload.s3-eu-west-1.amazonaws.com/recordings/2/record_17/stream_1/", "devtbupload")),
  ?assertEqual({false, "https://2.com/record_17/stream_1/"}, parse_url_dir("https://2.com/record_17/stream_1/", "devtbupload")).

restart_task_test() ->
  Tasks = [
    #current_task{task = #task{id=1, category = test}},
    #current_task{task = #task{id=2, category = video}},
    #current_task{task = #task{id=3, category = docs}}
  ],
  NewTasks = restart_tasks(Tasks, #{docs => queue:from_list([#task{id=5, category = docs}])}),
  ?assertEqual(1, queue:len(maps:get(test,NewTasks))),
  ?assertEqual(1, queue:len(maps:get(video,NewTasks))),
  ?assertEqual(2, queue:len(maps:get(docs,NewTasks))).

setup_() ->
  lager:start(),
  application:set_env(fyler,config,"fyler.config.test"),
  fyler:start().

cleanup_(_) ->
  application:stop(lager),
  fyler:stop().

authorization_test_() ->
  [{"Authorization test",
    ?setup(
      fun(_) ->
        {inorder,
          [
            add_session_t_(),
            wrong_login_t_(),
            wrong_pass_t_(),
            is_authorized_t_(),
            is_authorized_failed_t_()
          ]
        }
      end
    )
  }].

add_session_t_() ->
  P = "test",
  ?_assertMatch({ok, _}, fyler_server:authorize(list_to_binary(?Config(auth_login, "")), list_to_binary(P))).


wrong_login_t_() ->
  P = "test",
  ?_assertEqual(false, fyler_server:authorize(<<"badlogin">>, list_to_binary(P))).

wrong_pass_t_() ->
  P = "wqe",
  ?_assertEqual(false, fyler_server:authorize(?Config(auth_login, ""), list_to_binary(P))).

is_authorized_t_() ->
  P = "test",
  {ok, Token} = fyler_server:authorize(list_to_binary(?Config(auth_login, "")), list_to_binary(P)),
  ?_assertEqual(true, fyler_server:is_authorized(list_to_binary(Token))).

is_authorized_failed_t_() ->
  ?_assertMatch({false,_}, fyler_server:is_authorized(<<"123456">>)).


pools_ets_test_() ->
  [
    {"add pool",
    ?setup(
      fun add_pool_t_/1
      )
    },
    {"choose pool",
    ?setup(
      fun choose_pool_t_/1
      )
    },
    {"decr tasks",
    ?setup(
      fun decriment_tasks_num_t_/1
      )
    },
    {"remove pool",
    ?setup(
      fun remove_pool_t_/1
      )
    },
    {"pools list",
    ?setup(
      fun pools_list_t_/1
      )
    }
  ].

add_pool_t_(_) ->
  fyler_server ! {pool_connected, test, docs, true, 11},
  [
    ?_assertEqual(1, length(ets:tab2list(?T_POOLS)))
  ].

decriment_tasks_num_t_(_) ->
  ets:insert(?T_POOLS, #pool{active_tasks_num = 12, node = test}),
  [
    ?_assertEqual(11, decriment_tasks_num(test))
  ].

choose_pool_t_(_) ->
  ets:insert(?T_POOLS, #pool{total_tasks = 2, node = test, category = docs, enabled = true}),
  ets:insert(?T_POOLS, #pool{total_tasks = 12, node = test2, category = docs, enabled = true}),
  ets:insert(?T_POOLS, #pool{node = test3, category = docass, enabled = false}),
  ets:insert(?T_POOLS, #pool{total_tasks = 0, node = test4, category = docs, enabled = false}),
  [
    ?_assertMatch(#pool{node=test}, choose_pool(docs)),
    ?_assertEqual(undefined, choose_pool(docass))
  ].

remove_pool_t_(_) ->
  fyler_server ! {nodedown, test},
  [
    ?_assertEqual(0, length(ets:lookup(?T_POOLS,test)))
  ].

pools_list_t_(_) ->
  ets:insert(?T_POOLS, #pool{total_tasks = 2, node = test, category = docs, enabled = true}),
  ets:insert(?T_POOLS, #pool{total_tasks = 12, node = test2, category = docs, enabled = true}),
  ets:insert(?T_POOLS, #pool{node = test3, category = docass, enabled = false}),
  Pools = fyler_server:pools(),
  [
    ?_assertEqual(2, proplists:get_value(total, lists:last(Pools))),
    ?_assertEqual(docass, proplists:get_value(category, hd(Pools))) 
  ].

tasks_test_() ->
  [
    {"add task",
    ?setup(
      fun add_task_t_/1
      )
    },
    {"task finished",
    ?setup(
      fun task_finished_t_/1
      )
    },
    {
      "run task",
      ?setup(
        fun run_task_t_/1
      )
    }
  ].

add_task_t_(_) ->
  Res = fyler_server:run_task("https://test.s3.amazonaws.com/test.smth", "do_nothing", [{target_dir, <<"target/dir">>},{callback, <<"call_me.php">>}]),
  [
    ?_assertEqual(ok,Res),
    ?_assertEqual(1, queue:len(maps:get(test,gen_server:call(fyler_server,tasks))))
  ].

task_finished_t_(_) ->
  ets:insert(?T_POOLS, #pool{active_tasks_num = 1, total_tasks = 2, node = testf, category = docs, enabled = true}),
  gen_server:cast(fyler_server, {task_finished, testf}),
  [
    ?_assertMatch([#pool{active_tasks_num = 0}], ets:lookup(?T_POOLS, testf))
  ].

run_task_t_(_) ->
  [
    ?_assertEqual(ok, fyler_server:run_task("https://s3-eu-west-1.amazonaws.com/test/10.xls","do_nothing",[]))
  ].
%%% handlers specs %%%

do_nothing_test() ->
  ?assertEqual(test, do_nothing:category()).

doc_to_pdf_test() ->
  ?assertEqual(document, doc_to_pdf:category()).

doc_to_pdf_swf_test() ->
  ?assertEqual(document, doc_to_pdf_swf:category()).

doc_to_pdf_thumbs_test() ->
  ?assertEqual(document, doc_to_pdf_thumbs:category()).

pdf_split_pages_test() ->
  ?assertEqual(document, pdf_split_pages:category()).

pdf_to_swf_test() ->
  ?assertEqual(document, pdf_to_swf:category()).

pdf_to_swf_thumbs_test() ->
  ?assertEqual(document, pdf_to_swf_thumbs:category()).

pdf_to_thumbs_test() ->
  ?assertEqual(document, pdf_to_thumbs:category()).

split_pdf_test() ->
  ?assertEqual(document, split_pdf:category()).

recording_to_hls_test() ->
  ?assertEqual(video, recording_to_hls:category()).

video_to_mp4_test() ->
  ?assertEqual(video, video_to_mp4:category()).

audio_to_mp3_test() ->
  ?assertEqual(video, audio_to_mp3:category()).

video_to_hls_test() ->
  ?assertEqual(video, video_to_hls:category()).
-endif.
