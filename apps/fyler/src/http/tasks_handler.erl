-module(tasks_handler).
-behaviour(cowboy_http_handler).
-include("../fyler.hrl").
-include("../include/log.hrl").
%% Cowboy_http_handler callbacks
-export([
  init/3,
  handle/2,
  terminate/3
]).

init({tcp, http}, Req, _Opts) ->
  {ok, Req, undefined_state}.

handle(Req, State) ->
  Params = case cowboy_req:qs_vals(Req) of
    {Data, _} -> 
      Opts = proplists:get_keys(Data),
      [{binary_to_atom(Opt,utf8),proplists:get_value(Opt, Data)} || Opt <- Opts];
    _Else -> ?D(_Else), []
  end,
  HTML = jiffy:encode(fyler_server:tasks_stats(Params)),
  {ok, Req2} = cowboy_req:reply(200, [], HTML, Req),
  {ok, Req2, State}.

terminate(_Reason, _Req, _State) ->
  ok.