%% Copyright
-module(fyler_worker).
-author("palkan").
-include_lib("kernel/include/file.hrl").
-include("../include/log.hrl").
-include("fyler.hrl").

-behaviour(gen_server).

%% API
-export([start_link/1]).

%% gen_server
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).

-export([download_strategy/1]).

%% API
start_link(#task{} = Task) ->
  gen_server:start_link(?MODULE, [Task], []).

%% gen_server callbacks
-record(state, {
  task :: task(),
  process :: pid(),
  download_time :: non_neg_integer()
}).

init([#task{type = Type, file = #file{url = Path}} = Task]) ->
  ?D({start_task, Path, Type, self()}),
  process_flag(trap_exit, true),
  self() ! download,
  {ok, #state{task = Task}}.

handle_call(_Request, _From, State) ->
  {noreply, State}.

handle_cast(_Request, State) ->
  {noreply, State}.


handle_info(download, #state{task = #task{file = #file{url = Path, tmp_path = Tmp, is_aws = true} = File} = Task} = State) ->
  Start = ulitos:timestamp(),
  ?D({copy_from_aws_to, Tmp}),
  Res = aws_cli:copy_object("s3://" ++ Path, Tmp),
  {Time, Size} = case file:read_file_info(Tmp) of
                   #file_info{size = Size2} -> DTime = ulitos:timestamp() - Start,
                     self() ! process_start,
                     {DTime, Size2};
                   _ -> self() ! {error, {download_failed, Res}},
                     {undefined, undefined}
                 end,
  {noreply, State#state{task = Task#task{file = File#file{size = Size}}, download_time = Time}};


handle_info(download, #state{task = #task{file = #file{url = Path, tmp_path = Tmp} = File} = Task} = State) ->
  Start = ulitos:timestamp(),
  ?D({download_to, Tmp}),
  {Time, Size2} = case http_file:download(Path, [{cache_file, Tmp}, {strategy, fun fyler_worker:download_strategy/1}]) of
                    {ok, Size} -> DTime = ulitos:timestamp() - Start,
                      self() ! process_start,
                      {DTime, Size};
                    {error, Code} -> self() ! {error, {download_failed, Code}},
                      {undefined, undefined}
                  end,
  {noreply, State#state{task = Task#task{file = File#file{size = Size2}}, download_time = Time}};

handle_info(process_start, #state{task = #task{type = Type, file = File, options = Opts}} = State) ->
  Self = self(),
  Pid = spawn_link(fun() ->
    case erlang:apply(Type, run, [File, Opts]) of
      {ok, Stats} -> Self ! {process_complete, Stats};
      {error, Reason} -> Self ! {error, Reason}
    end
  end),
  {noreply, State#state{process = Pid}};

handle_info({process_complete, Stats}, #state{task = #task{file = #file{is_aws = true, dir = Dir}} = Task, download_time = Time} = State) ->
  ok = gen_server:call(fyler_server,{move_to_aws,Dir}),
  fyler_event:task_completed(Task, Stats#job_stats{download_time = Time}),
  {stop, normal, State};

handle_info({process_complete, Stats}, #state{task = Task, download_time = Time} = State) ->
  fyler_event:task_completed(Task, Stats#job_stats{download_time = Time}),
  {stop, normal, State};

handle_info({error, Reason}, #state{task = Task} = State) ->
  fyler_event:task_failed(Task, Reason),
  {stop, normal, State};

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


-spec download_strategy(Size :: non_neg_integer()) -> {Chunked :: boolean(), Threads :: non_neg_integer()}.

download_strategy(Size) when Size > 1024 * 1024 * 20 ->
  {true, 2};

download_strategy(_Size) -> {false, 0}.

