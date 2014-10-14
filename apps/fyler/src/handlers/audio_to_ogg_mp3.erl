%%% @doc Convert any audio to ogg and mp3 using audio_to_ogg and audio_to_mp3 handlers.
%%% @end
-module(audio_to_ogg_mp3).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1,run/2,category/0]).

category() ->
  video.

run(File) -> run(File,[]).

run(File, Opts) ->
  Start = ulitos:timestamp(),
  case  audio_to_mp3:run(File, Opts) of
    {ok, #job_stats{result_path = Mp3Result}} ->
      case audio_to_ogg:run(File, Opts) of
        {ok, #job_stats{result_path = OggResult}} ->
          {ok, #job_stats{time_spent = ulitos:timestamp() - Start, result_path = Mp3Result ++ OggResult}};
        {error, Reason} ->
          {error, Reason}
      end;
    {error, Reason} ->
      {error, Reason}
  end.
