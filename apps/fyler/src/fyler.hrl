%% Copyright
-author("palkan").

-define(Config(X,Y),ulitos:get_var(fyler,X,Y)).

-record(file,{
  url ::string(),
  name ::string(),
  dir ::string(),
  is_aws ::string(),
  extension ::string(),
  size ::non_neg_integer(),
  tmp_path ::string()
}).

-type file() ::#file{}.

-record(task,{
  type ::atom(),
  file ::file(),
  callback = undefined ::string(),
  worker ::reference(),
  options = []
}).

-type task() ::#task{}.

-record(job_stats,{
  download_time ::non_neg_integer(),
  time_spent ::non_neg_integer(),
  result_path ::string()
}).

-type stats() ::#job_stats{}.

-type event_type() ::complete|failed|cpu_high|cpu_available.

-record(fevent,{
  type ::event_type(),
  task ::task(),
  stats ::#job_stats{},
  error = undefined ::any()
}).
