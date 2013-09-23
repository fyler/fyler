-module(auth_handler).
-include("../../include/log.hrl").


-export([
  init/3,
  process_post/2,
  allowed_methods/2,
  content_types_accepted/2,
  terminate/3
]).

init({tcp, http}, _Req, _Opts) ->
  {upgrade, protocol, cowboy_rest}.

content_types_accepted(Req, State) ->
  {[{'*',process_post}],Req,State}.

allowed_methods(Req, State) ->
  {[<<"POST">>], Req, State}.

process_post(Req, State) ->
  case cowboy_req:body_qs(Req) of
    {ok, X, _} ->
      case validate_post_data(X) of
        [Login,Pass] -> case fyler_server:authorize(Login,Pass) of
                          {ok,Token} -> ?D({authorized,Token}),
                                        {ok, Req2} = cowboy_req:reply(200, [], jiffy:encode({[{token, list_to_binary(Token)}]}), Req),
                                        {halt,Req2,State};
                          false -> {ok, Req2} = cowboy_req:reply(401, Req),
                                   {halt,Req2,State}
                        end;
        false -> {ok, Req2} = cowboy_req:reply(401, Req),
                 {halt,Req2,State}
      end;
    _ -> {ok, Req2} = cowboy_req:reply(401, Req),
         {halt,Req2,State}
  end.

validate_post_data(Data) ->
  ?D(Data),
  Keys = [<<"login">>, <<"pass">>],
  BinData = [proplists:get_value(Key, Data) || Key <- Keys],
  Reply = [X || X <- BinData, X =/= undefined],
  if length(Reply) == length(Keys) ->
    Reply;
    true -> false
  end.

terminate(_Reason, _Req, _State) ->
  ok.