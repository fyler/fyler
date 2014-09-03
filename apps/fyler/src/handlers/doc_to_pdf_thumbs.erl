%%% @doc Module handling document conversion with unoconv  and thumbs generating
%%% @end

-module(doc_to_pdf_thumbs).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1,run/2,category/0]).

category() ->
  document.

run(File) -> run(File,[]).

run(#file{name = Name, dir = Dir} = File,Opts) ->
  Start = ulitos:timestamp(),
  case  doc_to_pdf:run(File,Opts) of
    {ok,#job_stats{result_path = [PDF|_Rest]}} ->  case pdf_to_thumbs:run(#file{tmp_path = Dir++"/"++binary_to_list(PDF), name = Name, dir = Dir}) of
              {ok,#job_stats{result_path = Thumbs}} -> {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [PDF]++Thumbs}};
              Else -> Else
            end;
    Else -> Else
  end.






