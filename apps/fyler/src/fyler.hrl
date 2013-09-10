%% Copyright
-author("palkan").

-define(Config(X,Y),ulitos:get_var(fyler,X,Y)).

-record(file,{
  url ::string(),
  name ::string(),
  extension ::string(),
  size ::non_neg_integer(),
  tmp_path ::string()
}).

-type file() ::#file{}.

-record(task,{
  type ::atom(),
  file ::file(),
  worker ::reference(),
  options = []
}).

-type task() ::#task{}.

-record(job_stats,{
  download_time ::non_neg_integer(),
  time_spent ::non_neg_integer()
}).

-type event_type() ::complete|failed.

-record(fevent,{
  type ::event_type(),
  task ::task(),
  stats ::#job_stats{},
  error = undefined ::any()
}).
