%% Copyright
-module(fyler).
-author("palkan").

-export([start/0, stop/0, upgrade/0, ping/0]).

-define(APPS,[crypto,os_mon,lager,ranch,cowlib,cowboy]).

start() ->
  ulitos_app:ensure_started(?APPS),
  application:start(fyler).

stop() ->
  application:stop(fyler),
  ulitos_app:stop_apps(?APPS).

upgrade() ->
 ulitos_app:reload(fyler),
 ok.

ping() ->
  pong.



