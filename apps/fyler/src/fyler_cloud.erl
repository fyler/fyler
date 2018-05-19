-module(fyler_cloud).

-include("fyler.hrl").
-include("../include/log.hrl").

%% API
-export([instance/2, start_instance/2, stop_instance/2, re_pattern/1]).

instance(CloudType, Id) ->
  case CloudType of
    openstack -> openstack_cli:instance(Id);
    _ -> aws_cli:instance(Id)
  end.

start_instance(CloudType, Id) ->
  case CloudType of
    openstack -> openstack_cli:start_instance(Id);
    _ -> aws_cli:start_instance(Id)
  end.

stop_instance(CloudType, Id) ->
  case CloudType of
    openstack -> openstack_cli:stop_instance(Id);
    _ -> aws_cli:stop_instance(Id)
  end.

re_pattern(CloudType) ->
  case CloudType of
    openstack -> openstack_cli:ip_address_pattern();
    _ -> aws_cli:ip_address_pattern()
  end.
