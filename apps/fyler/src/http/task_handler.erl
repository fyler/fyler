-module(task_handler).
-include("../../include/log.hrl").


-export([
  init/3,
  process_post/2,
  allowed_methods/2,
  content_types_accepted/2,
  content_types_provided/2,
  to_json/2,
  terminate/3
]).

init({tcp, http}, _Req, _Opts) ->
  {Method,_} = cowboy_req:method(_Req),
  ?D({method,Method}),
  {upgrade, protocol, cowboy_rest}.

content_types_accepted(Req, State) ->
  {[{'*',process_post}],Req,State}.

content_types_provided(Req, State) ->
  {[{{<<"text">>, <<"html">>, '*'}, to_json}],Req,State}.

allowed_methods(Req, State) ->
  {[<<"GET">>, <<"POST">>, <<"DELETE">>], Req, State}.

to_json(Req,State) ->
  {true,Req,State}.

process_post(Req, State) ->
  case cowboy_req:body_qs(Req) of
    {ok, X, _} ->
      case validate_post_data(X) of
        [Url, Type] -> ?D({post_data, Url, Type}), fyler_server:run_task(Url, Type, []);
        false -> ?D(<<"wrong post data">>)
      end;
    _ -> ?D(<<"no data">>)
  end,
  {true, Req, State}.

validate_post_data(Data) ->
  BinData = [proplists:get_value(Key, Data, undefined) || Key <- [<<"url">>, <<"type">>]],
  Reply = [binary_to_list(X) || X <- BinData, X =/= undefined],
  if length(Reply) == 2 ->
    Reply;
    true -> false
  end.

terminate(_Reason, _Req, _State) ->
  ok.