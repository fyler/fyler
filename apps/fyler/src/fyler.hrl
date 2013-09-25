%% Copyright
-author("palkan").

-define(Config(X,Y),ulitos:get_var(fyler,X,Y)).

-define(T_STATS,fyler_statistics).

-record(file,{
  url ::string(),
  name ::string(),
  dir ::string(),
  is_aws ::string(),
  bucket ::string(),
  extension ::string(),
  size ::non_neg_integer(),
  tmp_path ::string()
}).

-type file() ::#file{}.

-record(task,{
  type ::atom(),
  file ::file(),
  callback = undefined ::binary(),
  worker ::reference(),
  options = []
}).

-type task() ::#task{}.

-record(job_stats,{
  status ::success|failed,
  download_time ::non_neg_integer(),
  upload_time ::non_neg_integer(),
  file_size ::non_neg_integer(),
  file_path ::string(),
  time_spent ::non_neg_integer(),
  result_path ::string(),
  task_type ::atom(),
  error_msg ::any(),
  ts ::non_neg_integer()
}).

-type stats() ::#job_stats{}.

-type event_type() ::complete|failed|cpu_high|cpu_available.

-record(fevent,{
  type ::event_type(),
  node ::atom(),
  task ::task(),
  stats ::stats(),
  error = undefined ::any()
}).

-record(pool, {
  node :: atom(),
  enabled :: boolean(),
  active_tasks_num =0 :: non_neg_integer(),
  total_tasks = 0 ::non_neg_integer()
}).
