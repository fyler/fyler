%% Copyright
-module(fyler_monitor).
-author("palkan").
-include("../include/log.hrl").
-include("fyler.hrl").

-behaviour(gen_fsm).

-define(APPS, [os_mon]).

%% API
-export([start_link/0]).
-export([start_monitor/0, stop_monitor/0]).

%% gen_server
-export([init/1, idle/2, idle/3, monitoring/2, monitoring/3, handle_sync_event/4, handle_event/3, handle_info/3, terminate/3,
  code_change/4]).

-record(state, {
  listener :: pid(),
  alarm = false,
  timeout = 2000,
  cpu_max = 100
}).

%% API
start_link() ->
  ?D({start_monitor}),
  ulitos_app:ensure_started(?APPS),
  cpu_sup:util(),
  gen_fsm:start_link({local, ?MODULE}, ?MODULE, [], []).


start_monitor() ->
  gen_fsm:send_event(?MODULE, start_monitor),
  ok.

stop_monitor() ->
  gen_fsm:send_event(?MODULE, stop_monitor),
  ok.


init(_Args) ->
  ?D(monitor_init),
  Pid = spawn_link(fyler_system_listener, listen, []),
  {ok, idle, #state{listener = Pid, cpu_max = ?Config(cpu_high_watermark, 90), timeout = ?Config(cpu_check_timeout, 2000)}}.


idle(start_monitor, #state{alarm = true, cpu_max = Max, timeout = T} = State) ->
  CPU = cpu_sup:util(),
  Alarm = if  CPU < Max ->
    ?D({cpu_available,CPU}),
    fyler_pool:enable(),
    false;
    true ->
      true
  end,
  {next_state, monitoring, State#state{alarm = Alarm}, T};

idle(start_monitor, #state{cpu_max = Max, timeout = T} = State) ->
  CPU = cpu_sup:util(),
  Alarm = if CPU > Max ->
    ?D({cpu_busy,CPU}),
    fyler_pool:disable(),
    true;
    true ->
      false
  end,
  {next_state, monitoring, State#state{alarm = Alarm}, T};

idle(_Event, State) ->
  ?D({idle, unknown_event, _Event}),
  {next_state, idle, State}.

idle(_Event, _From, State) ->
  ?D({idle, unknown_sync_event, _Event}),
  {reply, undefined, idle, State}.

monitoring(timeout, #state{alarm = false, cpu_max = Max, timeout = T} = State) ->
  CPU = cpu_sup:util(),
  Alarm = if CPU > Max ->
    ?D({cpu_busy,CPU}),
    fyler_pool:disable(),
    true;
    true ->
      false
  end,
  {next_state, monitoring, State#state{alarm = Alarm}, T};

monitoring(timeout, #state{cpu_max = Max, timeout = T} = State) ->
  CPU = cpu_sup:util(),
  Alarm = if  CPU < Max ->
    ?D({cpu_available,CPU}),
    fyler_pool:enable(),
    false;
    true ->
      true
  end,
  {next_state, monitoring, State#state{alarm = Alarm}, T};

monitoring(stop_monitor, State) ->
  {next_state, idle, State};

monitoring(_Event, #state{timeout = T}=State) ->
  ?D({monitoring, unknown_event, _Event}),
  {next_state, monitoring, State, T}.

monitoring(_Event, _From, #state{timeout = T} = State) ->
  ?D({monitoring, unknown_sync_event, _Event}),
  {reply, undefined, monitoring, State, T}.


handle_sync_event(_Event, _From, StateName, State) ->
  {reply, undefined, StateName, State}.


handle_event(_Event, StateName, State) ->
  {next_state, StateName, State}.


handle_info(_Info, StateName, State) ->
  {next_state, StateName, State}.

terminate(_Reason, _StateName, _State) ->
  ok.

code_change(_OldVsn, StateName, State, _Extra) ->
  {ok, StateName, State}.
