%%% @doc Convert Teachbase recording files (flv) to hls using media
%%% @end

-module(recording_to_hls2).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2,category/0]).

category() ->
  video.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir} = File, _Opts) ->
  Start = ulitos:timestamp(),
  Playlist = Name ++ ".m3u8",
  Options = #{filename => Path, hls_writer => #{dir => Dir, playlist => Playlist}},
  #video_info{audio_codec = Audio, video_codec = Video} = video_probe:info(Path),
  case convert(Audio, Video, Options, File) of
    {ok, _} ->
      {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Playlist)]}};
    ok ->
      {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Playlist)]}};
    {error, Reason} ->
      {error, Reason}
  end.

convert("libspeex", "h264", Options, File) ->
  Audio = #{input => #{codec => speex, channels => 1, sample_rate => 16000}, output => #{codec => aac, channels => 2}},
  AllOptions = Options#{audio => Audio},
  media_convert:flv_to_hls(AllOptions),
  wait_result(AllOptions, File);

convert("aac", "h264", Options, File) ->
  media_convert:flv_to_hls(Options),
  wait_result(Options, File);

convert("mp3", "h264", Options = #{hls_writer := HlsWriter}, File) ->
  AllOptions = Options#{hls_writer => HlsWriter#{audio => mp3}},
  media_convert:flv_to_hls(AllOptions),
  wait_result(AllOptions, File);

convert("libspeex", "", Options = #{hls_writer := HlsWriter}, File) ->
  Audio = #{input => #{codec => speex, channels => 1, sample_rate => 16000}, output => #{codec => aac, channels => 2}},
  AllOptions = Options#{audio => Audio, hls_writer => HlsWriter#{video => undefined}},
  media_convert:flv_to_hls(AllOptions),
  wait_result(AllOptions, File);

convert("aac", "", Options = #{hls_writer := HlsWriter}, File) ->
  AllOptions = Options#{hls_writer => HlsWriter#{video => undefined}},
  media_convert:flv_to_hls(AllOptions),
  wait_result(AllOptions, File);

convert("mp3", "", Options = #{hls_writer := HlsWriter}, File) ->
  AllOptions = Options#{hls_writer => HlsWriter#{audio => mp3, video => undefined}},
  media_convert:flv_to_hls(AllOptions),
  wait_result(AllOptions, File);

convert(_Audio, "flashsv2", _Options, File) ->
  recording_to_hls:run(File, [{stream_type, <<"share">>}]);

convert(_Audio, _Video, _Options, File) ->
  video_to_hls:run(File).


wait_result(Options, File) ->
  receive
    {task_complete, Options} ->
      ok;
    {task_failed, Reason, Options} ->
      ?D({"media_convert:flv_to_hls failed", Reason}),
      video_to_hls:run(File)
  after 3600000 ->
    {error, timeout}
  end.


