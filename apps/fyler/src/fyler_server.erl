%% Copyright
-module(fyler_server).
-author("palkan").
-include("../include/log.hrl").
-include("fyler.hrl").

-behaviour(gen_server).

%% store session info
-define(T_SESSIONS, fyler_auth_sessions).

-define(SESSION_EXP_TIME, 300000).

-define(APPS, [ranch, cowlib, cowboy, mimetypes, ibrowse]).

%% API
-export([start_link/0]).

-export([run_task/3, start_pool/1, clear_stats/0, pools/0, send_response/3, authorize/2, is_authorized/1, tasks_stats/0, save_task_stats/1]).

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
  pool_masters = #{} :: #{atom() => pid()},
  nodes = #{} ::#{atom() => atom()},
  tasks_count = 1 :: non_neg_integer()
}).


%% API
start_link() ->
  ?D("Starting fyler webserver"),
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init(_Args) ->

  net_kernel:monitor_nodes(true),

  ulitos_app:ensure_started(?APPS),

  ?D("fyler webserver started"),

  ets:new(?T_STATS, [public, named_table, {keypos, #job_stats.id}]),

  ets:new(?T_LIVE_STATS, [public, named_table, {keypos, #task.id}]),

  ets:new(?T_SESSIONS, [private, named_table, {keypos, #ets_session.session_id}]),

  {ok, Http} = start_http_server(),

  Bucket = ?Config(aws_s3_bucket, []),

  PoolMasters = setup_pools(?Config(pool_types,[])),

  {ok, #state{cowboy_pid = Http, aws_bucket = Bucket, pool_masters = PoolMasters, aws_dir = ?Config(aws_dir, "fyler/")}}.


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
%% Return list of pools available
%% @end

pools() ->
  [[{node, Node}, {type, Type}, {enabled, Enabled}, {active_tasks, Active}, {total, Total}] || #pool{node = Node, type = Type, enabled = Enabled, active_tasks_num = Active, total_tasks = Total} <- gen_server:call(?MODULE, pools)].

%% @doc
%% Return a list of last 50 tasks completed as #job_stats{}.
%% @end

-spec tasks_stats() -> list(#job_stats{}).

tasks_stats() ->
  [fyler_utils:stats_to_proplist(V) || V <- ets:tab2list(?T_STATS)].


%% @doc
%% Save task statistics to pg
%% @end

-spec save_task_stats(#job_stats{}) -> any().

save_task_stats(#job_stats{} = Stats) ->
  ets:insert(?T_STATS, Stats).

%% @doc
%% Run new pool instance by type
%% @end

-spec start_pool(atom()) -> ok|false.

start_pool(Type) ->
  ?D({request_new_pool,Type}),
  false.


%% @doc
%% Run new task.
%% @end

-spec run_task(string(), string(), list()) -> ok|false.

run_task(URL, Type, Options) ->
  PoolType = pool_type(Type),
  TaskType = list_to_atom(Type),
  gen_server:call(?MODULE, {run_task, URL, PoolType, TaskType, Options}).


handle_call({run_task, URL, PoolType, Type, Options}, _From, #state{pool_masters = Pools, aws_bucket = Buckets, tasks_count = TCount} = State) ->
  case maps:get(PoolType,Pools,false) of
    false -> 
      ?E({unknown_type, PoolType}),
      {reply, false, State};
    Pool ->
      case parse_url(URL, Buckets) of
        {true, Bucket, Path, Name, Ext} ->
          UniqueDir = uniqueId() ++ "_" ++ Name,
          TmpName = filename:join(UniqueDir, Name ++ "." ++ Ext),
          ?D(Options),
          Callback = proplists:get_value(callback, Options, undefined),
          TargetDir = case proplists:get_value(target_dir, Options) of
                        undefined -> filename:join(AwsDir,UniqueDir);
                        TargetDir_ -> case parse_url_dir(binary_to_list(TargetDir_), Bucket) of
                                        {true, TargetPath} -> TargetPath;
                                        _ -> ?D(wrong_target_dir), filename:join(AwsDir, UniqueDir)
                                      end
                      end,

          Task = #task{id = TCount, type = Type, pool_type = PoolType, options = Options, callback = Callback, file = #file{extension = Ext, target_dir = TargetDir, bucket = Bucket, is_aws = true, url = Path, name = Name, tmp_path = TmpName}},
         
          ets:insert(?T_LIVE_STATS, Task),

          Pool ! {run_task, Task},

          {reply, ok, State#state{tasks_count = TCount + 1}};

        _ -> 
          ?E({bad_url, URL}),
          {reply, false, State}
      end
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

handle_call(pools, _From, #state{pools=PoolMasters} = State) ->
  {reply, lists:flatten([gen_server:call(Pool, pools) || Pool <- PoolMasters]), State};


handle_call(_Request, _From, State) ->
  ?D(_Request),
  {reply, unknown, State}.


handle_cast({pool_enabled, Type, Node, Enabled}, #state{pools_masters=Pools} = State) ->
  ?D({pool_enabled, Type, Node, Enabled}),
  case maps:get(Type,Pools,false) of
    false -> 
      ?E({unknown_pool_type, Node, Type}),
      false;
    Pool ->
      Pool ! {pool_enabled, Node, Enabled}
  end,
  {noreply, State};


handle_cast(_Request, State) ->
  ?D(_Request),
  {noreply, State}.


handle_info({session_expired, Token}, State) ->
  ets:delete(?T_SESSIONS, Token),
  {noreply, State};

handle_info({pool_connected, Node, Type, Enabled, Num}, #state{pool_masters = Pools, nodes = Nodes} = State) ->
  NewNodes = case maps:get(Type,Pools,false) of
    false -> 
      ?E({unknown_pool_type, Node, Type}),
      Nodes;
    Pool -> 
      Pool ! {pool_connected, Node, Type, Enabled, Num},
      {fyler_pool, Node} ! pool_accepted,
      maps:put(Node,Type,Nodes)
  end,
  {noreply, State#state{nodes = NewNodes}};


handle_info({nodedown, Node}, #state{nodes = Nodes, pool_masters = Pools} = State) ->
  ?D({nodedown, Node}),
  NewNodes = case maps:get(Node,Nodes, false) of
    false -> 
      ?D({unknown_node,Node}),
      Nodes;
    Type ->
      PoolMaster = maps:get(Type,Pools),
      PoolMaster ! {pool_disconnected, Node},

      case ets:match_object(?T_LIVE_STATS, #task{pool = Node, _ = '_'}) of
        [] -> 
          ?I("No active tasks in died pool"), ok;
        Tasks -> 
          ?I("Pool died with active tasks; restarting..."),
          restart_tasks(Tasks,PoolMaster)
      end,
      maps:remove(Node,Nodes)
  end,
  {noreply, State#state{nodes = NewNodes}};

handle_info(Info, State) ->
  ?D(Info),
  {noreply, State}.

terminate(_Reason, _State) ->
  ?D(_Reason),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


%% @doc
%% Send response to task initiator as HTTP Post with params <code>status = success|failed</code> and <code>path</code - path to download file if success.
%% @end

-spec send_response(task(), stats(), success|failed) -> ok|list()|binary().

send_response(#task{callback = undefined}, _, _) ->
  ok;

send_response(#task{callback = Callback, file = #file{bucket = Bucket, target_dir = Dir}}, #job_stats{result_path = Path}, success) ->
  ibrowse:send_req(binary_to_list(Callback), [{"Content-Type", "application/x-www-form-urlencoded"}], post, "status=ok&aws=true&bucket=" ++ Bucket ++ "&data=" ++ jiffy:encode({[{path, Path}, {dir, list_to_binary(Dir)}]}), []);

send_response(#task{callback = Callback}, _, failed) ->
  ibrowse:send_req(binary_to_list(Callback), [{"Content-Type", "application/x-www-form-urlencoded"}], post, "status=failed", []).


start_http_server() ->
  Dispatch = cowboy_router:compile([
    {'_', [
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
%% Add tasks to the queue again.
%% @end

-spec restart_tasks(list(task())) -> ok.

restart_tasks([],_) -> ?I("All tasks restarted."), ok;

restart_tasks([Task|T],Pool) ->
  ?D({restarting_task, Task}),
  Pool ! {run_task, Task},
  restart_tasks(T,Pool).


%%% @doc
%%% @end

-spec parse_url(string(),list(string())) -> {IsAws::boolean(),Bucket::string()|boolean(), Path::string(),Name::string(),Ext::string()}.

parse_url(Path, Buckets) ->
  {ok, Re} = re:compile("[^:]+://.+/([^/]+)\\.([^\\.]+)"),
  case re:run(Path, Re, [{capture, all, list}]) of
    {match, [_, Name, Ext]} ->
      {ok, Re2} = re:compile("[^:]+://([^\\.]+)\\.s3\\.amazonaws\\.com/(.+)"),
      {IsAws, Bucket,Path2} = case re:run(Path, Re2, [{capture, all, list}]) of
        {match, [_, Bucket_, Path_]} ->
          {true, Bucket_, Path_};
        _ -> {ok, Re3} = re:compile("[^:]+://([^/\\.]+).s3\\-[^\\.]+\\.amazonaws\\.com/(.+)"),
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


path_to_test() ->
  ?assertEqual({false, false, "http://qwe/data.ext", "data", "ext"}, parse_url("http://qwe/data.ext", [])),
  ?assertEqual({false, false, "http://dev2.teachbase.ru/app/cpi.txt", "cpi", "txt"}, parse_url("http://dev2.teachbase.ru/app/cpi.txt", [])),
  ?assertEqual({false, false, "https://qwe/qwe/qwr/da.ta.ext", "da.ta", "ext"}, parse_url("https://qwe/qwe/qwr/da.ta.ext", ["qwo"])),
  ?assertEqual({true, "qwe", "qwe/da.ta.ext", "da.ta", "ext"}, parse_url("http://qwe.s3-eu-west-1.amazonaws.com/da.ta.ext", ["qwe"])),
  ?assertEqual({true, "qwe", "qwe/da.ta.ext", "da.ta", "ext"}, parse_url("http://qwe.s3.amazonaws.com/da.ta.ext", ["qwe", "qwo"])),
  ?assertEqual({true, "qwe", "qwe/path/to/object/da.ta.ext", "da.ta", "ext"}, parse_url("http://qwe.s3-eu-west-1.amazonaws.com/path/to/object/da.ta.ext", ["qwe"])),
  ?assertEqual({false, false, "http://qwe.s3-eu-west-1.amazonaws.com/path/to/object/da.ta.ext", "da.ta", "ext"}, parse_url("http://qwe.s3-eu-west-1.amazonaws.com/path/to/object/da.ta.ext", "q")),
  ?assertEqual(false, parse_url("qwr/data.ext", [])).


dir_url_test() ->
  ?assertEqual({true, "recordings/2/record_17/stream_1/"}, parse_url_dir("https://devtbupload.s3.amazonaws.com/recordings/2/record_17/stream_1/", "devtbupload")),
  ?assertEqual({true, "recordings/2/record_17/stream_1/"}, parse_url_dir("http://devtbupload.s3-eu-west-1.amazonaws.com/recordings/2/record_17/stream_1/", "devtbupload")),
  ?assertEqual({false, "https://2.com/record_17/stream_1/"}, parse_url_dir("https://2.com/record_17/stream_1/", "devtbupload")).


authorization_test_() ->
  {"Authorization test",
    {setup,
      fun start_server_/0,
      fun stop_server_/1,
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
    }
  }.


start_server_() ->
  ok = application:start(fyler),
  application:set_env(fyler,auth_pass,ulitos:binary_to_hex(crypto:hash(md5, "test"))).


stop_server_(_) ->
  application:stop(fyler).


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


-endif.
