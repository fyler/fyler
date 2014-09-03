%%% @doc Do nothing with file; just print file stat with 2 seconds delay (use for debug only).
%%% @end

-module(do_nothing).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/2, category/0]).

-define(COMMAND(In), os:cmd("sleep 2 && stat " ++ In)).

category() ->
  test.

run(#file{tmp_path = Path},_Opts) ->
  Start = ulitos:timestamp(),
  ?D(?COMMAND(Path)),
  {ok,#job_stats{time_spent = ulitos:timestamp() - Start}}.



