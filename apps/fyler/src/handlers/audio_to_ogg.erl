%%% @doc Convert any audio to ogg.
%%% @end 

-module(audio_to_ogg).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2,category/0]).

-define(COMMAND(In,Out,Params),
  io_lib:format("ffmpeg -i ~s ~s ~s",[In,Params,Out])
).

category() ->
  video.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir, extension = Ext},_Opts) ->
  Start = ulitos:timestamp(),

  NewName = if Ext =:= "ogg"
    -> Name++"_converted";
              true -> Name
            end,

  Ogg = filename:join(Dir,NewName++".ogg"),

  Command = ?COMMAND(Path, Ogg, " -c:a libvorbis -ac 2 -ar 48000 -ab 192k "),

  ?D({"command",Command}),
  Data = os:cmd(Command),
  case filelib:wildcard("*.ogg",Dir) of
    [] -> {error,Data};
    _List ->
      Result = NewName++".ogg",
      {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Result)]}}
  end.