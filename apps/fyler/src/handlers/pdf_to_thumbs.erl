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
  ThumbDir = Dir++"/thumbs",
  ok = file:make_dir(ThumbDir),
  ?D({"command",?COMMAND(Path,ThumbDir++"/"++Name)}),
  Data = os:cmd(?COMMAND(Path,ThumbDir++"/"++Name)),
  ?D({gs_data,Data}),
  case filelib:wildcard("*.png",Dir) of
    [] -> {error,Data};
    List -> JSON = mochijson2:encode({struct,
                    [
                      {<<"name">>,Name},
                      {<<"dir">>,<<"thumbs">>},
                      {<<"length">>,length(List)},
                      {<<"thumbs">>,List}
                    ]
                  }
            ),
            JSONFile = Name++".json",
            {ok,F} = file:open(JSONFile,[write]),
            file:write(F,JSON),
            file:close(F),
            {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = JSONFile}}
  end.







