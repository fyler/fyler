%%% @doc Failing task
%%% @end

-module(do_fail).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/2, run/1, category/0]).

-define(COMMAND(In), os:cmd("sleep 1")).

category() ->
  test.

run(X) ->
  run(X,[]).

run(_,_Opts) ->
  Start = ulitos:timestamp(),
  ?D(?COMMAND(Path)),
  jiffy:decode("{\"copyright\":\"© 2008 Microsoft Corporation\"}"), % this cause an error
  {ok,#job_stats{time_spent = ulitos:timestamp() - Start}}.



