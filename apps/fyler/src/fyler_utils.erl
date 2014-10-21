-module(fyler_utils).
-include("fyler.hrl").
-include("../include/log.hrl").

%% API
-export([
  task_record_to_proplist/1, 
  task_record_to_task/1, 
  stats_to_pg_string/1,
  stats_to_pg_update_string/1,
  stats_to_proplist/1,
  current_task_to_proplist/1,
  pool_to_proplist/1,
  to_json/1
  ]).


stats_to_proplist(#job_stats{status=Status,
  download_time = DTime,
  upload_time = UTime,
  url = Url,
  priority = Priority,
  file_size = Size,
  file_path = Path,
  time_spent = Time,
  error_msg = Error,
  task_type = Type}) ->
  {[
  {status, Status}, 
  {download_time, DTime},
  {upload_time, UTime},
  {url, Url},
  {priority, Priority},
  {file_size, Size},
  {file_path, Path},
  {time_spent, Time},
  {task_type, Type},
  {error, error_to_s(Error)}]}.


current_task_to_proplist(#current_task{id=Id, status=Status, url=Url, type = Type, pool = Pool}) ->
  {[
    {id, Id},
    {status, Status},
    {url, list_to_binary(Url)},
    {type, Type},
    {pool,Pool}
  ]}.

pool_to_proplist(#pool{node = Node, category = Type, enabled = Enabled, active_tasks_num = Active, total_tasks = Total}) ->
  {[{node, atom_to_binary(Node,utf8)}, {category, Type}, {enabled, Enabled}, {active_tasks, Active}, {total, Total}]}. 


%% @doc
%% Convert tuple of values from PG to #job_stats{} record.
%% @end

-spec task_record_to_proplist(term()) -> list(#job_stats{}).

task_record_to_proplist(Record) ->
  #job_stats{ts=TS}=Stats = list_to_tuple([job_stats|tuple_to_list(Record)]),
  Stats2 = Stats#job_stats{ts = list_to_binary(pgtime_to_string(TS))},
  Stats2.

%% @doc
%% Convert tuple of values from PG to task tuple ({url, type, options, id})
%% @end

-spec task_record_to_task(term()) -> list().

task_record_to_task(Record) ->
  #job_stats{url = Url, id = Id, options = Options, task_type = Type} = list_to_tuple([job_stats|tuple_to_list(Record)]),
  {to_list(Url), to_list(Type), from_json(Options), Id}.

%% @doc
%% Convert stats record values to pg values string
%% @end

-spec stats_to_pg_string(#job_stats{}) -> string().

stats_to_pg_string(#job_stats{status=Status,
  download_time = DTime,
  upload_time = UTime,
  file_size = Size,
  file_path = Path,
  time_spent = Time,
  error_msg = Error,
  result_path = Results,
  task_type = Type}) ->

  ResultsList = string:join([binary_to_list(R) || R<-Results],","),

  "'"++atom_to_list(Status)++"',"++integer_to_list(to_int(DTime))++","++integer_to_list(to_int(UTime))++","++integer_to_list(to_int(Size))++",'"++Path++"',"++integer_to_list(to_int(Time))++",'"++ResultsList++"','"++atom_to_list(Type)++"','"++binary_to_list(error_to_s(Error))++"'".

stats_to_pg_update_string(#job_stats{status=Status,
  download_time = DTime,
  upload_time = UTime,
  file_size = Size,
  time_spent = Time,
  error_msg = Error,
  result_path = Results}) ->

  ResultsList = string:join([binary_to_list(R) || R<-Results],","),

  "status = '"++atom_to_list(Status)++"', download_time = "++integer_to_list(to_int(DTime))++", upload_time = "++integer_to_list(to_int(UTime))++", file_size = "++integer_to_list(to_int(Size))++", time_spent = "++integer_to_list(to_int(Time))++", result_path = '"++ResultsList++"', error_msg = '"++binary_to_list(error_to_s(Error))++"'".


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

pgtime_to_string(_F) -> "".


to_json([]) ->
  <<"">>;

to_json(List) when is_list(List) ->
  jiffy:encode({List});

to_json(_) ->
  <<"">>.

from_json("") ->
  [];

from_json(Any) ->
  try jiffy:decode(Any) of
    {Data} -> [{binary_to_atom(Opt,latin1),proplists:get_value(Opt, Data)} || Opt <- proplists:get_keys(Data)]
  catch
    _:_Error ->
      ?E({json_failed, Any, _Error}),
      []
  end.

pad(N) when N < 10 -> "0"++integer_to_list(N);

pad(N) -> integer_to_list(N).

to_int(undefined) -> 0;

to_int(N) -> N.

to_list(null) -> "";

to_list(Str) when is_binary(Str) ->
  binary_to_list(Str);

to_list(Str) ->
  Str.

error_to_s(Er) when is_list(Er) ->
  list_to_binary(Er);

error_to_s(Er) when is_binary(Er) ->
  Er;

error_to_s({error,Reason}) ->
  error_to_s(Reason);

error_to_s(null) ->
  <<"">>;

error_to_s(_) ->
  <<"Error">>.



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
    ts = <<"2013-10-24 12:00:00">>, url="http://url", priority="low", options = ""}, task_record_to_proplist({1,<<"success">>,1,1,1,<<"path/to/file">>,1,<<"path/to/result">>,<<"do_nothing">>,<<"command not found">>,{{2013,10,24},{12,0,0.3}}, "http://url", "", "low"}))
  ].


rec_to_string_test_() ->
  [
    ?_assertEqual("'success',1,1,1,'path/to/file',1,'path1,path2','do_nothing','command not found'", stats_to_pg_string(#job_stats{id=1,
    status= success,
    download_time=1,
    upload_time=1,
    file_size=1,
    file_path= "path/to/file",
    time_spent=1,
    result_path= [<<"path1">>,<<"path2">>],
    task_type= do_nothing,
    error_msg= "command not found"}))
  ].

rec_to_task_test_() ->
  [
    ?_assertEqual({"http://url", "do_nothing", [{callback, <<"http://callback">>}], 1}, 
      task_record_to_task({1,<<"success">>,1,1,1,<<"path/to/file">>,1,<<"path/to/result">>,<<"do_nothing">>,<<"command not found">>,{{2013,10,24},{12,0,0.3}}, <<"http://url">>, <<"{\"callback\":\"http://callback\"}">>, <<"low">>})
      )
  ].

rec_to_update_string_test_() ->
  [
    ?_assertEqual("status = 'success', download_time = 1, upload_time = 1, file_size = 1, time_spent = 1, result_path = 'path1,path2', error_msg = 'command not found'", stats_to_pg_update_string(#job_stats{id=1,
      status= success,
      download_time=1,
      upload_time=1,
      file_size=1,
      file_path= "path/to/file",
      time_spent=1,
      result_path= [<<"path1">>,<<"path2">>],
      task_type= do_nothing,
      error_msg= "command not found"}))
  ].

to_json_test() ->
  ?assertEqual(<<"">>, to_json([])),
  ?assertEqual(<<"{\"id\":1}">>, to_json([{id,1}])),
  ?assertEqual(<<"{\"id\":1}">>, to_json([{<<"id">>,1}])).

-endif.