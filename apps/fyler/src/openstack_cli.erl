-module(openstack_cli).
-author("paderinandrey").

-include("../include/log.hrl").
-include("fyler.hrl").

%% API
-export([instance/2, start_instance/2, stop_instance/2, ip_address_pattern/0]).

instance(Id, Options) ->
  CloudName = maps:get(name, Options, default),
  os:cmd(io_lib:format("openstack --os-cloud=~s server show ~s --format=json", [CloudName, Id])).

start_instance(Id, Options) ->
  CloudName = maps:get(name, Options, default),
  os:cmd(io_lib:format("openstack --os-cloud=~s server start ~s", [CloudName, Id])).

stop_instance(Id, Options) ->
  CloudName = maps:get(name, Options, default),
  os:cmd(io_lib:format("openstack --os-cloud=~s server stop ~s", [CloudName, Id])).

ip_address_pattern() ->
  "\"addresses\": \"int-net1=(?<ip>[^\"]*),.*\"".
