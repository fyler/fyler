#! /usr/local/bin/escript
%%! -pa ebin

main([]) ->

  {ok, [Host]} = io:fread("Enter host: ", "~s"),
  {ok, [Task]} = io:fread("Enter task: ", "~s"),
  Line = io:get_line("File names: "),
  Names = string:tokens(string:strip(Line,both,$\n)," "),
  io:format("host ~p, name ~p",[Host,Names]),
  inets:start(),
  [send(Host++F,Task) || F <- Names].

send(Path,Type) ->
  Method = post,
  URL = "http://localhost:8008/api/tasks",
  Header = [],
  Mime = "application/x-www-form-urlencoded",
  Body = "url="++Path++"&type="++Type,
  HTTPOptions = [],
  Options = [],
  io:format("Send task: ~p ~p~n",[Path,Type]),
  {ok, {R,_,_}} = httpc:request(Method, {URL, Header, Mime, Body}, HTTPOptions, Options),
  io:format("Response: ~p~n",[R]).