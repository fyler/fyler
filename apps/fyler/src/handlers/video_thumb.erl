%%% @doc Create poster and thumb from video
%%% @end

-module(video_thumb).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2,category/0]).

-define(COMMAND(In,Out), 
  io_lib:format("ffmpeg -i ~s -vframes 1 -map 0:v:0 ~s",[In,Out])
  ).

category() ->
 video.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir},Opts) ->
  Start = ulitos:timestamp(),
  
  Poster = filename:join(Dir,Name++"_poster.png"),

  Command = ?COMMAND(Path,Poster),

  ?D({"command",Command}),
  Data = os:cmd(Command),
  case filelib:wildcard("*_poster.png",Dir) of
    [] -> {error,Data};
    _List ->
            Result = list_to_binary(Name++"_poster.png"), 
            case image_thumb:run(#file{tmp_path = Poster, name = Name, dir = Dir},Opts) of
              {ok,#job_stats{result_path = Thumb}} ->
                {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [Result|Thumb]}};
              Else -> 
                ?E({image_thumb_failed, Else}),
                {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [Result]}}
            end
  end.
