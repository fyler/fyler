-module(ya_cli).

-author("paderinandrey").

-include("../include/log.hrl").
-include("fyler.hrl").

%% API
-export([instance/2, ip_address_pattern/0,
   start_instance/2, stop_instance/2]).

instance(Id, _Options) ->
  os:cmd(io_lib:format("yc compute instance get ~s --format yaml", [Id])).

start_instance(Id, _Options) ->
  os:cmd(io_lib:format("yc compute instance start ~s", [Id])).

stop_instance(Id, _Options) ->
  os:cmd(io_lib:format("yc compute instance stop ~s", [Id])).

ip_address_pattern() ->
  "primary_v4_address:\n\\s+address:\\s(?<ip>[(\\d{1,3}\\.){3}\\d{1,3}]*)".
