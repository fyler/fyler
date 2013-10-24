%%% @doc Module handling generating thumb from image
%%% @end

-module(image_thumb).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2]).

-define(COMMAND(In,OutName), "convert \""++In++"\" -resize 100 \""++Out++"\"").

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir},_Opts) ->
  Start = ulitos:timestamp(),
  Out = Dir++"/"++Name ++"_thumb.png",
  ?D({"command",?COMMAND(Path,Out)}),
  Data = os:cmd(?COMMAND(Path,Out)),
  ?D({imagemagick_data,Data}),
  case  filelib:is_file(Out) of
    true -> {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Out)]}};
    _ -> {error, Data}
  end.







