-module(stats_handler).
-include("../fyler.hrl").
%% Cowboy_http_handler callbacks
-export([
  init/2
]).

init(Req, State) ->
  HTML = jiffy:encode(fyler_server:current_tasks()),
  {ok, cowboy_req:reply(200, [], HTML, Req), State}.