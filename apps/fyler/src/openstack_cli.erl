-module(openstack_cli).
-author("paderinandrey").

-include("../include/log.hrl").
-include("fyler.hrl").

%% API
-export([instance/1, start_instance/1, stop_instance/1, ip_address_pattern/0]).

instance(Id) ->
  os:cmd(io_lib:format("openstack --os-cloud=~s server show ~s --format=json", [?Config(cloud_name, 'default'), Id])).

start_instance(Id) ->
  os:cmd(io_lib:format("openstack --os-cloud=~s server start ~s", [?Config(cloud_name, 'default'), Id])).

stop_instance(Id) ->
  os:cmd(io_lib:format("openstack --os-cloud=~s server stop ~s", [?Config(cloud_name, 'default'), Id])).

ip_address_pattern() ->
  "\"addresses\": \"int-net1=(?<ip>[^\"]*),.*\"".
