%% Copyright
-module(aws_cli).
-author("palkan").

-include("../include/log.hrl").

%% API
-export([copy_object/2, copy_object/3, copy_folder/2, copy_folder/3, dir_exists/1, instance/1, start_instance/1, stop_instance/1]).


copy_object(From,To) ->
  copy_object(From,To,public).

-spec copy_object(string(),string(),any()) -> any().
copy_object(From,To,Acl) ->
  os:cmd(io_lib:format("aws s3 cp --acl ~s ~s ~s",[access_to_acl(Acl),From,To])).

copy_folder(From,To) ->
  copy_folder(From,To,public).

-spec copy_folder(string(),string(),any()) -> any().
copy_folder(From,To,Acl) ->
  os:cmd(io_lib:format("aws s3 sync --acl ~s ~s ~s",[access_to_acl(Acl),From,To])).

instance(Id) ->
  os:cmd(io_lib:format("aws ec2 describe-instances --instance-id ~s", [Id])).

start_instance(Id) ->
  os:cmd(io_lib:format("aws ec2 start-instances --instance-ids ~s", [Id])).

stop_instance(Id) ->
  os:cmd(io_lib:format("aws ec2 stop-instances --instance-ids ~s", [Id])).

%% @doc
%% Check whether s3 dir prefix exists.
%% @end

-spec dir_exists(Path::list()) -> boolean().

dir_exists(Path) ->
  Res = os:cmd("aws s3 ls "++Path),
  parse_ls_result(Res).

parse_ls_result([]) ->
  false;

parse_ls_result(Str) ->
  not (string:str(Str,"(NoSuchBucket)")>0).

access_to_acl(private) ->
  "private";

access_to_acl(public) ->
  "public-read";

access_to_acl(authorized) ->
  "authenticated-read";

access_to_acl(_) ->
  "public".


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

parse_ls_result_test() ->
  ?assert(parse_ls_result("some letters")),
  ?assertNot(parse_ls_result("")),
  ?assertNot(parse_ls_result("\nA client error (NoSuchBucket) occurred when calling the ListObjects operation: The specified bucket does not exist\n")).

-endif.