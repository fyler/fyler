%%% @doc Module handling generating thumbs from pdf
%%% @end

-module(pdf_to_thumbs).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2]).

-define(COMMAND(In,OutName), "gs -dNOPAUSE -dBATCH -dSAFER -sDEVICE=png16m  -sOutputFile=\""++OutName++"_%d.png\" -r15 -q \""++In++"\" -c quit").

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir},_Opts) ->
  Start = ulitos:timestamp(),
  ?D({"command",?COMMAND(Path,Dir++"/"++Name)}),
  Data = os:cmd(?COMMAND(Path,Dir++"/"++Name)),
  ?D({gs_data,Data}),
  ?D({thumbs, filelib:wildcard("*.png",Dir)}),
  {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = Name++".json"}}.






