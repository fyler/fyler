%%% @doc Convert any video to hls with h264 and aac.
%%% @end 

-module(video_to_hls).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2,category/0]).

-define(COMMAND(In,Out,Params), 
  "ffmpeg -i "++In++" "++Params++" -hls_time 10 -hls_list_size 999 "++Out
  ).

category() ->
 video.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir},_Opts) ->
  Start = ulitos:timestamp(),
  M3U = filename:join(Dir,Name++".m3u8"),

  Info = video_probe:info(Path),

  Command = ?COMMAND(Path,M3U, get_params(Info)),

  ?D({"command",Command}),
  Data = os:cmd(Command),
  case filelib:wildcard("*.m3u8",Dir) of
    [] -> {error,Data};
    _List ->
      Result = Name++".m3u8",
      {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Result)]}}
  end.


get_params(#video_info{audio_codec = Audio, video_codec = Video, video_size = Size, pixel_format = Pix}=_Info) ->
  video_codec(Video)++pixel_format(Pix)++video_size(Size)++audio_codec(Audio).

audio_codec(undefined) ->
  " -an ";

audio_codec([]) ->
  " -an ";

audio_codec("aac") ->
  " -c:a copy ";

audio_codec("mp3") ->
  " -c:a copy ";

audio_codec(_) ->
  " -c:a libfdk_aac -ac 2 -ar 48000 -ab 192k ".

video_codec(undefined) ->
  " -vn ";

video_codec([]) ->
  " -vn ";

video_codec("h264") ->
  " -c:v copy ";

video_codec(_) ->
  " -vcodec libx264 -profile:v baseline -preset slower -crf 18 ".

pixel_format("yuv420p") ->
  "";

pixel_format(_) ->
  " -pix_fmt yuv420p ".

video_size(Size) when Size < 480 ->
  " -vf \"scale=trunc(in_w/2)*2:trunc(in_h/2)*2\" ";

video_size(Size) when Size < 500 ->
  " -video_size hd480 ";

video_size(Size) when Size < 800 ->
  " -video_size hd720 ";

video_size(_Size) ->
  " -video_size hd1080 ".