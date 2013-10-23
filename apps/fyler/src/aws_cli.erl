%% Copyright
-module(aws_cli).
-author("palkan").

-include("../include/log.hrl").

-define(NOT_EXISTS_SIZE,87).

%% API
-export([copy_object/2, copy_folder/2, dir_exists/1]).


%% @doc
%% @end
-spec copy_object(string(),string()) ->  any().

copy_object(From,To) ->
  ?D({aws_command,"aws s3 cp --acl public-read "++From++" "++To}),
  os:cmd("aws s3 cp --acl public-read "++From++" "++To).

%% @doc
%% @end
-spec copy_folder(string(),string()) ->  any().

copy_folder(From,To) ->
  ?D({aws_command,"aws s3 sync --acl public-read "++From++" "++To}),
  os:cmd("aws s3 sync  --acl public-read "++From++" "++To).

%% @doc
%% Check whether s3 dir prefix exists.
%%
%% <b>Note</b>: don't forget about tailing slash;
%% Algorithm is empirical, but works fine.
%% @end

-spec dir_exists(Path::list()) -> boolean().

dir_exists(Path) ->
  ?D({aws_command,"aws s3 ls "++Path}),
  Res = os:cmd("aws s3 ls "++Path),
  length(Res)-length(Path) > ?NOT_EXISTS_SIZE.

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").



exists_test_() ->
  [
    ?_assertEqual(true, dir_exists("s3://tbconvert/recordings/2/record_10/")),
    ?_assertEqual(true, dir_exists("s3://tbconvert")),
    ?_assertEqual(false, dir_exists("s3://tbconvert/1.mp4")),
    ?_assertEqual(false, dir_exists("s3://tbconvert/recordings/2/record_10213/")),
    ?_assertEqual(false, dir_exists("s3://tbconvert/no_existed_dir/")),
    ?_assertEqual(false, dir_exists("s3://tb.records")),
    ?_assertEqual(false, dir_exists("s3://no_existed_bucket"))
  ].

-endif.