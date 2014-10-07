-module(auth_handler).
-include("../../include/log.hrl").


-export([
  init/2,
  process_post/2,
  allowed_methods/2,
  content_types_accepted/2
]).

init(Req, Opts) ->
  {cowboy_rest, Req, Opts}.

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
                                        Resp = cowboy_req:set_resp_header(<<"content-type">>, <<"application/json">>, Req),
                                        {halt, cowboy_req:reply(200, [], jiffy:encode({[{token, list_to_binary(Token)}]}), Resp), State};
                          false -> {halt, cowboy_req:reply(401, Req), State}
                        end;
        false -> {halt, cowboy_req:reply(401, Req), State}
      end;
    _ -> {halt, cowboy_req:reply(401, Req), State}
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