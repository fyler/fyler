%%% @doc Module handling pdf splitting and pages
%%% @end

-module(pdf_split_pages).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2,category/0]).

category() ->
  document.

run(File) -> run(File, []).

run(#file{name = Name, dir = Dir} = File, Opts) ->
  Start = ulitos:timestamp(),
  case split_pdf:run(File, Opts) of
    {ok, #job_stats{result_path = [PDF]}} -> case pdf_to_pages:run(#file{tmp_path = Dir++"/"++binary_to_list(PDF), name = Name, dir = Dir}) of
                                               {ok, #job_stats{result_path = Pages}} -> case pdf_to_thumbs:run(#file{tmp_path = Dir++"/"++binary_to_list(PDF), name = Name, dir = Dir}) of
                                                                                          {ok, #job_stats{result_path = Thumbs}} ->
                                                                                            {ok, #job_stats{time_spent = ulitos:timestamp() - Start, result_path = PDF ++ Pages ++ Thumbs}};
                                                                                          Else -> Else
                                                                                        end;
                                               Else -> Else
                                             end;
    Else -> Else
  end.






