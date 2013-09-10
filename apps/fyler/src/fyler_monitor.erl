%% Copyright
-module(fyler_monitor).
-author("palkan").
-include("../include/log.hrl").
-include("fyler.hrl").

-behaviour(gen_fsm).

%% API
-export([start_link/0]).
-export([start_monitor/0,stop_monitor/0]).

%% gen_server
-export([init/1, idle/2, idle/3, monitoring/2, monitoring/3,  handle_sync_event/4, handle_event/3, handle_info/3, terminate/3,
  code_change/4]).

-define(TIMEOUT,5000).

-record(state, {
listener ::pid()
}).

%% API
start_link() ->
  ?D({start_monitor}),
  cpu_sup:util(),
  gen_fsm:start_link({local, ?MODULE}, ?MODULE, [], []).


start_monitor() ->
  gen_fsm:send_event(?MODULE,start_monitor),
  ok.

stop_monitor() ->
  gen_fsm:send_event(?MODULE,stop_monitor),
  ok.


init(_Args) ->
  ?D(monitor_init),
  Pid = spawn_link(fyler_system_listener, listen, []),
  {ok, idle, #state{listener = Pid}}.


idle(start_monitor,State) ->
  print_stats(),
  {next_state,monitoring,State,?TIMEOUT};


idle(_Event, State) ->
  ?D({idle, unknown_event, _Event}),
  {next_state,idle,State}.

idle(_Event, _From, State) ->
  ?D({idle, unknown_sync_event,_Event}),
  {reply,undefined,idle,State}.

monitoring(timeout, State) ->
  print_stats(),
  {next_state,monitoring,State,?TIMEOUT};

monitoring(stop_monitor, State) ->
  print_stats(),
  {next_state,idle,State};

monitoring(_Event, State) ->
  ?D({monitoring, unknown_event, _Event}),
  {next_state,monitoring,State,?TIMEOUT}.

monitoring(_Event, _From, State) ->
  ?D({monitoring, unknown_sync_event, _Event}),
  {reply,undefined,monitoring,State, ?TIMEOUT}.


handle_sync_event(_Event, _From, StateName, State) ->
  {reply, undefined, StateName, State}.


handle_event(_Event, StateName, State) ->
  {next_state, StateName, State}.


handle_info(_Info, StateName, State) ->
  {next_state, StateName, State}.

print_stats() ->
  [{_, DiskTotal, DiskCap}|_Rest] = disksup:get_disk_data(),
  {MemTotal, MemAlloc,_} = memsup:get_memory_data(),
  NProcs = cpu_sup:nprocs(),
  CPU = cpu_sup:util(),
  ?D(iolist_to_binary(io_lib:format("Disk data: total ~p, capacity ~p.",[DiskTotal,DiskCap]))),
  ?D(iolist_to_binary(io_lib:format("Memory: total ~p, free ~p.",[MemTotal,MemAlloc]))),
  ?D(iolist_to_binary(io_lib:format("CPU: number of procs ~p, busy ~p%.",[NProcs,CPU]))).

terminate(_Reason, _StateName, _State) ->
  ok.

code_change(_OldVsn, StateName, State, _Extra) ->
  {ok, StateName, State}.
