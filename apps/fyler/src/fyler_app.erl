-module(fyler_app).
-behaviour(application).
-include("fyler.hrl").

%% Application callbacks
-export([start/2, stop/1]).



%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    lager:info("Starting application: fyler"),
    ulitos:load_config(fyler,"fyler.config"),
    fyler_sup:start_link(?Config(role,server)).

stop(_State) ->
    ok.
