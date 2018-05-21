-module(openstack_cli).
-author("paderinandrey").

-include("../include/log.hrl").
-include("fyler.hrl").

%% API
-export([instance/2, start_instance/2, stop_instance/2, ip_address_pattern/0]).

instance(Id, Options) ->
  os:cmd(io_lib:format("openstack --os-cloud=~s server show ~s --format=json", [cloud_name(Options), Id])).

start_instance(Id, Options) ->
  os:cmd(io_lib:format("openstack --os-cloud=~s server start ~s", [cloud_name(Options), Id])).

stop_instance(Id, Options) ->
  os:cmd(io_lib:format("openstack --os-cloud=~s server stop ~s", [cloud_name(Options), Id])).

ip_address_pattern() ->
  "\"addresses\": \"int-net1=(?<ip>[^\"]*),.*\"".

cloud_name(Options) ->
  maps:get(name, Options, default).
