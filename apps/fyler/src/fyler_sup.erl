-module(fyler_sup).
-include("fyler.hrl").
-include("log.hrl").
-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-export([start_worker/1, stop_worker/1, start_category_manager/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(CHILD(I, Type, Args), {I, {I, start_link, Args}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

%% @doc Start new worker
%% @end

-spec start_worker(task()) -> supervisor:startlink_ret().

start_worker(Task) ->
  supervisor:start_child(worker_sup, [Task]).


%% @doc Stop worker process
%% @end
-spec stop_worker(pid()) -> ok | {error,atom()}.

stop_worker(Pid) ->
  supervisor:terminate_child(worker_sup,Pid).

%% @doc Start category manager
%% @end
-spec start_category_manager(atom()) -> supervisor:startlink_ret().

start_category_manager(Category) ->
  supervisor:start_child(category_sup, [Category]).

start_link(server) ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []);

start_link(pool) ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, [pool]).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================


init([worker]) ->
  {ok, {{simple_one_for_one, 5, 10}, [
    {undefined, {fyler_worker, start_link, []},
      temporary, 2000, worker, [fyler_worker]}
  ]}};

init([category_sup]) ->
  {ok, {{simple_one_for_one, 5, 10}, [
    {undefined, {fyler_category_manager, start_link, []},
      temporary, 2000, worker, []}
  ]}};

init([category]) ->
  {ok, {{one_for_all, 5, 10}, []}};

init([]) ->
    Children = [
      {category_sup,
        {supervisor,start_link,[{local, category_sup}, ?MODULE, [category_sup]]},
        permanent,
        infinity,
        supervisor,
        []
      },
      ?CHILD(fyler_server,worker),
      ?CHILD(fyler_event,worker),
      ?CHILD(fyler_event_listener,worker)
    ],
    PgSizeArgs = [
      {size,?Config(pg_pool_size,5)},
      {max_overflow,?Config(pg_max_overflow,10)}
    ],
    PgPoolArgs = [
      {name, {local, ?PG_POOL}},
      {worker_module, fyler_pg_worker}
    ] ++ PgSizeArgs,

    PgPoolSpecs = [poolboy:child_spec(?PG_POOL, PgPoolArgs, [])],

    HPoolArgs = [
      {name, {local, ?H_POOL}},
      {worker_module, fyler_hackney_worker},
      {size, 3},
      {max_overflow, 8}
    ],

    HPoolSpecs = [poolboy:child_spec(?H_POOL, HPoolArgs, [])],

    {ok, { {one_for_one, 5, 10}, PgPoolSpecs ++ HPoolSpecs ++ Children} };

init([pool]) ->
  Children = [
    ?CHILD(fyler_monitor, worker),
    ?CHILD(fyler_uploader,worker),
    {worker_sup,
      {supervisor,start_link,[{local, worker_sup}, ?MODULE, [worker]]},
      permanent,
      infinity,
      supervisor,
      []
    },
    ?CHILD(fyler_pool,worker)
  ],
  {ok, { {one_for_one, 5, 10}, Children} }.


