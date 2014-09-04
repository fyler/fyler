%%% @doc Module handling generating thumb from pdf
%%% @end

-module(pdf_thumb).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2,category/0]).

-define(COMMAND(In,OutName), "gs -dNOPAUSE -dBATCH -dSAFER -sDEVICE=png16m -dFirstPage=1 -dLastPage=1 -sOutputFile=\""++OutName++"\" -r15 -q \""++In++"\" -c quit").

category() ->
  document.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir},_Opts) ->
  Start = ulitos:timestamp(),
  Out = filename:join(Dir,Name ++"_thumb.png"),
  ?D({"command",?COMMAND(Path,Out)}),
  Data = os:cmd(?COMMAND(Path,Out)),
  ?D({gs_data,Data}),
  case  filelib:is_file(Out) of
    true -> {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Name ++"_thumb.png")]}};
    _ -> {error, {pdf_thumb_failed,Data}}
  end.







