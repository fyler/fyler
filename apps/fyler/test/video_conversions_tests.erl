-module(video_conversions_tests).
-include("../src/fyler.hrl").
-include("../include/log.hrl").
-include_lib("kernel/include/file.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(PATH(File), filename:join([code:priv_dir(fyler),"..","test","support", File])).

-define(setup(F), {setup, fun setup_/0, fun cleanup_/1, F}).

-define(TIMEOUT, 120).

file_size(Path) ->
  case file:read_file_info(Path) of
    {ok,#file_info{size = Size}} -> Size;
    _ -> 0
  end.

delete_files([]) ->
  ok;

delete_files([File|Files]) ->
  file:delete(?PATH(File)),
  delete_files(Files).

setup_() ->
  lager:start(),
  media:start(),
  ulitos_app:ensure_started(erlexec),
  file:make_dir(?PATH("tmp")).

cleanup_(_) ->
  ulitos_file:recursively_del_dir(?PATH("tmp")),
  file:delete(?PATH("v1.mp4")),
  file:delete(?PATH("v2_converted.mp4")),
  file:delete(?PATH("v3.mp4")),
  file:delete(?PATH("v1.webm")),
  file:delete(?PATH("v2.webm")),
  file:delete(?PATH("v3.webm")),
  file:delete(?PATH("stream_1.mp4")),
  file:delete(?PATH("stream_1.webm")),
  file:delete(?PATH("8.mp3")),
  file:delete(?PATH("9_converted.mp3")),
  file:delete(?PATH("8.ogg")),
  file:delete(?PATH("9.ogg")),
  case filelib:wildcard("*.ts",?PATH("")) of
    Files when is_list(Files) -> delete_files(Files);
    _ -> false
  end,
  case filelib:wildcard("*.m3u8",?PATH("")) of
    Files3 when is_list(Files3) -> delete_files(Files3);
    _ -> false
  end,
  case filelib:wildcard("*.png",?PATH("")) of
    Files4 when is_list(Files4) -> delete_files(Files4);
    _ -> false
  end,
  application:stop(erlexec),
  application:stop(lager).

video_mp4_test_() ->
  ?setup(
    [
      {timeout, ?TIMEOUT, [mov_to_mp4_t_()]},
      {timeout, ?TIMEOUT, [avi_to_mp4_t_()]},
      {timeout, ?TIMEOUT, [mp4_to_mp4_t_()]},
      {timeout, ?TIMEOUT, [flv_to_mp4_t_()]}
    ]
  ).

video_webm_test_() ->
  ?setup(
    [
      {timeout, ?TIMEOUT, [mov_to_webm_t_()]},
      {timeout, ?TIMEOUT, [avi_to_webm_t_()]},
      {timeout, ?TIMEOUT, [mp4_to_webm_t_()]},
      {timeout, ?TIMEOUT, [flv_to_webm_t_()]}
    ]
  ).

video_mp4_webm_test_() ->
  ?setup(
    [
      {timeout, ?TIMEOUT, [flv_to_mp4_webm_t_()]}
    ]
  ).

video_hls_test_() ->
  ?setup(
    [
      {timeout, ?TIMEOUT, [mov_to_hls_t_()]},
      {timeout, ?TIMEOUT, [avi_to_hls_t_()]},
      {timeout, ?TIMEOUT, [mp4_to_hls_t_()]}
    ]
  ).

video_recording_test_() ->
  ?setup(
    [
      {timeout, ?TIMEOUT, [av_rec_to_hls_t_()]},
      {timeout, ?TIMEOUT, [screen_rec_to_hls_t_()]},
      {timeout, ?TIMEOUT, [av_rec_to_hls2_t_()]}
    ]
  ).

audio_to_mp3_test_() ->
  ?setup(
    [
      {timeout, ?TIMEOUT, [wav_to_mp3_t_()]},
      {timeout, ?TIMEOUT, [mp3_to_mp3_t_()]}
    ]
  ).

audio_to_ogg_test_() ->
  ?setup(
    [
      {timeout, ?TIMEOUT, [wav_to_ogg_t_()]},
      {timeout, ?TIMEOUT, [mp3_to_ogg_t_()]}
    ]
  ).

video_probe_test_() ->
  ?setup(
    [
      {timeout, ?TIMEOUT, [video_probe_flv_speex_t_()]},
      {timeout, ?TIMEOUT, [video_probe_screen_share_t_()]},
      {timeout, ?TIMEOUT, [video_probe_mov_t_()]},
      {timeout, ?TIMEOUT, [video_probe_aac_h264_t_()]},
      {timeout, ?TIMEOUT, [video_probe_avi_t_()]}
    ]
  ).

mov_to_mp4_t_() ->
  fun() ->
    Res = video_to_mp4:run(#file{tmp_path = ?PATH("v1.MOV"), name = "v1", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.

avi_to_mp4_t_() ->
  fun() ->
    Res = video_to_mp4:run(#file{tmp_path = ?PATH("v3.avi"), name = "v3", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.

mp4_to_mp4_t_() ->
  fun() ->
    Res = video_to_mp4:run(#file{tmp_path = ?PATH("v2.mp4"), name = "v2", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.

flv_to_mp4_t_() ->
  fun() ->
    Res = video_to_mp4:run(#file{tmp_path = ?PATH("stream_1.flv"), name = "stream_1", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.

mov_to_webm_t_() ->
  fun() ->
    Res = video_to_webm:run(#file{tmp_path = ?PATH("v1.MOV"), name = "v1", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.

avi_to_webm_t_() ->
  fun() ->
    Res = video_to_webm:run(#file{tmp_path = ?PATH("v3.avi"), name = "v3", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.

mp4_to_webm_t_() ->
  fun() ->
    Res = video_to_webm:run(#file{tmp_path = ?PATH("v2.mp4"), name = "v2", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.

flv_to_webm_t_() ->
  fun() ->
    Res = video_to_webm:run(#file{tmp_path = ?PATH("stream_1.flv"), name = "stream_1", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.

flv_to_mp4_webm_t_() ->
  fun() ->
    Res = video_to_mp4_webm:run(#file{tmp_path = ?PATH("stream_1.flv"), name = "stream_1", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(4, length(Stat#job_stats.result_path))
  end.

mov_to_hls_t_() ->
  fun() ->
    Res = video_to_hls:run(#file{tmp_path = ?PATH("v1.MOV"), name = "v1", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.

mp4_to_hls_t_() ->
  fun() ->
    Res = video_to_hls:run(#file{tmp_path = ?PATH("v2.mp4"), name = "v2", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.

avi_to_hls_t_() ->
  fun() ->
    Res = video_to_hls:run(#file{tmp_path = ?PATH("v3.avi"), name = "v3", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.

av_rec_to_hls_t_() ->
  fun() ->
    Res = recording_to_hls:run(#file{tmp_path = ?PATH("stream_1.flv"), name = "stream_1", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(1, length(Stat#job_stats.result_path))
  end.

av_rec_to_hls2_t_() ->
  fun() ->
    Res = recording_to_hls2:run(#file{tmp_path = ?PATH("stream_1.flv"), name = "stream_1", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(1, length(Stat#job_stats.result_path))
  end.

screen_rec_to_hls_t_() ->
  fun() ->
    Res = recording_to_hls:run(#file{tmp_path = ?PATH("stream_2.flv"), name = "stream_1", dir = ?PATH("")},[{stream_type,<<"share">>}]),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(1, length(Stat#job_stats.result_path))
  end.

wav_to_mp3_t_() ->
  fun() ->
    Res = audio_to_mp3:run(#file{tmp_path = ?PATH("8.wav"), name = "8", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(1, length(Stat#job_stats.result_path))
  end.

mp3_to_mp3_t_() ->
  fun() ->
    Res = audio_to_mp3:run(#file{tmp_path = ?PATH("9.mp3"), name = "9", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(1, length(Stat#job_stats.result_path))
  end.

wav_to_ogg_t_() ->
  fun() ->
    Res = audio_to_ogg:run(#file{tmp_path = ?PATH("8.wav"), name = "8", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(1, length(Stat#job_stats.result_path))
  end.

mp3_to_ogg_t_() ->
  fun() ->
    Res = audio_to_ogg:run(#file{tmp_path = ?PATH("9.mp3"), name = "9", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(1, length(Stat#job_stats.result_path))
  end.

video_probe_flv_speex_t_() ->
  fun() ->
    ?assertMatch(#video_info{audio_codec="speex", video_codec="h264"}, video_probe:info(?PATH("stream_1.flv")))
  end.

video_probe_screen_share_t_() ->
  fun() ->
    ?assertMatch(#video_info{video_codec="flashsv2", pixel_format="bgr24"}, video_probe:info(?PATH("stream_2.flv")))
  end.

video_probe_mov_t_() ->
  fun() ->
    ?assertMatch(#video_info{video_codec="mjpeg"}, video_probe:info(?PATH("v1.MOV")))
  end.

video_probe_aac_h264_t_() ->
  fun() ->
    ?assertMatch(#video_info{video_codec="h264", audio_codec="aac"}, video_probe:info(?PATH("v2.mp4")))
  end.

video_probe_avi_t_() ->
  fun() ->
    ?assertMatch(#video_info{video_codec="mpeg4"}, video_probe:info(?PATH("v3.avi")))
  end.