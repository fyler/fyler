%% Copyright
-author("palkan").

-define(Config(X,Y),ulitos:get_var(fyler,X,Y)).

-define(T_LIVE_STATS,fyler_live_statistics).
-define(T_STATS,fyler_statistics).

-record(file,{
  url ::string(),
  name ::string(),
  dir ::string(),
  is_aws ::string(),
  bucket ::string(),
  extension ::string(),
  size ::non_neg_integer(),
  tmp_path ::string(),
  target_dir = [] ::list()
}).

-type file() ::#file{}.

-record(job_stats,{
  id = 0 ::non_neg_integer(),
  status ::success|failed,
  download_time = 0 ::non_neg_integer(),
  upload_time = 0 ::non_neg_integer(),
  file_url = "" ::string(),
  file_size = 0 ::non_neg_integer(),
  file_path = "" ::string(),
  time_spent = 0 ::non_neg_integer(),
  result_path = [] ::string(),
  task_type = do_nothing ::atom(),
  error_msg = "" ::string(),
  ts = 0 ::non_neg_integer()
}).

-type stats() ::#job_stats{}.

-record(task,{
  id ::non_neg_integer(),
  type ::atom(),
  pool_type ::atom(),
  status = queued ::progress|queued, 
  file ::file(),
  priority = normal ::low|normal|high,
  acl = public ::atom(),
  callback = undefined ::binary(),
  worker ::reference(),
  options = [],
  pool ::atom()
}).

-type task() ::#task{}.

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
  type :: atom(),
  enabled :: boolean(),
  total_tasks = 0 ::non_neg_integer()
}).
