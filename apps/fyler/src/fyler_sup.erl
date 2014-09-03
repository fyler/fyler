-module(fyler_sup).
-include("fyler.hrl").
-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-export([start_worker/1,stop_worker/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

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

init([]) ->
    Children = [
      ?CHILD(fyler_event,worker),
      ?CHILD(fyler_server,worker),
      ?CHILD(fyler_event_listener,worker)
    ],

    SizeArgs = [
      {size,?Config(pg_pool_size,5)},
      {max_overflow,?Config(pg_max_overflow,10)}
    ],
    PoolArgs = [
      {name, {local, ?PG_POOL}},
      {worker_module, fyler_pg_worker}
    ] ++ SizeArgs,

    PoolSpecs = [poolboy:child_spec(?PG_POOL, PoolArgs, [])],

    {ok, { {one_for_one, 5, 10}, Children++PoolSpecs} };

init([pool]) ->
  Children = [
    ?CHILD(fyler_pool,worker),
    ?CHILD(fyler_monitor,worker),
    ?CHILD(fyler_uploader,worker),
    {worker_sup,
      {supervisor,start_link,[{local, worker_sup}, ?MODULE, [worker]]},
      permanent,
      infinity,
      supervisor,
      []
    }
  ],
  {ok, { {one_for_one, 5, 10}, Children} }.


