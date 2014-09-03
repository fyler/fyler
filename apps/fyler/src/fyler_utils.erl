-module(fyler_utils).
-include("fyler.hrl").

%% API
-export([stats_to_proplist/1]).



%% @doc
%% Convert tuple of values from PG to #job_stats{} record.
%% @end

-spec stats_to_proplist(term()) -> list(#job_stats{}).

stats_to_proplist(Stats) ->
  Keys = [
    id, 
    download_time, 
    upload_time, 
    file_url, 
    file_size, 
    file_path, 
    time_spent, 
    result_path, 
    task_type],
  Res = lists:zip(Keys, [
    Stats#job_stats.id, 
    Stats#job_stats.download_time, 
    Stats#job_stats.upload_time, 
    Stats#job_stats.file_url, 
    Stats#job_stats.file_size, 
    Stats#job_stats.file_path, 
    Stats#job_stats.time_spent, 
    Stats#job_stats.result_path,
    Stats#job_stats.task_type
  ])++[{created_at, time_to_string(Stats#job_stats.ts)},{error, error_to_string(Stats#job_stats.error_msg)}],
  Res



%% @doc Convert epgsql time fromat to number.
%% @end

-spec time_to_string({{Year::non_neg_integer(),Month::non_neg_integer(),Day::non_neg_integer()},{Hour::non_neg_integer(),Minute::non_neg_integer(),Seconds::non_neg_integer()}}) -> number() | {error, badformat}.
time_to_string({{Year,Month,Day},{Hour,Minute,Seconds}}) ->
  integer_to_list(Year)++"-"++
    integer_to_list(Month)++"-"++
    integer_to_list(Day)++" "++
    pad(Hour)++":"++
    pad(Minute)++":"++
    pad(trunc(Seconds));

time_to_string(_F) -> {error,badformat,_F}.


pad(N) when N < 10 -> "0"++integer_to_list(N);

pad(N) -> integer_to_list(N).

error_to_string(Error) when is_list(Error) ->
  list_to_binary(Error);

error_to_string(Error) when is_atom(Error) ->
  Error;

error_to_string(Error) when is_binary(Error) ->
  Error;

error_to_string({_,Error}) when is_list(Error) ->
  error_to_string(Error);

error_to_string(_) ->
  <<"unknown">>.




-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

stats_to_list_test_() ->
  [
    ?_assertEqual([
      {id, 1}, 
      {download_time, 1}, 
      {upload_time, 1},
      {file_url, "file/url"},
      {file_size, 1},
      {file_path, "path/to/file"},
      {time_spent, 1},
      {result_path, "path/to/result"},
      {task_type, do_nothing},
      {created_at, "2013-10-24 12:00:00"},
      {error, command_not_found}
    ], stats_to_proplist(#job_stats{id=1,
    status=success,
    download_time=1,
    upload_time=1,
    file_url = "file/url",
    file_size=1,
    file_path= "path/to/file",
    time_spent=1,
    result_path= "path/to/result",
    task_type= do_nothing,
    error_msg=command_not_found,
    ts = {{2013,10,24},{12,0,0.3}}}))
  ].
-endif.