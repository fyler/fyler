#! /usr/local/bin/escript
%%! -pa ebin -pa deps/ulitos/ebin

main(_) ->
  {ok, [Login]} = io:fread("Enter login: ", "~s"),
  {ok, [Pass]} = io:fread("Enter pass: ", "~s"),
  inets:start(),
  crypto:start(),
  send(Login,Pass).

send(Login,Pass) ->
  Method = post,
  URL = "http://localhost:8008/api/auth",
  Header = [],
  Mime = "application/x-www-form-urlencoded",
  Body = body(Login,Pass),
  HTTPOptions = [],
  Options = [],
  {ok, {R,_,B}} = httpc:request(Method, {URL, Header, Mime, Body}, HTTPOptions, Options),
  io:format("Response: ~p~n Body:~p~n",[R,B]).

body(Login,Pass) ->
  "login="++Login++"&pass="++Pass.