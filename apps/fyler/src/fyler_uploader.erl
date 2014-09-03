-module(fyler_uploader).
-author("palkan").
-include("../include/log.hrl").
-include_lib("fyler.hrl").

-behaviour(gen_server).

%% API
-export([start_link/0, upload_to_aws/5]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-define(AWS_URL(B,F),"http://"++B++".s3.amazonaws.com/"++F).

-record(state, {
  queue = queue:new() ::queue:queue()
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).


%% @doc
%% Move dir to aws bucket
%% @end

-spec upload_to_aws(Bucket::string(),Dir::string(),TargetDir::string(),Acl::atom(), Handler::pid()) -> ok | queued | {error,Error::any()}.

upload_to_aws(Bucket,Dir,TargetDir,Acl,Handler) ->
  gen_server:call(?SERVER,{upload,Bucket,Dir,TargetDir,Acl,Handler}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
  {ok,#state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------

handle_call(Request,_,#state{queue = Queue}=State) ->
  ?D({queue_request, Request}),
  NewQueue = queue:in(Request,Queue),
  self() ! next_task,
  {reply,queued,State#state{queue = NewQueue}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------

handle_cast(_Msg, State) ->
  {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------


handle_info(next_task,#state{queue = Queue} = State) ->
  NewState = case queue:out(Queue) of
    {empty,_} -> ?D(no_more_tasks), State;
    {{value,Task},Queue2} -> {reply,_,State_} = handle_task(Task,State#state{queue = Queue2}),
                             self() ! next_task,
                             State_
  end,
  {noreply,NewState};


handle_info(_Info, State) ->
  {noreply, State}.


%% @doc
%% Handle queued task.
%% @end

-spec handle_task(Task::any(),State::#state{}) -> {reply,Reply::any(),NewState::#state{}}.

handle_task({upload,Bucket,Dir,TargetDir,Acl,Handler}, State) ->
  Reply = case filelib:is_dir(Dir) of
            true -> AWSPath = ?AWS_URL(Bucket,TargetDir),
              Start = ulitos:timestamp(),
              Res = aws_cli:copy_folder(Dir,AWSPath,Acl),
              UpTime = ulitos:timestamp() - Start,
              case aws_cli:dir_exists(AWSPath) of
                true ->
                  ulitos_file:recursively_del_dir(Dir),
                  {upload_complete, UpTime};
                false -> 
                  ?E({aws_sync_error,Res}),
                  {error, aws_sync_failed}
              end;
            _ -> 
              ?E({dir_not_found,Dir}),
              {error, dir_not_found}
          end,
  
  if is_pid(Handler) 
    ->
      Handler ! Reply;
    true -> ok
  end,

  {reply,Reply,State};


handle_task(_Task,State) -> {reply,undefined,State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
  ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-define(setup(F), {setup, fun setup_/0, fun cleanup_/1, F}).

setup_() ->
  meck:new(aws_cli,[non_strict]),
  meck:expect(aws_cli, copy_folder, fun(_,_,_) -> timer:sleep(1000) end),
  meck:expect(aws_cli, dir_exists, fun(_) -> true end),
  filelib:ensure_dir("./tmp/test"),
  file:make_dir("./tmp/test"),
  lager:start(),
  {ok,Pid} = fyler_uploader:start_link(),
  erlang:unlink(Pid),
  Pid.

cleanup_(Pid) ->
  meck:unload(aws_cli),
  application:stop(lager),
  erlang:exit(Pid,kill).

handle_task_test_() ->
  [
    {"handle task tests", ?setup(fun(X) ->
        [
          add_task_t_(X),
          complete_task_t_(X),
          wrong_dir_t_(X)
        ]
        end
      )
    }
  ].

add_task_t_(_) ->
  [
    ?_assertEqual(queued,fyler_uploader:upload_to_aws("", "./tmp/test_1", "", "", self()))
  ].

complete_task_t_(_) ->
  [
    fun() ->
      fyler_uploader:upload_to_aws("", "./tmp/test", "", "", self()),
      receive
        {upload_complete,_} -> 
          ?assertNot(filelib:is_dir("./tmp/test"))
      after 1500
        -> ?assert(false)
      end
    end
  ].

wrong_dir_t_(_) ->
  [
    fun() ->
      fyler_uploader:upload_to_aws("", "./tmperqwe/test", "", "", self()),
      receive
        {error,Error} -> ?assertEqual(dir_not_found, Error)
      after 1500
        -> ?assert(false)
      end
    end
  ].


-endif.