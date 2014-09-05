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
    ConfigPath = case ?Config(config,undefined) of
      undefined -> "fyler.config";
      Else -> Else
    end,
    ulitos_app:load_config(fyler,ConfigPath,["/etc"]),
    fyler_sup:start_link(?Config(role,server)).

stop(_State) ->
    ok.
