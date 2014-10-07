-module(tasks_handler).
-include("../fyler.hrl").
-include("../include/log.hrl").
%% Cowboy_http_handler callbacks
-export([
  init/2
]).

init(Req, Opts) ->
  Params = cowboy_req:parse_qs(Req),
  HTML = jiffy:encode(fyler_server:tasks_stats(lists:map(fun({Key, Value}) -> {binary_to_atom(Key, utf8), Value} end, Params))),
  Req2 = cowboy_req:reply(200, [], HTML, Req),
  {ok, Req2, Opts}.