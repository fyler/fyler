%%% @doc Module handling archive with 'index.html' unpacking 
%%% @end

-module(unpack_html).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1,run/2, category/0]).

-define(COMMAND(In,Out), lists:flatten(io_lib:format("7z -o~s x ~s",[Out,In]))).

category() ->
  document.

run(File) -> run(File,[]).

run(#file{tmp_path = Path, dir = Dir}, _Opts) ->
  Start = ulitos:timestamp(),

  OutDir = filename:join(Dir,"out"),

  Command = ?COMMAND(Path,OutDir),

  ?D({command, Command}),

  Data = exec_command:run(Command),
  RootDir = detect_root(OutDir),
  ?D({archive_root, RootDir}),
  FullRootDir = filename:join(Dir,RootDir),
  FileName = filename:join(RootDir, detect_filename(filelib:wildcard("*.html", FullRootDir))),
  ?D({archive_index, FileName}),
  HTML = filename:join(Dir,FileName),
  case  filelib:is_file(HTML) of
    true -> 
          {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(FileName)]}};
    _ -> {error, {'unpack_archive_failed',HTML,Data}}
  end.

detect_filename([]) ->
  "empty.html";

detect_filename(List) ->
  case lists:member("index.html", List) of
    true -> "index.html";
    false -> hd(List)
  end. 

%% checks whether we have one dir with contents or index on the top level 
detect_root(Dir) ->
  {ok, SubDirs} = file:list_dir(Dir),
  case lists:filter(fun(D) -> filelib:is_dir(filename:join(Dir, D)) end, SubDirs) of
    [SubDir] -> filename:join("out", SubDir);
    _Else -> "out"
  end.