-module(pools_handler).
-include("../fyler.hrl").
%% Cowboy_http_handler callbacks
-export([
  init/2
]).

init(Req, State) ->
  HTML = jiffy:encode(fyler_server:pools()),
  {true, cowboy_req:reply(200, [], HTML, Req), State}.