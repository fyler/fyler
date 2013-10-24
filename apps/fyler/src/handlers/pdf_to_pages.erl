%%% @doc Module handling generating pages from pdf
%%% @end

-module(pdf_to_pages).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1, run/2]).

-define(COMMAND(In, OutName), "gs -dNOPAUSE -dBATCH -dSAFER -sDEVICE=jpeg  -sOutputFile=\"" ++ OutName ++ "page_%d.jpg\" -r200 -q \"" ++ In ++ "\" -c quit").
-define(COMMAND2(In, Out), "jpegtran -copy none -progressive -outfile \"" ++ Out ++ "\" \"" ++ In ++ "\"").

run(File) -> run(File, []).

run(#file{tmp_path = Path, name = Name, dir = Dir}, _Opts) ->
  Start = ulitos:timestamp(),
  PagesDir = Dir ++ "/pages",
  ok = file:make_dir(PagesDir),
  ?D({"command", ?COMMAND(Path, PagesDir ++ "/")}),
  Data = os:cmd(?COMMAND(Path, PagesDir ++ "/")),
  ?D({gs_data, Data}),
  case filelib:wildcard("*.jpg", PagesDir) of
    [] -> {error, Data};
    List ->
      List2 = case make_progressive_jpeg(PagesDir, List) of
                {ok, List_} ->
                  [file:delete(PagesDir ++ "/" ++ Old) || Old <- List],
                  List_;
                false -> List
              end,
      JSON = jiffy:encode({
        [
          {name, list_to_binary(Name)},
          {dir, <<"pages">>},
          {length, length(List2)},
          {pages, [list_to_binary(T) || T <- List2]}
        ]
      }),
      JSONFile = Dir ++ "/" ++ Name ++ ".pages.json",
      {ok, F} = file:open(JSONFile, [write]),
      file:write(F, JSON),
      file:close(F),
      {ok, #job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(Name ++ ".pages.json")]}}
  end.



make_progressive_jpeg(Dir, List) ->
  [os:cmd(?COMMAND2(Dir ++ "/" ++ F, Dir ++ "/pr_" ++ F)) || F <- List],
  case filelib:wildcard("pr_*.jpg", Dir) of
    [] -> ?D({error_converting_to_progressive, Dir}), false;
    List2 -> {ok, List2}
  end.





