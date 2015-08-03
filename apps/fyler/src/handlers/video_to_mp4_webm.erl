%%% @doc Convert any video to webm and mp4 using video_to_webm and video_to_mp4 handlers.
%%% @end
-module(video_to_mp4_webm).
-author("ilia").
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1,run/2,category/0]).

category() ->
  video.

run(File) -> run(File,[]).

run(#file{} = File, Opts) ->
  Start = ulitos:timestamp(),
  case  video_to_mp4:run(File, [{thumb, false} | Opts]) of
    {ok, #job_stats{result_path = [Mp4]}} ->
      case video_to_webm:run(File, Opts) of
        {ok, #job_stats{result_path = WebmResult}} ->
          {ok, #job_stats{time_spent = ulitos:timestamp() - Start, result_path = [Mp4 | WebmResult]}};
        {error, Reason} ->
          {error, Reason}
      end;
    {error, Reason} ->
      {error, Reason}
  end.