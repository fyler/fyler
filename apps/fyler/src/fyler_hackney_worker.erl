-module(fyler_hackney_worker).
-include("../include/log.hrl").
-include("fyler.hrl").

-export([start_link/2, init_server/2]).

% default connect timeout to 10 seconds
-define(TIMEOUT, 10000).

% sleep for 20 seconds before die
-define(SLEEP, 20000).

start_link(Task, Stats) ->
  proc_lib:start_link(?MODULE, init_server, [Task, Stats]).

init_server(#task{callback = undefined}, _Stats) ->
  exit(normal);

init_server(#task{callback = Callback} = Task, Stats) ->
  proc_lib:init_ack({ok, self()}),
  Options = [
    {<<"Content-Type">>, <<"application/x-www-form-urlencoded">>},
    {pool, default},
    {timeout, ?TIMEOUT}
  ],
  Request = prepare_request(Task, Stats),
  case hackney:post(Callback, Options, Request, []) of
    {ok, Status, _, _} when Status >= 200, Status < 300 ->
      ?I({successfull_callback, Callback, Status}),
      exit(normal);
    {ok, Status, _, _} ->
      ?E({callback_app_error, Callback, Status}),
      exit(normal);
    {error, Reason} ->
      ?E({callback_failed, Callback, Reason}),
      timer:sleep(?SLEEP),
      exit(http_error)
  end.

prepare_request(
  #task{file = #file{is_aws = true, bucket = Bucket, target_dir = Dir}},
  #job_stats{status = success, result_path = Path}
) ->
  Data = jiffy:encode({[{path, Path}, {dir, list_to_binary(Dir)}]}),
  iolist_to_binary("status=ok&aws=true&bucket=" ++ Bucket ++ "&data=" ++ Data);

prepare_request(_Task, _Stats) ->
  <<"status=failed">>.
