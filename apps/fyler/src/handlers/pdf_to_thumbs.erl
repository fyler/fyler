%%% @doc Module handling generating thumbs from pdf
%%% @end

-module(pdf_to_thumbs).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2,category/0]).

category() ->
  document.

-define(COMMAND(In,OutName), "gs -dNOPAUSE -dBATCH -dSAFER -sDEVICE=png16m  -sOutputFile=\""++OutName++"thumb_%04d.png\" -r15 -q \""++In++"\" -c quit").

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir},_Opts) ->
  Start = ulitos:timestamp(),
  ThumbDir = filename:join(Dir,"thumbs"),
  file:make_dir(ThumbDir),
  ?D({"command",?COMMAND(Path,ThumbDir++"/")}),
  Data = exec(?COMMAND(Path,ThumbDir++"/")),
  ?D({gs_data,Data}),
  case filelib:wildcard("*.png",ThumbDir) of
    [] -> {error,Data};
    List -> JSON = jiffy:encode({
                    [
                      {name,list_to_binary(Name)},
                      {dir,<<"thumbs">>},
                      {length,length(List)},
                      {thumbs,[list_to_binary(T) || T <- List]}
                    ]
           } ),
            JSONFile = filename:join(Dir,Name++".thumbs.json"),
            {ok,F} = file:open(JSONFile,[write]),
            file:write(F,JSON),
            file:close(F),
            {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Name++".thumbs.json")]}}
  end.

exec(Command) ->
  {ok, _, _} = exec:run(Command, [stdout, monitor]),
  loop(<<>>).

loop(Data) ->
  receive
    {stdout, _, Part} ->
      loop(<<Data/binary, Part/binary>>);
    _ ->
      Data
  end.







