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

%% API
start_link(#task{} = Task) ->
  gen_server:start_link(?MODULE, [Task], []).

%% gen_server callbacks
-record(state, {
  task :: task(),
  process :: pid(),
  stats ::stats(),
  download_time :: non_neg_integer()
}).

init([#task{type = Type, file = #file{url = Path}} = Task]) ->
  ?D({start_task, Path, Type, self()}),
  process_flag(trap_exit, true),
  self() ! download,
  lager:md([{context, {[{type, Type}, {path, list_to_binary(Path)}]}}]),
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
                   {ok,#file_info{size = Size2}} -> DTime = ulitos:timestamp() - Start,
                     self() ! process_start,
                     {DTime, Size2};
                   _ -> self() ! {error, {download_failed, Res}},
                     {undefined, undefined}
                 end,
  {noreply, State#state{task = Task#task{file = File#file{size = Size}}, download_time = Time}};


handle_info(download, #state{task = #task{file = #file{url = Path}}} = State) ->
  self() ! {error, {non_aws_download, Path}},
  {noreply, State};

handle_info(process_start, #state{task = #task{type = Type, file = File, options = Opts}} = State) ->
  Self = self(),
  Pid = case erlang:function_exported(Type,run,2) of
    true ->
      ?D({start_processing, File#file.name}),
    spawn_link(fun() ->
      case erlang:apply(Type, run, [File, Opts]) of
        {ok, Stats} -> Self ! {process_complete, Stats};
        {error, Reason} -> Self ! {error, Reason}
      end
    end);
    false -> self() ! {error, handler_not_found},
             undefined
   end,
  {noreply, State#state{process = Pid}};

handle_info({process_complete, Stats}, #state{task = #task{file = #file{name = Name, is_aws = true, bucket = Bucket, dir = Dir, target_dir = TargetDir}, acl = Acl}} = State) ->
  ?D({start_upload_processed_file, Name, TargetDir}),
  fyler_uploader:upload_to_aws(Bucket, Dir, TargetDir, Acl, self()),
  {noreply, State#state{stats = Stats}};

handle_info({upload_complete, UpTime}, #state{stats=Stats,task = #task{id = Id, file = #file{url = Path, size = Size}, type = Type} = Task, download_time = Time} = State) ->
  gen_server:cast(fyler_pool,{task_completed,Task, Stats#job_stats{id = Id, download_time = Time, upload_time = UpTime, file_path = Path, file_size = Size, status = success, task_type = Type, ts = ulitos:timestamp()}}),
  {stop, normal, State#state{process = undefined}};

handle_info({error, Reason}, #state{task = #task{id = Id, file = #file{url = Path, size = Size}, type = Type}=Task} = State) ->
  ?E({error,Reason}),
  gen_server:cast(fyler_pool,{task_failed,Task,#job_stats{id = Id, error_msg = Reason, status = failed, ts = ulitos:timestamp(), task_type = Type, file_path = Path, file_size = Size}}),
  {stop, normal, State#state{process = undefined}};

handle_info({'EXIT', _Pid, normal}, State) ->
  {noreply, State};

handle_info({'EXIT', Pid, Error}, #state{process = Pid, task = #task{id = Id, file = #file{url = Path, size = Size}, type = Type}=Task} = State) ->
  ?E({error, Error}),
  gen_server:cast(fyler_pool,{task_failed,Task,#job_stats{id = Id, error_msg = Error, status = failed, ts = ulitos:timestamp(), task_type = Type, file_path = Path, file_size = Size}}),
  {stop, normal, State};

handle_info(_,State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

