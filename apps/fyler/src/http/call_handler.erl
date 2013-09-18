-module(call_handler).
-behaviour(cowboy_http_handler).
%% Cowboy_http_handler callbacks
-export([
  init/3,
  handle/2,
  terminate/3
]).

init({tcp, http}, Req, _Opts) ->
  {ok, Req, undefined_state}.

handle(Req, State) ->
  {Bin,_} = cowboy_req:binding(call,Req,<<"none">>),
  Call = binary_to_atom(Bin,latin1),
  Body = case erlang:function_exported(fyler_server,Call,0) of
    true ->  fyler_server:Call(),
             <<"Ok">>;
    _ -> <<"Not found">>
  end,
  {ok, Req2} = cowboy_req:reply(200, [], Body, Req),
  {ok, Req2, State}.

terminate(_Reason, _Req, _State) ->
  ok.