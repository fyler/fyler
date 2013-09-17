#! /usr/local/bin/escript
%%! -pa ebin

main([URL,Type]) ->
  main([URL,Type,undefined]);

main([URL,Type,Callback]) ->
  inets:start(),
  send(URL,Type,Callback);

main([]) ->
  {ok, [Host]} = io:fread("Enter host: ", "~s"),
  {ok, [Task]} = io:fread("Enter task: ", "~s"),
  Line = io:get_line("File names: "),
  Names = string:tokens(string:strip(Line,both,$\n)," "),
  io:format("host ~p, name ~p",[Host,Names]),
  inets:start(),
  [send(Host++F,Task,undefined) || F <- Names].

send(Path,Type,Callback) ->
  Method = post,
  URL = "http://localhost:8008/api/tasks",
  Header = [],
  Mime = "application/x-www-form-urlencoded",
  Body = body(Path,Type,Callback),
  HTTPOptions = [],
  Options = [],
  io:format("Send task: ~p ~p~n",[Path,Type]),
  {ok, {R,_,_}} = httpc:request(Method, {URL, Header, Mime, Body}, HTTPOptions, Options),
  io:format("Response: ~p~n",[R]).

body(Path,Type,undefined) ->
  "url="++Path++"&type="++Type;

body(Path,Type,Callback) ->
  "url="++Path++"&type="++Type++"&callback="++Callback.