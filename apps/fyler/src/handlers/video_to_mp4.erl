%%% @doc Convert any video to mp4 with h264 and aac.
%%% @end 

-module(video_to_mp4).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2, category/0, info_to_params/1]).

-define(COMMAND(In,Out,Params), 
  "ffmpeg -i "++In++" "++Params++" "++Out
  ).

category() ->
 video.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, extension=Ext, dir = Dir},Opts) ->
  Start = ulitos:timestamp(),

  NewName = if Ext =:= "mp4"
    -> Name++"_converted";
    true -> Name
  end,

  MP4 =filename:join(Dir,NewName++".mp4"),

  Info = video_probe:info(Path),

  Command = ?COMMAND(Path,MP4, info_to_params(Info)),

  ?D({"command",Command}),
  Data = os:cmd(Command),
  case filelib:wildcard("*.mp4",Dir) of
    [] -> {error,Data};
    _List -> 
            Result = NewName++".mp4",
            IsThumb = proplists:get_value(thumb, Opts, true),
            if IsThumb ->
              case video_thumb:run(#file{tmp_path = MP4, name = Name, dir = Dir},Opts) of
                {ok,#job_stats{result_path = Thumbs}} ->
                  {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Result)|Thumbs]}};
                _Else ->
                  ?E({video_mp4_failed, _Else}),
                  {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Result)]}}
              end;
            true ->
              {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Result)]}}
            end
  end.


info_to_params(#video_info{audio_codec = Audio, video_codec = Video, video_size = Size, pixel_format = Pix, video_bad_size=BadSize}=_Info) ->
  Format = pixel_format(Pix),
  VCodec = video_codec(Video,Format),
  Copy = VCodec =:= " -c:v copy ",
  VCodec ++ Format ++ video_size(Size,Copy,BadSize) ++ audio_codec(Audio).

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

video_codec(undefined,_) ->
  " -vn ";

video_codec([],_) ->
  " -vn ";

video_codec("h264","") ->
  " -c:v copy ";

video_codec(_,_) ->
  " -vcodec libx264 -profile:v baseline -preset slower -crf 18 ".

pixel_format("yuv420p") ->
  "";

pixel_format(_) ->
  " -pix_fmt yuv420p ".

video_size(Size,_,true) when Size < 800 ->
  " -vf \"scale=trunc(in_w/2)*2:trunc(in_h/2)*2\" ";

video_size(Size,_,_) when Size > 1000->
  " -video_size hd1080 ";

video_size(_,_,_) ->
  "".