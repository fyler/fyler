%% Copyright
-author("palkan").

-define(Config(X,Y),ulitos_app:get_var(fyler,X,Y)).

-define(T_STATS,fyler_live_statistics).

-define (T_POOLS, fyler_pools).

-define(PG_POOL,fyler_pg_pool).

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

-record(task,{
  id ::non_neg_integer(),
  type ::atom(),
  category ::atom(),
  acl = public ::atom(),
  priority = normal ::low|normal|high,
  file ::file(),
  callback = undefined ::binary(),
  worker ::reference(),
  options = []
}).

-type task() ::#task{}.

-record(current_task,{
  id ::non_neg_integer(),
  status ::queued|progress,
  task ::task(),
  type ::atom(),
  category ::atom(),
  pool ::atom(),
  url ::string()
}).


-record(job_stats,{
  id = 0 ::non_neg_integer(),
  status ::success|failed,
  download_time = 0 ::non_neg_integer(),
  upload_time = 0 ::non_neg_integer(),
  file_size = 0 ::non_neg_integer(),
  file_path = "" ::string(),
  time_spent = 0 ::non_neg_integer(),
  result_path = [] ::string(),
  task_type = do_nothing ::atom(),
  error_msg = "" ::string(),
  ts = 0 ::non_neg_integer()
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
  category :: atom(),
  enabled :: boolean(),
  active_tasks_num =0 :: non_neg_integer(),
  total_tasks = 0 ::non_neg_integer()
}).


-record(video_info,{
  audio_codec = undefined ::string(),
  video_codec = undefined ::string(),
  video_size = undefined ::string(),
  video_bad_size = false ::atom(),
  pixel_format = undefined ::string()
}).