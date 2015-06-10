%%% @doc Convert any video to hls with h264 and aac.
%%% @end 

-module(video_to_hls).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2, category/0]).

-define(COMMAND(In,Out,Params), 
  "ffmpeg -i "++In++" "++Params++" -hls_time 10 -hls_list_size 0 "++Out
  ).

category() ->
  video.

run(File) -> run(File, []).

run(#file{tmp_path = Path, name = Name, dir = Dir}, _Opts) ->
  Start = ulitos:timestamp(),
  M3U = filename:join(Dir, Name ++ ".m3u8"),

  Info = video_probe:info(Path),

  Command = ?COMMAND(Path, M3U, video_to_mp4:info_to_params(Info)),

  ?D({"command", Command}),
  Data = exec(Command),
  case filelib:wildcard("*.m3u8", Dir) of
    [] -> {error, Data};
    _List ->
      Result = Name ++ ".m3u8",
      {ok, #job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Result)]}}
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