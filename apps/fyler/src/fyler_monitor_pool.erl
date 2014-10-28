-module(fyler_monitor_pool).

-include("fyler.hrl").
-include("log.hrl").

-behaviour(gen_fsm).

-define(Regex, "\"PrivateIpAddress\": \"(?<ip>[^\"]*)\"").
-define(Node(Category, Ip), list_to_atom(lists:flatten(io_lib:format("fyler_pool_~p@~s", [Category, Ip])))).

%% API
-export([start_link/2]).

%% gen_fsm callbacks
-export([init/1,
  monitoring/2,
  start/2,
  after_start/2,
  pre_stop/2,
  stop/2,
  handle_event/3,
  handle_sync_event/4,
  handle_info/3,
  terminate/3,
  code_change/4]).

-record(state, {category :: atom(),
                indicator = 0 :: non_neg_integer(),
                node_counter = 0 :: non_neg_integer(),
                active_nodes = [] :: [atom()],
                passive_nodes = [] :: [atom()],
                node_activity = #{} :: #{atom() => true | false},
                node_to_id :: #{atom() => iolist()},
                stop_ref :: reference() | undefined,
                start_ref :: reference() | undefined,
                timer :: non_neg_integer(),
                instances = [] :: [iolist()]}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Category, Opts) ->
  gen_fsm:start_link(?MODULE, [Category, Opts], []).

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================


init([Category, Opts]) ->
  InstanceList = maps:get(instances, Opts, []),
  Timer = maps:get(timer, Opts, 180000),
  case InstanceList of
    [] ->
      {stop, normal};
    [_Instance] ->
      {stop, normal};
    _ ->
      self() ! start,
      {ok, start_monitor, #state{category = Category, timer = Timer, instances = InstanceList}}
  end.

monitoring(high_idle_time, #state{} = State) ->
  ?D({monitoring, start}),
  {next_state, start, State};

monitoring({pool_connected, Node}, #state{indicator = Ind, node_counter = N, active_nodes = Nodes, passive_nodes = PassiveNodes, node_activity = Activities} = State) ->
  ?D({pool_connected, Node, Nodes}),
  monitoring({pool_enabled, Node}, State#state{indicator = Ind + 1, node_counter = N + 1, active_nodes = [Node | Nodes], passive_nodes = lists:delete(Node, PassiveNodes), node_activity = maps:put(Node, true, Activities)});

monitoring({pool_down, Node}, #state{indicator = Ind, node_counter = N, active_nodes = Nodes, passive_nodes = PassiveNodes, node_activity = Activities} = State) ->
  ?D({pool_down, Node}),
  NewInd =
    case maps:get(Node, Activities, true) of
      true -> Ind;
      false -> Ind - 1
    end,
  NextState =
    case NewInd + 1 of
      N -> start;
      _ -> monitoring
    end,
  ?D({monitoring, NextState}),
  {next_state, NextState, State#state{indicator = NewInd, node_counter = N - 1, active_nodes = lists:delete(Node, Nodes), passive_nodes = [Node | PassiveNodes]}};

monitoring({pool_enabled, Node}, #state{indicator = Ind, active_nodes = [Node], node_activity = Activities} = State) ->
  {next_state, monitoring, State#state{indicator = Ind - 1, node_activity = maps:put(Node, true, Activities)}};

monitoring({pool_enabled, Node}, #state{indicator = Ind, node_activity = Activities} = State) ->
  ?D({{pool_enabled, Node}}),
  ?D({monitoring, pre_stop}),
  {next_state, pre_stop, State#state{indicator = Ind - 1, node_activity = maps:put(Node, true, Activities)}, 1000};

monitoring({pool_disabled, Node}, #state{indicator = Ind, passive_nodes = [], node_activity = Activities} = State) ->
  {next_state, monitoring, State#state{indicator = Ind + 1, node_activity = maps:put(Node, false, Activities)}};

monitoring({pool_disabled, Node}, #state{indicator = Ind, node_counter = N, node_activity = Activities} = State) when N == Ind + 1 ->
  ?D({monitoring, start}),
  {next_state, start, State#state{indicator = Ind + 1, node_activity = maps:put(Node, false, Activities)}};

monitoring({pool_disabled, Node}, #state{indicator = Ind, node_activity = Activities} = State)->
  {next_state, monitoring, State#state{indicator = Ind + 1, node_activity = maps:put(Node, false, Activities)}};

monitoring(_Event, State) ->
  {next_state, monitoring, State}.

start(high_idle_time, #state{passive_nodes = [Node |_], node_to_id = NodeToId, timer = Timer} = State) ->
  ?D({start_new_instance, Node}),
  ?D({start, after_start}),
  aws_cli:start_instance(maps:get(Node, NodeToId)),
  Ref = make_ref(),
  erlang:send_after(Timer, self(), {start, Ref}),
  {next_state, after_start, State#state{start_ref = Ref}};

start({pool_enabled, Node}, #state{indicator = Ind, node_activity = Activities} = State) ->
  ?D({start, monitoring}),
  {next_state, monitoring, State#state{indicator = Ind - 1, node_activity = maps:put(Node, true, Activities)}};

start({pool_disabled, Node}, #state{indicator = Ind, node_activity = Activities} = State) ->
  {next_state, start, State#state{indicator = Ind + 1, node_activity = maps:put(Node, false, Activities)}};

start({pool_connected, Node}, #state{node_counter = N, active_nodes = Nodes, passive_nodes = PassiveNodes, node_activity = Activities} = State) ->
  ?D({start, monitoring}),
  {next_state, monitoring, State#state{node_counter = N + 1, active_nodes = [Node | Nodes], passive_nodes = lists:delete(Node, PassiveNodes), node_activity = maps:put(Node, true, Activities)}};

start({pool_down, Node}, #state{indicator = Ind, node_counter = N, active_nodes = Nodes, passive_nodes = PassiveNodes, node_activity = Activities} = State) ->
  NewInd =
    case maps:get(Node, Activities, true) of
      true -> Ind;
      false -> Ind - 1
    end,
  {next_state, start, State#state{indicator = NewInd, node_counter = N - 1, active_nodes = lists:delete(Node, Nodes), passive_nodes = [Node | PassiveNodes]}};

start(_Event, State) ->
  {next_state, start, State}.

after_start({pool_enabled, Node}, #state{indicator = Ind, node_activity = Activities} = State) ->
  {next_state, after_start, State#state{indicator = Ind - 1, node_activity = maps:put(Node, true, Activities)}};

after_start({pool_disabled, Node}, #state{indicator = Ind, node_activity = Activities} = State) ->
  {next_state, after_start, State#state{indicator = Ind + 1, node_activity = maps:put(Node, false, Activities)}};

after_start({pool_connected, Node}, #state{node_counter = N, active_nodes = Nodes, passive_nodes = PassiveNodes, node_activity = Activities} = State) ->
  ?D({after_start, monitoring}),
  {next_state, monitoring, State#state{node_counter = N + 1, active_nodes = [Node | Nodes], passive_nodes = lists:delete(Node, PassiveNodes), node_activity = maps:put(Node, true, Activities)}};

after_start({pool_down, Node}, #state{indicator = Ind, node_counter = N, active_nodes = Nodes, passive_nodes = PassiveNodes, node_activity = Activities} = State) ->
  NewInd =
    case maps:get(Node, Activities, true) of
      true -> Ind;
      false -> Ind - 1
    end,
  {next_state, after_start, State#state{indicator = NewInd, node_counter = N - 1, active_nodes = lists:delete(Node, Nodes), passive_nodes = [Node | PassiveNodes]}};

after_start(_Event, State) ->
  {next_state, after_start, State}.

pre_stop(timeout, #state{timer = Timer} = State) ->
  ?D({pre_stop, stop}),
  Ref = make_ref(),
  erlang:send_after(Timer, self(), {stop, Ref}),
  {next_state, stop, #state{stop_ref = Ref} = State};

pre_stop({pool_connected, Node}, #state{node_counter = N, active_nodes = Nodes, passive_nodes = PassiveNodes, timer = Timer, node_activity = Activities} = State) ->
  ?D({pre_stop, stop}),
  Ref = make_ref(),
  erlang:send_after(Timer, self(), {stop, Ref}),
  {next_state, stop, State#state{node_counter = N + 1, active_nodes = [Node | Nodes], passive_nodes = lists:delete(Node, PassiveNodes), stop_ref = Ref, node_activity = maps:put(Node, true, Activities)}};

pre_stop({pool_down, Node}, #state{indicator = Ind, node_counter = N, active_nodes = Nodes, passive_nodes = PassiveNodes, node_activity = Activities} = State) ->
  NewInd =
    case maps:get(Node, Activities, true) of
      true -> Ind;
      false -> Ind - 1
    end,
  NextState =
    case NewInd + 1 of
      N -> start;
      _ -> monitoring
    end,
  ?D({pre_stop, NextState}),
  {next_state, NextState, State#state{indicator = NewInd, node_counter = N - 1, active_nodes = lists:delete(Node, Nodes), passive_nodes = [Node | PassiveNodes]}};

pre_stop({pool_enabled, Node}, #state{indicator = Ind, timer = Timer, node_activity = Activities} = State) ->
  Ref = make_ref(),
  erlang:send_after(Timer, self(), {stop, Ref}),
  ?D({pre_stop, stop}),
  {next_state, stop, State#state{indicator = Ind - 1, stop_ref = Ref, node_activity = maps:put(Node, true, Activities)}};

pre_stop({pool_disabled, Node}, #state{indicator = Ind, node_counter = N, node_activity = Activities} = State)  when N == Ind + 1 ->
  ?D({pre_stop, monitoring}),
  {next_state, monitoring, State#state{indicator = Ind + 1, node_activity = maps:put(Node, false, Activities)}};

pre_stop({pool_disabled, Node}, #state{indicator = Ind, timer = Timer, node_activity = Activities} = State) ->
  ?D({pre_stop, stop}),
  Ref = make_ref(),
  erlang:send_after(Timer, self(), {stop, Ref}),
  {next_state, stop, State#state{indicator = Ind + 1, stop_ref = Ref, node_activity = maps:put(Node, false, Activities)}};

pre_stop(high_idle_time, State) ->
  ?D({pre_stop, monitoring}),
  {next_state, monitoring, State};

pre_stop(_Event, State) ->
  {next_state, pre_stop, State}.

stop({pool_connected, Node}, #state{node_counter = N, active_nodes = Nodes, passive_nodes = PassiveNodes, node_activity = Activities} = State) ->
  {next_state, stop, State#state{node_counter = N + 1, active_nodes = [Node | Nodes], passive_nodes = lists:delete(Node, PassiveNodes), node_activity = maps:put(Node, true, Activities)}};

stop({pool_down, Node}, #state{indicator = Ind, node_counter = N, active_nodes = Nodes, passive_nodes = PassiveNodes, node_activity = Activities} = State) ->
  NewInd =
    case maps:get(Node, Activities, true) of
      true -> Ind;
      false -> Ind - 1
    end,
  NextState =
    case NewInd + 1 of
      N -> start;
      _ -> stop
    end,
  ?D({stop, NextState}),
  {next_state, NextState, State#state{indicator = NewInd, node_counter = N - 1, active_nodes = lists:delete(Node, Nodes), passive_nodes = [Node | PassiveNodes]}};

stop({pool_enabled, Node}, #state{indicator = Ind, node_activity = Activities} = State) ->
  {next_state, stop, State#state{indicator = Ind - 1, node_activity = maps:put(Node, true, Activities)}};

stop({pool_disabled, Node}, #state{indicator = Ind, node_counter = N, node_activity = Activities} = State) when N == Ind + 1 ->
  ?D({stop, monitoring}),
  {next_state, monitoring, State#state{indicator = Ind + 1, node_activity = maps:put(Node, false, Activities)}};

stop({pool_disabled, Node}, #state{indicator = Ind, node_activity = Activities} = State) ->
  {next_state, stop, State#state{indicator = Ind + 1, node_activity = maps:put(Node, false, Activities)}};

stop(high_idle_time, State) ->
  ?D({stop, monitoring}),
  {next_state, monitoring, State};

stop(_Event, State) ->
  {next_state, stop, State}.

handle_event(_Event, StateName, State) ->
  {next_state, StateName, State}.

handle_sync_event(_Event, _From, StateName, State) ->
  Reply = ok,
  {reply, Reply, StateName, State}.

handle_info(start, start_monitor, #state{category = Category, instances = InstanceList} = State) ->
  {ok, Re} = re:compile(?Regex),
  IdToNode =
    fun
      (Id, {Map, Nodes}) ->
        {match, [Ip]} = re:run(aws_cli:instance(Id), Re, [{capture, [ip], list}]),
        Node = ?Node(Category, Ip),
        {maps:put(Node, Id, Map), [Node | Nodes]}
    end,
  {NodeToId, AllNodes} = lists:foldl(IdToNode, {#{}, []}, InstanceList),
  fyler_event:add_sup_handler(fyler_listener_to_monitor, [Category, self()]),
  NodeCounter =
    fun
      (#pool{node = Node, enabled = true, category = C}, {Nodes, Ind}) when C == Category -> {[Node, Nodes], Ind};
      (#pool{node = Node, enabled = false, category = C}, {Nodes, Ind}) when C == Category -> {[Node, Nodes], Ind};
      (_, {Nodes, Ind}) -> {Nodes, Ind}
    end,
  {ActiveNodes, Indicator} = ets:foldl(NodeCounter, {[], 0}, ?T_POOLS),
  PassiveNodes = lists:subtract(AllNodes, ActiveNodes),
  ?I({fyler_monitor_pool_started, Category}),
  {next_state, monitoring, State#state{indicator = Indicator, node_counter = length(ActiveNodes), active_nodes = ActiveNodes, passive_nodes = PassiveNodes, node_to_id = NodeToId}};

handle_info({stop, Ref}, stop, #state{active_nodes = [Node |_], node_to_id = NodeToId, stop_ref = Ref} = State) ->
  ?D({stop_instance, Node}),
  ?D({stop, monitoring}),
  aws_cli:stop_instance(maps:get(Node, NodeToId)),
  {next_state, monitoring, State};

handle_info({stop, _Ref}, pre_stop, #state{timer = Timer} = State) ->
  ?D({pre_stop, stop}),
  Ref = make_ref(),
  erlang:send_after(Timer, self(), {stop, Ref}),
  {next_state, stop, State#state{stop_ref = Ref}};

handle_info({start, _Ref}, pre_stop, #state{timer = Timer} = State) ->
  ?D({pre_stop, stop}),
  Ref = make_ref(),
  erlang:send_after(Timer, self(), {stop, Ref}),
  {next_state, stop, State#state{stop_ref = Ref}};

handle_info({start, Ref}, after_start, #state{start_ref = Ref} = State) ->
  ?D({after_start, monitoring}),
  {next_state, monitoring, State};

handle_info(_Info, StateName, State) ->
  {next_state, StateName, State}.

terminate(_Reason, _StateName, _State) ->
  ok.

code_change(_OldVsn, StateName, State, _Extra) ->
  {ok, StateName, State}.




-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

pool_disabled_test() ->
  State = #state{indicator = 10, node_counter = 12, node_activity = #{node => true}},
  ?assertEqual({next_state, monitoring, State#state{indicator = 11, node_activity = #{node => false}}}, monitoring({pool_disabled, node}, State)),
  ?assertEqual({next_state, start, State#state{indicator = 11, node_activity = #{node => false}}}, start({pool_disabled, node}, State)),
  ?assertEqual({next_state, monitoring, State#state{indicator = 12, node_activity = #{node => false}}}, monitoring({pool_disabled, node}, State#state{indicator = 11})),
  ?assertEqual({next_state, start, State#state{indicator = 12, node_activity = #{node => false}, passive_nodes = [node]}}, monitoring({pool_disabled, node}, State#state{indicator = 11, passive_nodes = [node]})),
  ?assertEqual({next_state, monitoring, State#state{indicator = 12, node_activity = #{node => false}}}, stop({pool_disabled, node}, State#state{indicator = 11})),
  ?assertEqual({next_state, stop, State#state{indicator = 11, node_activity = #{node => false}}}, stop({pool_disabled, node}, State)),
  ?assertEqual({next_state, after_start, State#state{indicator = 11, node_activity = #{node => false}}}, after_start({pool_disabled, node}, State)).

pool_enabled_test() ->
  State = #state{indicator = 10, node_counter = 12, node_activity = #{node => false}},
  ?assertEqual({next_state, pre_stop, State#state{indicator = 9, node_activity = #{node => true}}, 1000}, monitoring({pool_enabled, node}, State)),
  ?assertEqual({next_state, monitoring, State#state{indicator = 9, node_activity = #{node => true}}}, start({pool_enabled, node}, State)),
  ?assertEqual({next_state, stop, State#state{indicator = 9, node_activity = #{node => true}}}, stop({pool_enabled, node}, State)),
  ?assertEqual({next_state, after_start, State#state{indicator = 9, node_activity = #{node => true}}}, after_start({pool_enabled, node}, State)).

pool_down_test() ->
  State1 = #state{indicator = 10, node_counter = 12, active_nodes = [node], node_activity = #{node => false}},
  State2 = #state{indicator = 10, node_counter = 12, active_nodes = [node], node_activity = #{node => true}},
  ?assertEqual({next_state, monitoring, State1#state{indicator = 9, node_counter = 11, active_nodes = [], passive_nodes = [node], node_activity = #{node => false}}}, monitoring({pool_down, node}, State1)),
  ?assertEqual({next_state, monitoring, State1#state{indicator = 10, node_counter = 11, active_nodes = [], passive_nodes = [node], node_activity = #{node => true}}}, monitoring({pool_down, node}, State2)),
  ?assertEqual({next_state, stop, State1#state{indicator = 9, node_counter = 11, active_nodes = [], passive_nodes = [node], node_activity = #{node => false}}}, stop({pool_down, node}, State1)),
  ?assertEqual({next_state, stop, State2#state{indicator = 10, node_counter = 11, active_nodes = [], passive_nodes = [node], node_activity = #{node => true}}}, stop({pool_down, node}, State2)),
  ?assertEqual({next_state, after_start, State2#state{indicator = 10, node_counter = 11, active_nodes = [], passive_nodes = [node], node_activity = #{node => true}}}, after_start({pool_down, node}, State2)).

pool_connected_test() ->
  State = #state{indicator = 10, node_counter = 11, active_nodes = [node], node_activity = #{node => false}},
  ?assertEqual({next_state, pre_stop, State#state{indicator = 10, node_counter = 12, active_nodes = [new_node, node], node_activity = #{new_node => true, node => false}}, 1000}, monitoring({pool_connected, new_node}, State)),
  ?assertEqual({next_state, monitoring, State#state{indicator = 10, node_counter = 12, active_nodes = [new_node, node], node_activity = #{new_node => true, node => false}}}, start({pool_connected, new_node}, State)),
  ?assertEqual({next_state, stop, State#state{indicator = 10, node_counter = 12, active_nodes = [new_node, node], node_activity = #{new_node => true, node => false}}}, stop({pool_connected, new_node}, State)),
  ?assertEqual({next_state, monitoring, State#state{indicator = 10, node_counter = 12, active_nodes = [new_node, node], node_activity = #{new_node => true, node => false}}}, after_start({pool_connected, new_node}, State)).

-endif.


