-module(fyler_sup).
-include("fyler.hrl").
-include("log.hrl").
-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-export([
  start_worker/1,
  stop_worker/1,
  start_category_manager/1,
  start_callback_worker/2
]).

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
-spec stop_worker(pid()) -> ok | {error, atom()}.

stop_worker(Pid) ->
  supervisor:terminate_child(worker_sup, Pid).

%% @doc Start category manager
%% @end
-spec start_category_manager(atom()) -> supervisor:startlink_ret().

start_category_manager(Category) ->
  supervisor:start_child(category_sup, [Category]).

%% @doc Start hackney (callback) worker
%% @end
-spec start_callback_worker(task(), stats()) -> supervisor:startlink_ret().

start_callback_worker(Task, Stats) ->
  supervisor:start_child(callback_sup, [Task, Stats]).


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

init([hackney_worker]) ->
  {ok, {{simple_one_for_one, 5, 120}, [
    {undefined, {fyler_hackney_worker, start_link, []},
      transient, brutal_kill, worker, [fyler_hackney_worker]}
  ]}};

init([category_sup]) ->
  {ok, {{simple_one_for_one, 5, 10}, [
    {undefined, {fyler_category_manager, start_link, []},
      temporary, 2000, worker, [fyler_category_manager]}
  ]}};

init([category]) ->
  {ok, {{one_for_all, 5, 10}, []}};

init([]) ->
    Children = [
      {category_sup,
        {
          supervisor,
          start_link,
          [{local, category_sup}, ?MODULE, [category_sup]]
        },
        permanent,
        infinity,
        supervisor,
        []
      },
      {callback_sup,
        {
          supervisor,
          start_link,
          [{local, callback_sup}, ?MODULE, [hackney_worker]]
        },
        permanent,
        infinity,
        supervisor,
        []
      },
      ?CHILD(fyler_server, worker),
      ?CHILD(fyler_event, worker),
      ?CHILD(fyler_event_listener, worker)
    ],
    PgSizeArgs = [
      {size, ?Config(pg_pool_size, 5)},
      {max_overflow, ?Config(pg_max_overflow, 10)}
    ],
    PgPoolArgs = [
      {name, {local, ?PG_POOL}},
      {worker_module, fyler_pg_worker}
    ] ++ PgSizeArgs,

    PgPoolSpecs = [poolboy:child_spec(?PG_POOL, PgPoolArgs, [])],

    {ok, { {one_for_one, 5, 10}, PgPoolSpecs ++ Children} };

init([pool]) ->
  Children = [
    ?CHILD(fyler_monitor, worker),
    ?CHILD(fyler_uploader, worker),
    {worker_sup,
      {
        supervisor,
        start_link,
        [{local, worker_sup}, ?MODULE, [worker]]
      },
      permanent,
      infinity,
      supervisor,
      []
    },
    ?CHILD(fyler_pool, worker)
  ],
  {ok, { {one_for_one, 5, 10}, Children} }.


