%% Copyright
-module(fyler).
-author("palkan").

-export([start/0, stop/0, upgrade/0, ping/0]).

-define(APPS,[crypto,lager,ranch,cowboy]).

start() ->
  ensure_started(?APPS),
  application:start(fyler).

stop() ->
  application:stop(fyler),
  stop_apps(?APPS).

upgrade() ->
 ok.

ping() ->
  pong.


%%
%% Utils
%%


ensure_started([]) -> ok;
ensure_started([App | Apps]) ->
  case application:start(App) of
    ok -> ensure_started(Apps);
    {error, {already_started, App}} -> ensure_started(Apps)
  end.

stop_apps([]) -> ok;
stop_apps([App | Apps]) ->
  application:stop(App),
  stop_apps(Apps).
