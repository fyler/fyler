%%% @doc Module handling archive with 'index.html' unpacking 
%%% @end

-module(unpack_html).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1,run/2, category/0]).

-define(COMMAND(In,Out), io_lib:format("7z -o~s x ~s",[Out,In])).

category() ->
  document.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir},_Opts) ->
  Start = ulitos:timestamp(),
  ?D({"command",?COMMAND(Path,Dir)}),
  Data = os:cmd(?COMMAND(Path,Dir)),
  FileName = "index.html",
  HTML = filename:join(Dir,FileName),
  case  filelib:is_file(HTML) of
    true -> 
          {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(FileName)]}};
    _ -> {error, {'7z_failed',HTML,Data}}
  end.






