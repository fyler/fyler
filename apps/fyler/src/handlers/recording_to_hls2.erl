%%% @doc Convert Teachbase recording files (flv) to hls using media
%%% @end

-module(recording_to_hls2).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2,category/0]).

category() ->
  video.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir}, _Opts) ->
  Start = ulitos:timestamp(),
  Playlist = Name ++ ".m3u8",
  Options = #{filename => Path, hls_writer => #{dir => Dir, playlist => Playlist}},
  #video_info{audio_codec = Audio, video_codec = Video} = video_probe:info(Path),
  case convert(Audio, Video, Options) of
    ok ->
      {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Playlist)]}};
    {error, Reason} ->
      {error, Reason}
  end.

convert("libspeex", "h264", Options) ->
  Audio = #{input => #{codec => speex, channels => 1, sample_rate => 16000}, output => #{codec => aac, channels => 2}},
  AllOptions = Options#{audio => Audio},
  media_convert:flv_to_hls(AllOptions),
  wait_result(AllOptions);

convert("aac", "h264", Options) ->
  media_convert:flv_to_hls(Options),
  wait_result(Options);

convert("mp3", "h264", Options = #{hls_writer := HlsWriter}) ->
  AllOptions = Options#{hls_writer => HlsWriter#{audio => mp3}},
  media_convert:flv_to_hls(AllOptions),
  wait_result(AllOptions);

convert(_Audio, _Video, _Options) ->
  {error, invalid_codecs}.


wait_result(Options) ->
  receive
    {task_complete, Options} ->
      ok;
    {task_failed, Reason, Options} ->
      {error, Reason}
  after 3600000 ->
    {error, timeout}
  end.


