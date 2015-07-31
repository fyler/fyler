%%% @doc Module for getting video info (usign ffprobe).
%%% @end

-module(video_probe).
-include("../fyler.hrl").
-include("../../include/log.hrl").
-export([info/1]).

-define(CMD(Path), lists:flatten(io_lib:format("ffprobe -v quiet -print_format json -show_format -show_streams ~s", [Path]))).

info(Path) ->
  Command = ?CMD(Path),

  true = filelib:is_file(Path),
  case exec_command:run_link(Command, [stdout, monitor]) of
    {error, Error} ->
      ?E(Error),
      #video_info{audio_codec = default, video_codec = default};
    _ ->
      Probe = loop(<<>>),
      try jiffy:decode(Probe) of
        {Info} ->
          Streams = proplists:get_value(<<"streams">>, Info, []),
          if
            length(Streams) > 0 ->
              VideoInfo = parse_info(Streams, #video_info{}),
              ?D({video_info, VideoInfo}),
              VideoInfo;
            true ->
              ?E({file_is_not_video, Path}),
              false
          end
      catch
        throw:{error, {Ind, invalid_string}} -> ?E({error, {string:substr(Probe, Ind, 1), invalid_string}});
        _:Error_ -> ?E(Error_),
          #video_info{audio_codec = default, video_codec = default}
      end
  end.


loop(Probe) ->
  receive
    {stdout, _, Part} ->
      loop(<<Probe/binary, Part/binary>>);
    {'DOWN', _, _, _, normal} ->
      Probe;
    _ ->
      <<>>
  end.

parse_info([],Info) -> Info;

parse_info([{Stream}|T],Info) ->
  Type = proplists:get_value(<<"codec_type">>, Stream),
  parse_info(T, update_info(Type, Stream, Info)).

update_info(<<"video">>,Stream,Info) ->
  Codec = binary_to_list(proplists:get_value(<<"codec_name">>, Stream, <<>>)),
  Size = proplists:get_value(<<"width">>, Stream, 0),
  Height = proplists:get_value(<<"height">>,Stream,0),
  BadSize = bad_size(Size,Height),
  Pix = binary_to_list(proplists:get_value(<<"pix_fmt">>,Stream,<<>>)),
  Info#video_info{video_codec=Codec,pixel_format=Pix,video_size=Size, video_bad_size=BadSize};

update_info(<<"audio">>,Stream,Info) ->
  Codec = binary_to_list(proplists:get_value(<<"codec_name">>,Stream,<<>>)),
  Info#video_info{audio_codec=Codec};

update_info(_,_,Info) ->
  Info.

bad_size(W,H) when (W rem 2) =:= 1; (H rem 2) =:= 1 ->
  true;

bad_size(_,_) -> false.

