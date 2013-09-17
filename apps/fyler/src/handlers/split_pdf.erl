%%% @doc Module handling document conversion with unoconv
%%% @end

-module(split_pdf).
-include("../fyler.hrl").
-include("../../include/log.hrl").

-export([run/1,run/2]).

-define(COMMAND(In,Split,Out), "pdftk \""++In++"\" cat "++Split++" output \""++Out++"\"").


run(File) -> run(File,[]).

run(#file{tmp_path = Path, name = Name, dir = Dir},Opts) ->
  Start = ulitos:timestamp(),
  case proplists:get_value(split,Opts) of
    undefined -> ?D(split_options_undefined),
                 {ok,#job_stats{time_spent = 0, result_path = [list_to_binary(Path)]}};
    Split ->  PDF = Dir ++ "/" ++ Name ++ "_split.pdf",
              ?D({"command",?COMMAND(Path,binary_to_list(Split),PDF)}),
              Data = os:cmd(?COMMAND(Path,binary_to_list(Split),PDF)),
              case  filelib:is_file(PDF) of
                    true -> {ok,#job_stats{time_spent = ulitos:timestamp() - Start, result_path = [list_to_binary(PDF)]}};
                    _ -> {error, Data}
              end
  end.






