%%% @doc Module handling document conversion with unocovn
%%% @end

-module(doc_to_pdf).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/2]).

-define(COMMAND(In), os:cmd("unoconv -f pdf " ++ In)).


run(#file{tmp_path = Path},_Opts) ->
  Start = ulitos:timestamp(),
  Data = os:cmd(?COMMAND(Path)),
  ?D({"unoconv conversion: ", Data}),
  {ok,#job_stats{time_spent = ulitos:timestamp() - Start}}.



