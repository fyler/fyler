%%% @doc Module handling document conversion with unoconv
%%% @end

-module(doc_to_pdf).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1,run/2, category/0]).

-define(COMMAND(In), lists:flatten(io_lib:format("unoconv -f pdf ~s",[In]))).

category() ->
  document.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir},_Opts) ->
  Start = ulitos:timestamp(),
  Command  = ?COMMAND(Path),
  ?D({"command", Command}),
  Data = exec(Command),
  PDF = filename:join(Dir, Name ++ ".pdf"),
  case  filelib:is_file(PDF) of
    true -> case pdf_thumb:run(#file{tmp_path = PDF, name = Name, dir = Dir}) of
              {ok,#job_stats{result_path = Thumb}} ->
                    {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Name ++ ".pdf")|Thumb]}};
              Else -> Else
            end;
    _ -> {error, {unoconv_failed,PDF,Data}}
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






