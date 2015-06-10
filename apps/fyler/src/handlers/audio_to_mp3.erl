%%% @doc Convert any audio to mp3.
%%% @end 

-module(audio_to_mp3).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2,category/0]).

-define(COMMAND(In,Out,Params), 
  lists:flatten(io_lib:format("ffmpeg -i ~s ~s ~s",[In,Params,Out]))
  ).

category() ->
 video.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir, extension = Ext}, _Opts) ->
  Start = ulitos:timestamp(),

  NewName = if Ext =:= "mp3" 
      -> Name ++ "_converted";
      true -> Name
  end,

  MP3 = filename:join(Dir, NewName ++ ".mp3"),

  Command = ?COMMAND(Path, MP3, " -c:a libmp3lame -ac 2 -ar 48000 -ab 192k "),

  ?D({"command",Command}),
  Data = exec(Command),
  case filelib:wildcard("*.mp3", Dir) of
    [] -> {error,Data};
    _List ->
      Result = NewName++".mp3",
      {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Result)]}}
  end.

exec(Command) ->
  {ok, _, _} = exec:run(Command, [stderr, monitor]),
  loop(<<>>).

loop(Data) ->
  receive
    {stderr, _, Part} ->
      loop(<<Data/binary, Part/binary>>);
    _ ->
      Data
  end.
