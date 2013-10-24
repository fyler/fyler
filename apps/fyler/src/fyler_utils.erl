-module(fyler_utils).
-include("fyler.hrl").

%% API
-export([task_record_to_proplist/1]).



%% @doc
%% Convert tuple of values from PG to #job_stats{} record.
%% @end

-spec task_record_to_proplist(term()) -> list(#job_stats{}).

task_record_to_proplist(Record) ->
  #job_stats{ts=TS}=Stats = list_to_tuple([job_stats|tuple_to_list(Record)]),
  Stats2 = Stats#job_stats{ts = list_to_binary(pgtime_to_string(TS))},
  Stats2.

%% @doc Convert epgsql time fromat to number.
%% @end

-spec pgtime_to_string({{Year::non_neg_integer(),Month::non_neg_integer(),Day::non_neg_integer()},{Hour::non_neg_integer(),Minute::non_neg_integer(),Seconds::non_neg_integer()}}) -> number() | {error, badformat}.
pgtime_to_string({{Year,Month,Day},{Hour,Minute,Seconds}}) ->
  integer_to_list(Year)++"-"++
    integer_to_list(Month)++"-"++
    integer_to_list(Day)++" "++
    pad(Hour)++":"++
    pad(Minute)++":"++
    pad(trunc(Seconds));

pgtime_to_string(_F) -> {error,badformat,_F}.


pad(N) when N < 10 -> "0"++integer_to_list(N);

pad(N) -> integer_to_list(N).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


rec_to_job_test_() ->
  [
    ?_assertEqual(#job_stats{id=1,
    status= <<"success">>,
    download_time=1,
    upload_time=1,
    file_size=1,
    file_path= <<"path/to/file">>,
    time_spent=1,
    result_path= <<"path/to/result">>,
    task_type= <<"do_nothing">>,
    error_msg= <<"command not found">>,
    ts = <<"2013-10-24 12:00:00">>}, task_record_to_proplist({1,<<"success">>,1,1,1,<<"path/to/file">>,1,<<"path/to/result">>,<<"do_nothing">>,<<"command not found">>,{{2013,10,24},{12,0,0.3}}}))
  ].

-endif.