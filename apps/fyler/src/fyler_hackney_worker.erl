-module(fyler_hackney_worker).
-behaviour(gen_server).
-behaviour(poolboy_worker).
-include("../include/log.hrl").
-include("fyler.hrl").

-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
  code_change/3]).

-record(state, {options}).

start_link(Args) ->
  gen_server:start_link(?MODULE, Args, []).

init(_) ->
  Options = [{<<"Content-Type">>, <<"application/x-www-form-urlencoded">>}],
  {ok, #state{options = Options}}.


handle_call({response, #task{callback = Callback, file = #file{is_aws = true, bucket = Bucket, target_dir = Dir}},
  #job_stats{status = success, result_path = Path}}, _From, #state{options = Options} = State) ->

  Data = jiffy:encode({[{path, Path}, {dir, list_to_binary(Dir)}]}),
  Request = iolist_to_binary("status=ok&aws=true&bucket=" ++ Bucket ++ "&data=" ++ Data),
  Response = hackney:post(Callback, Options, Request, []),
  {reply, Response, State};

handle_call({response, #task{callback = Callback},
  #job_stats{status = failed}}, _From, #state{options = Options} = State) ->

  Request = <<"status=failed">>,
  Response = hackney:post(Callback, Options, Request, []),
  {reply, Response, State};

handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast({response, #task{callback = Callback, file = #file{is_aws = true, bucket = Bucket, target_dir = Dir}},
  #job_stats{status = success, result_path = Path}}, #state{options = Options} = State) ->

  Data = jiffy:encode({[{path, Path}, {dir, list_to_binary(Dir)}]}),
  Request = iolist_to_binary("status=ok&aws=true&bucket=" ++ Bucket ++ "&data=" ++ Data),
  hackney:post(Callback, Options, Request, []),
  {noreply, State};

handle_cast({response, #task{callback = Callback},
  #job_stats{status = failed}}, #state{options = Options} = State) ->

  Request = <<"status=failed">>,
  hackney:post(Callback, Options, Request, []),
  {noreply, State};

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_, _) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
