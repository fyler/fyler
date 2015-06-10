%%% @doc Module handling generating thumb from image
%%% @end

-module(image_thumb).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2,category/0]).

category() ->
  document.

-define(COMMAND(In,OutName,Size), lists:flatten(io_lib:format("convert \"~s\" -resize ~p \"~s\"",[In,Size,OutName]))).

run(File) -> run(File, []).

run(#file{tmp_path = Path, name = Name, dir = Dir}, Opts) ->
  Start = ulitos:timestamp(),
  Out = filename:join(Dir, Name ++ "_thumb.png"),
  
  Size = case proplists:get_value(thumb_size, Opts) of
    undefined -> 100;
    Size_ -> Size_
  end,

  Command = ?COMMAND(Path, Out, Size),
  ?D({"command", Command}),

  Data = exec(Command),
  ?D({imagemagick_data, Data}),
  case  filelib:is_file(Out) of
    true -> {ok, #job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Name ++"_thumb.png")]}};
    _ -> {error, Data}
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








