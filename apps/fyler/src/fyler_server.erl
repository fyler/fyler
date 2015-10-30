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

-define(APPS, [ranch, cowlib, cowboy, mimetypes, hackney]).

%% API
-export([start_link/0]).

-export([run_task/3, clear_stats/0, pools/0, current_tasks/0, send_response/2, authorize/2, is_authorized/1, tasks_stats/0, tasks_stats/1, save_task_stats/1, task_status/1, cancel_task/1]).

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
  aws_dir :: string(),
  managers = #{} :: #{atom() => pid()}
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

  AwsDir = ?Config(aws_dir, "fyler/"),

  ?I({server_start, AwsDir}),

  %% check db for task in progress and restart them
  self() ! check_pending_tasks,

  {ok, #state{cowboy_pid = Http, aws_dir = AwsDir}}.


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
  gen_server:call(?MODULE, current_tasks).

-spec tasks_stats() -> list(#job_stats{}).

tasks_stats() ->
  tasks_stats([]).

%% @doc
%% Return a list of last 50 tasks completed as #job_stats{}.
%% @end
-spec tasks_stats(Params::list()) -> list(#job_stats{}).

tasks_stats(Params) ->
  ?D({query_params,Params}),
  Offset = binary_to_list(proplists:get_value(offset,Params,<<"0">>)),
  Limit = binary_to_list(proplists:get_value(limit,Params,<<"50">>)),
  OrderBy = binary_to_list(proplists:get_value(order_by,Params,<<"id">>)),
  Order = binary_to_list(proplists:get_value(order,Params,<<"desc">>)),

  Query_ = [],
  
  Query1 = case proplists:get_value(status,Params,false) of
    false -> Query_;
    Status -> Query_++["status='"++binary_to_list(Status)++"'"]
  end,

  Query2 = case proplists:get_value(type,Params,false) of
    false -> Query1;
    Type -> Query1++["task_type='"++binary_to_list(Type)++"'"]
  end,

  Query = if length(Query2) > 0
    -> "where ("++string:join(Query2," and ")++")";
    true -> ""
  end,

  SQL = "select * from tasks "++Query++"order by "++OrderBy++" "++Order++" offset "++Offset++" limit "++Limit,

  Values = case pg_cli:equery(SQL) of
             {ok, _, List} ->
               List;
             Other ->
               ?E({pg_query_failed, SQL, Other}),
               []
           end,
  [fyler_utils:stats_to_proplist(fyler_utils:task_record_to_proplist(V)) || V <- Values].


%% @doc
%% Save task statistics to pg
%% @end

-spec save_task_stats(#job_stats{}) -> any().

save_task_stats(#job_stats{id = Id} = Stats) ->
  ValuesString = fyler_utils:stats_to_pg_update_string(Stats),
  ?D({pg_update_values,ValuesString}),
  case pg_cli:equery("update tasks set " ++ ValuesString ++ "where id = " ++ integer_to_list(Id)) of
    {ok, _} -> ok;
    Other -> ?E({pg_query_failed, Other})
  end.


%% @doc
%% Run new task.
%% @end

-spec run_task(string(), string(), list()) -> ok|false.

run_task(URL, Type, Options) ->
  gen_server:call(?MODULE, {run_task, URL, Type, Options}).

%% @doc
%% Get status of task
%% @end

-spec task_status(non_neg_integer()) -> undefined | queued | progress | success | abort.

task_status(TaskId) ->
  case pg_cli:equery("select status from tasks where id = " ++ integer_to_list(TaskId)) of
    {ok, _, []} ->
      undefined;
    {ok, _, [{<<"progress">>}]} ->
      progress;
    {ok, _, [{<<"success">>}]} ->
      success;
    {ok, _, [{<<"abort">>}]} ->
      abort;
    {ok, _, [{Status}]} ->
      Status;
    Other ->
      ?E({pg_query_failed, Other}),
      undefined
  end.

-spec cancel_task(non_neg_integer()) -> ok.

cancel_task(Id) ->
  gen_server:call(fyler_server, {cancel_task, Id}).


handle_call({run_task, URL, Type, Options}, _From, #state{aws_dir = AwsDir} = State) ->
  case build_task(URL, Type, Options, false, AwsDir) of
    #task{id = Id} = Task ->
      NewState = send_to_manager(Task, State),
      {reply, {ok, Id}, NewState};
    _ ->
      {reply, false, State}
  end;

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

handle_call({cancel_task, TaskId}, _From, State) ->
  NewState =
    case pg_cli:equery("select task_type from tasks where id = " ++ integer_to_list(TaskId)) of
      {ok, _, []} ->
        State;
      {ok, _, [{Handler}]} ->
        Category = erlang:apply(atom_to_binary(Handler, utf8), category, []),
        case pg_cli:equery("update tasks set status = 'abort' where id = " ++ integer_to_list(TaskId)) of
          {ok, _} -> ok;
          Other -> ?E({pg_query_failed, Other})
        end,
        {State1, Manager} = find_manager(Category, State),
        fyler_category_manager:cancel_task(Manager, TaskId),
        State1;
      Other ->
        ?E({pg_query_failed, Other}),
        State
    end,
  {reply, ok, NewState};

handle_call(current_tasks, _From, #state{managers = Managers} = State) ->
  Stat = fun(M, _, Stats) -> [{[{M, [fyler_utils:current_task_to_proplist(Task) || Task <- ets:tab2list(M)]}]} | Stats] end,
  {reply, maps:fold(Stat, [], Managers), State};

handle_call(_Request, _From, State) ->
  ?D(_Request),
  {reply, unknown, State}.


handle_cast({pool_enabled, Node, Enabled}, State) ->
  ?D({pool_enabled, Enabled, Node}),
  case ets:lookup(?T_POOLS,Node) of
    [#pool{category = Category} = Pool] ->
      {NewState, Pid} = find_manager(Category, State),
      ets:insert(?T_POOLS, Pool#pool{enabled = Enabled}),
      if
        Enabled -> fyler_category_manager:pool_enabled(Pid, Node);
        true -> fyler_category_manager:pool_disabled(Pid, Node)
      end,
      {noreply, NewState};
    _ -> {noreply, State}
  end;

handle_cast({task_finished, _Node}, State) ->
  {noreply, State};

handle_cast(_Request, State) ->
  ?D(_Request),
  {noreply, State}.

handle_info({session_expired, Token}, State) ->
  ets:delete(?T_SESSIONS, Token),
  {noreply, State};

handle_info({pool_connected, Node, Category, Enabled}, State) ->
  ?D({pool_connected, Node, Category, Enabled}),
  Pool = #pool{node = Node, category = Category, enabled = Enabled},

  {fyler_pool, Node} ! pool_accepted,

  {NewState, Manager} = find_manager(Category, State),

  case ets:lookup(?T_POOLS,Node) of
    [#pool{}] -> fyler_category_manager:pool_down(Manager, Node);
    _ -> ok
  end,

  ets:insert(?T_POOLS, Pool),

  fyler_event:pool_connected(Manager, Category),
  fyler_category_manager:pool_connected(Manager, Node),
  if
    not Enabled ->
      fyler_event:pool_disabled(Node, Category),
      fyler_category_manager:pool_disabled(Manager, Node);
    true -> ok
  end,

  {noreply, NewState};

handle_info({task_accepted, Ref, Node, Category}, State) ->
  {NewState, Manager} = find_manager(Category, State),
  fyler_category_manager:task_accepted(Manager, Ref, Node),
  {noreply, NewState};

handle_info({task_rejected, Ref, Node, Category}, State) ->
  {NewState, Manager} = find_manager(Category, State),
  fyler_category_manager:task_rejected(Manager, Ref, Node),
  {noreply, NewState};

handle_info({nodedown, Node}, #state{managers = Managers} = State) ->
  ?E({nodedown, Node}),
  NewState =
    case ets:lookup(?T_POOLS, Node) of
      [#pool{category = Category}] ->
        ets:delete(?T_POOLS,Node),
        fyler_event:pool_down(Node, Category),
        case maps:get(Category, Managers, undefined) of
          undefined ->
            {ok, Pid} = fyler_sup:start_category_manager(Category),
            State#state{managers = maps:put(Category, Pid, Managers)};
          Pid ->
            fyler_category_manager:pool_down(Pid, Node),
            State
        end;
      _ ->
        ?E({unknown_node, Node}),
        State
    end,
  {noreply, NewState};


handle_info(check_pending_tasks, State) ->
  Query = "select * from tasks where status='progress' order by id ASC",
  Values = case pg_cli:equery(Query) of
             {ok, _, List} -> List;
             {ok, _,_,_} -> []; %% mocked in test
             Other -> ?E({pg_query_failed, Query, Other}),
                      []
           end,
  Tasks = [fyler_utils:task_record_to_task(V) || V <- Values],
  NewState = rebuild_tasks(Tasks, State),
  {noreply, NewState};

handle_info({'DOWN', _, process, Pid, Reason}, #state{managers = Managers} = State) ->
  case lists:keyfind(Pid, 2, maps:to_list(Managers)) of
    {Category, Pid} ->
      ?D({"manager down", Category, Reason}),
      {noreply, State#state{managers = maps:put(Category, undefined, Managers)}};
    false ->
      {noreply, State}
  end;

handle_info(Info, State) ->
  ?D(Info),
  {noreply, State}.

terminate(_Reason,_State) ->
  ?D(_Reason),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

find_manager(Category, #state{managers = Managers} = State) ->
  case maps:get(Category, Managers, undefined) of
    undefined ->
      {ok, Pid} = fyler_sup:start_category_manager(Category),
      erlang:monitor(process, Pid),
      {State#state{managers = maps:put(Category, Pid, Managers)}, Pid};
    Pid ->
      {State, Pid}
  end.

%% @doc Send to task to task manager

-spec send_to_manager(task(), #state{}) -> #state{}.

send_to_manager(#task{category = Category} = Task, State) ->
  {NewState, Manager} = find_manager(Category, State),
  fyler_category_manager:run_task(Manager, Task),
  NewState.

%% @doc
%% Send response to task initiator as HTTP Post with params <code>status = success|failed</code> and <code>path</code - path to download file if success.
%% @end

-spec send_response(task(), stats()) -> ok.

send_response(#task{callback = undefined}, _Stats) ->
  ok;

send_response(Task, Stats) ->
  fyler_sup:start_callback_worker(Task, Stats).

start_http_server() ->
  Dispatch = cowboy_router:compile([
    {'_', [
      {"/", stats_handler, []},
      {"/stats", stats_handler, []},
      {"/tasks", tasks_handler, []},
      {"/pools", pools_handler, []},
      {"/api/auth", auth_handler, []},
      {"/api/tasks/[:id]", [{id, int}], task_handler, []},
      {'_', notfound_handler, []}
    ]}
  ]),
  Port = ?Config(http_port, 8008),
  cowboy:start_http(http_listener, 100,
    [{port, Port}],
    [{env, [{dispatch, Dispatch}]}]
  ).


build_task(URL, Type, Options, OldId, AwsDir) ->
  case parse_url(URL) of
    {true, Bucket, Path, Name, Ext} ->
      %% generate temp uniq name
      UniqueDir = uniqueId() ++ "_" ++ Name,
      TmpName = filename:join(UniqueDir, Name ++ "." ++ Ext),

      ?D(Options),

      Callback = proplists:get_value(callback, Options, undefined),
      TargetDir = 
        case proplists:get_value(target_dir, Options) of
          undefined -> filename:join(AwsDir,UniqueDir);
          TargetDir_ -> case parse_url_dir(binary_to_list(TargetDir_), Bucket) of
                          {true, TargetPath} -> TargetPath;
                          _ -> ?E({wrong_target_dir, TargetDir_}), filename:join(AwsDir,UniqueDir)
                        end
        end,

      Handler = list_to_atom(Type),

      Category = erlang:apply(Handler,category,[]),

      Priority_ = proplists:get_value(priority, Options, <<"low">>),
      Priority = binary_to_atom(Priority_,latin1),

      Id = 
        case OldId of
          false ->
            {ok, 1, _, [{Id_}]} = pg_cli:equery("insert into tasks (status, file_path, task_type, url, options, priority) values ('progress', '" ++ Path ++ "', '" ++ atom_to_list(Handler) ++ "', '"++URL++"', '"++binary_to_list(fyler_utils:to_json(Options))++"', '"++atom_to_list(Priority)++"') returning id"),
            Id_;
          _ -> OldId
        end,
      %%ets:insert(?T_STATS, #current_task{id = Id, type = list_to_atom(Type), url = Path, status = queued}),
      #task{id = Id, type = Handler, category = Category, options = Options, callback = Callback, priority = Priority, file = #file{extension = Ext, target_dir = TargetDir, bucket = Bucket, is_aws = true, url = Path, name = Name, dir = UniqueDir, tmp_path = TmpName}};
    _ ->
      %% change status if taks was from db
      case OldId of
        false -> ok;
        _ ->
          pg_cli:equery("update tasks set status = 'failed', error_msg = 'bad_url' where id = " ++ integer_to_list(OldId))
      end,
      ?E({bad_url, URL}),
      false
  end.

%% @doc
%% Rebuild tasks from db (after server is down).
%% @end

rebuild_tasks([], State) -> ?I("All tasks rebuilt."), State;

rebuild_tasks([{Url, Type, Options, Id}=T|Tasks], #state{aws_dir = AwsDir} = State) ->
  ?D({rebuilding_task, T}),
  Task = build_task(Url, Type, Options, Id, AwsDir),
  rebuild_tasks(Tasks, send_to_manager(Task, State)).


%%% @doc
%%% @end

-spec parse_url(string()) -> {IsAws::boolean(),Bucket::string()|boolean(), Path::string(),Name::string(),Ext::string()}.

parse_url(Path) ->
  {ok, Re} = re:compile("[^:]+://.+/([^/]+)\\.([^\\.]+)"),
  case re:run(Path, Re, [{capture, all, list}]) of
    {match, [_, Name, Ext]} ->
      {ok, Re2} = re:compile("[^:]+://([^/]+)\\.s3[^\\.]*\\.amazonaws\\.com/(.+)"),
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
        false -> {false, false, Path, Name, Ext};
        _ -> {true, Bucket, Bucket++"/"++Path2, Name, Ext}
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
-define(setup2(F), {setup, fun setup2_/0, fun cleanup_/1, F}).

path_to_test() ->
  ?assertEqual({false, false, "http://qwe/data.ext", "data", "ext"}, parse_url("http://qwe/data.ext")),
  ?assertEqual({false, false, "http://dev2.teachbase.ru/app/cpi.txt", "cpi", "txt"}, parse_url("http://dev2.teachbase.ru/app/cpi.txt")),
  ?assertEqual({false, false, "https://qwe/qwe/qwr/da.ta.ext", "da.ta", "ext"}, parse_url("https://qwe/qwe/qwr/da.ta.ext")),
  ?assertEqual({true, "qwe", "qwe/da.ta.ext", "da.ta", "ext"}, parse_url("http://qwe.s3-eu-west-1.amazonaws.com/da.ta.ext")),
  ?assertEqual({true, "qwe", "qwe/da.ta.ext", "da.ta", "ext"}, parse_url("https://s3-eu-west-1.amazonaws.com/qwe/da.ta.ext")),
  ?assertEqual({true, "qwe", "qwe/da.ta.ext", "da.ta", "ext"}, parse_url("http://qwe.s3.amazonaws.com/da.ta.ext")),
  ?assertEqual({true, "qwe", "qwe/path/to/object/da.ta.ext", "da.ta", "ext"}, parse_url("http://qwe.s3-eu-west-1.amazonaws.com/path/to/object/da.ta.ext")),
  ?assertEqual(false, parse_url("qwr/data.ext")).


dir_url_test() ->
  ?assertEqual({true, "recordings/2/record_17/stream_1/"}, parse_url_dir("https://devtbupload.s3.amazonaws.com/recordings/2/record_17/stream_1/", "devtbupload")),
  ?assertEqual({true, "recordings/2/record_17/stream_1/"}, parse_url_dir("http://devtbupload.s3-eu-west-1.amazonaws.com/recordings/2/record_17/stream_1/", "devtbupload")),
  ?assertEqual({false, "https://2.com/record_17/stream_1/"}, parse_url_dir("https://2.com/record_17/stream_1/", "devtbupload")).


setup_() ->
  lager:start(),
  application:set_env(fyler,config,"fyler.config.test"),
  ulitos_app:set_var(fyler, aws_s3_bucket, ["test"]),
  meck:new(pg_cli, [passthrough]),
  meck:expect(pg_cli, equery, fun(_) -> {ok, 1, 1, [{1}]} end),
  fyler:start().

setup2_() ->
  lager:start(),
  application:set_env(fyler,config,"fyler.config.test"),
  ulitos_app:set_var(fyler, aws_s3_bucket, ["test"]),
  meck:new(pg_cli, [passthrough]),
  meck:expect(pg_cli, equery, fun(_) -> {ok, 1, [{1,<<"progress">>,1,1,1,<<"">>,1,<<"">>,<<"do_nothing">>,<<"">>,{{2013,10,24},{12,0,0.3}}, <<"https://test.s3.amazonaws.com/test.smth">>, <<"{\"callback\":\"http://callback\"}">>, <<"low">>}]} end),
  fyler:start().

cleanup_(_) ->
  meck:unload(pg_cli),
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
  fyler_server ! {pool_connected, test, docs, true},
  [
    ?_assertEqual(1, length(fyler_server:pools()))
  ].

remove_pool_t_(_) ->
  fyler_server ! {nodedown, test},
  [
    ?_assertEqual(0, length(ets:lookup(?T_POOLS,test)))
  ].

pools_list_t_(_) ->
  ets:insert(?T_POOLS, #pool{node = test, category = docs, enabled = true}),
  ets:insert(?T_POOLS, #pool{node = test2, category = docs, enabled = true}),
  ets:insert(?T_POOLS, #pool{node = test3, category = docass, enabled = false}),
  Pools = [P||{P}<-fyler_server:pools()],
  [
    ?_assertEqual(3, length(Pools))
  ].

tasks_test_() ->
  [
    {"add task",
    ?setup(
      fun add_task_t_/1
      )
    },
    {
      "run task",
      ?setup(
        fun run_task_t_/1
      )
    },
    {
      "rebuild tasks",
      ?setup2(
        fun rebuild_tasks_t_/1
      )
    },
    {
      "task params",
      ?setup(
        fun task_params_t_/1
      )
    }
  ].

add_task_t_(_) ->
  Res = fyler_server:run_task("https://test.s3.amazonaws.com/test.smth", "do_nothing", [{target_dir, <<"target/dir">>},{callback, <<"call_me.php">>}]),
  [
    ?_assertEqual({ok, 1},Res)
  ].

run_task_t_(_) ->
  [
    ?_assertEqual({ok, 1}, fyler_server:run_task("https://s3-eu-west-1.amazonaws.com/test/10.xls","do_nothing",[]))
  ].

task_params_t_(_) ->
  fyler_server:run_task("http://test.s3.amazonaws.com/record/stream.flv","recording_to_hls",[{stream_type,<<"media">>},{target_dir,<<"http://test.s3.amazonaws.com/record/stream/">>}, {callback,<<"http://callback">>}]),
  Tasks = fyler_server:current_tasks(),
  {{value,#task{file=File, category=Category, callback=Callback}},_} = fyler_queue:out(maps:get(video,Tasks)),
  [
    ?_assertMatch(#file{target_dir= "record/stream/", bucket="test", extension="flv", name="stream", url="test/record/stream.flv"},File),
    ?_assertEqual(video, Category),
    ?_assertEqual(<<"http://callback">>, Callback)
  ].

rebuild_tasks_t_(_) ->
  Tasks = fyler_server:current_tasks(),
  {{value,#task{file=File, category=Category, callback=Callback}},_} = fyler_queue:out(maps:get(test,Tasks)),
  [
    ?_assertMatch(#file{bucket="test", name="test"},File),
    ?_assertEqual(test, Category),
    ?_assertEqual(<<"http://callback">>, Callback)
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

unpack_html_test() ->
  ?assertEqual(document, unpack_html:category()).

recording_to_hls_test() ->
  ?assertEqual(video, recording_to_hls:category()).

video_to_mp4_test() ->
  ?assertEqual(video, video_to_mp4:category()).

audio_to_mp3_test() ->
  ?assertEqual(video, audio_to_mp3:category()).

video_to_hls_test() ->
  ?assertEqual(video, video_to_hls:category()).
-endif.
