-module(stats_handler).
-behaviour(cowboy_http_handler).
-include("../fyler.hrl").
%% Cowboy_http_handler callbacks
-export([
  init/3,
  handle/2,
  terminate/3
]).

init({tcp, http}, Req, _Opts) ->
  {ok, Req, undefined_state}.

handle(Req, State) ->
  {ok, HTML} = stats_tpl:render([{records, [lists:zip(record_info(fields, job_stats), tl(tuple_to_list(R))) || R <- ets:tab2list(?T_STATS)]}]),
  {ok, Req2} = cowboy_req:reply(200, [], HTML, Req),
  {ok, Req2, State}.

terminate(_Reason, _Req, _State) ->
  ok.