-module(fyler_cloud).

-include("fyler.hrl").
-include("../include/log.hrl").

%% API
-export([cloud_handler/0]).

cloud_handler() ->
  CloudType = maps:get(type, ?Config(cloud_options, aws)),
  case CloudType of
    openstack -> openstack_cli;
    aws -> aws_cli;
    _ -> ?E({not_implemented, CloudType})
  end.
