%%% @doc Convert any video to webm with vp8 and vorbis.
%%% @end
-module(video_to_webm).
-author("ilia").

-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2, category/0]).

-define(COMMAND(In,Out,Params),
  "ffmpeg -i "++In++" "++Params++" "++Out
).

category() ->
  video.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, extension=Ext, dir = Dir},Opts) ->
  Start = ulitos:timestamp(),

  NewName = if Ext =:= "webm"
    -> Name++"_converted";
              true -> Name
            end,

  Webm = filename:join(Dir, NewName ++ ".webm"),

  Info = video_probe:info(Path),

  Command = ?COMMAND(Path, Webm, info_to_params(Info)),

  ?D({"command", Command}),
  Data = exec_command:run(Command, stderr),
  case filelib:wildcard("*.webm", Dir) of
    [] -> {error, Data};
    _List ->
      Result = NewName ++ ".webm",
      IsThumb = proplists:get_value(thumb, Opts, true),
      Thumbs = thumbs(#file{tmp_path = Webm, name = Name, dir = Dir}, Opts, IsThumb),
      {ok, #job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Result)|Thumbs]}}
  end.

thumbs(_, _, false) ->
  [];

thumbs(#file{tmp_path = Webm, name = Name, dir = Dir}, Opts, true) ->
  case video_thumb:run(#file{tmp_path = Webm, name = Name, dir = Dir}, Opts) of
    {ok,#job_stats{result_path = Thumbs}} ->
      Thumbs;
    _Else ->
      ?E({video_webm_failed, _Else}),
      []
  end.

info_to_params(#video_info{audio_codec = Audio, video_codec = Video, video_size = Size, pixel_format = Pix, video_bad_size=BadSize}=_Info) ->
  Format = pixel_format(Pix),
  VCodec =
    if
      BadSize -> video_codec(default, Format);
      true -> video_codec(Video, Format)
    end,
  Copy = VCodec =:= " -c:v copy ",
  VCodec ++ Format ++ video_size(Size,Copy,BadSize) ++ audio_codec(Audio).

audio_codec(undefined) ->
  " -an ";

audio_codec([]) ->
  " -an ";

audio_codec("vorbis") ->
  " -c:a copy ";

audio_codec(_) ->
  " -c:a libvorbis -ac 2 -ar 48000 -ab 192k ".

video_codec(undefined,_) ->
  " -vn ";

video_codec([],_) ->
  " -vn ";

video_codec("vp8","") ->
  " -c:v copy ";

video_codec(_,_) ->
  " -c:v libvpx -quality good -cpu-used 4 -qmin 10 -qmax 42 -threads 4 ".

pixel_format("yuv420p") ->
  "";

pixel_format(_) ->
  " -pix_fmt yuv420p ".

video_size(_,_,true) ->
  " -vf \"scale=trunc(in_w/2)*2:trunc(in_h/2)*2\" ";

video_size(_,_,_) ->
  "".