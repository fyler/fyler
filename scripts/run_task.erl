#! /usr/local/bin/escript
%%! -pa ebin

main([URL,Type,Token]) ->
  main([URL,Type,undefined,Token]);

main([URL,Type,Callback,Token]) ->
  inets:start(),
  send(URL,Type,Callback,Token);

main([]) ->
  {ok, [Host]} = io:fread("Enter host: ", "~s"),
  {ok, [Task]} = io:fread("Enter task: ", "~s"),
  {ok, [Token]} = io:fread("Enter token: ", "~s"),
  Line = io:get_line("File names: "),
  Names = string:tokens(string:strip(Line,both,$\n)," "),
  io:format("host ~p, name ~p",[Host,Names]),
  inets:start(),
  [send(Host++F,Task,undefined,Token) || F <- Names].

send(Path,Type,Callback,Token) ->
  Method = post,
  URL = "http://localhost:8008/api/tasks",
  Header = [],
  Mime = "application/x-www-form-urlencoded",
  Body = body(Path,Type,Callback,Token),
  HTTPOptions = [],
  Options = [],
  io:format("Send task: ~p ~p~n",[Path,Type]),
  {ok, {R,_,B}} = httpc:request(Method, {URL, Header, Mime, Body}, HTTPOptions, Options),
  io:format("Response: ~p~n Body:~p~n",[R,B]).

body(Path,Type,undefined,Token) ->
  "url="++Path++"&type="++Type++"&fkey="++Token;

body(Path,Type,Callback,Token) ->
  "url="++Path++"&type="++Type++"&callback="++Callback++"&fkey="++Token.
