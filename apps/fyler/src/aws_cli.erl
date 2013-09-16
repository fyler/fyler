%% Copyright
-module(aws_cli).
-author("palkan").

%% API
-export([copy_object/2, copy_folder/2]).


%% @doc
%% @end
-spec copy_object(string(),string()) ->  any().

copy_object(From,To) ->
  os:cmd("aws s3 cp "++From++" "++To).

%% @doc
%% @end
-spec copy_folder(string(),string()) ->  any().

copy_folder(From,To) ->
  os:cmd("aws s3 sync "++From++" "++To).
