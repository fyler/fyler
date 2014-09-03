%%% @doc Module handling swf  and thumbs generation
%%% @end

-module(pdf_to_swf_thumbs).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1,run/2,category/0]).

category() ->
  document.

run(File) -> run(File,[]).

run(File,Opts) ->
  Start = ulitos:timestamp(),
  case  pdf_to_swf:run(File,Opts) of
    {ok,#job_stats{result_path = SWF}} ->  case pdf_to_thumbs:run(File) of
              {ok,#job_stats{result_path = Thumbs}} -> {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = SWF++Thumbs}};
              Else -> Else
            end;
    Else -> Else
  end.






