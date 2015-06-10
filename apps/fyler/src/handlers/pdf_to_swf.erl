%%% @doc Module handling generating swfs from pdf
%%% @end

-module(pdf_to_swf).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2,category/0]).

-define(COMMAND(In,OutDir), "pdf2swf -T 10 -f '"++In++"' -o '"++OutDir++"/slide%04d.swf'").

category() ->
  document.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir},_Opts) ->
  Start = ulitos:timestamp(),
  SDir = filename:join(Dir,"swfs"),
  file:make_dir(SDir),
  ?D({"command",?COMMAND(Path,SDir)}),
  Data = exec(?COMMAND(Path,SDir)),
  case filelib:wildcard("*.swf",SDir) of
    [] -> {error,Data};
    List -> JSON = jiffy:encode({
                    [
                      {name,list_to_binary(Name)},
                      {dir,<<"swfs">>},
                      {length,length(List)},
                      {slides,[list_to_binary(T) || T <- List]}
                    ]
           } ),
            JSONFile = filename:join(Dir,Name++".swfs.json"),
            {ok,F} = file:open(JSONFile,[write]),
            file:write(F,JSON),
            file:close(F),
            {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Name++".swfs.json")]}}
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







