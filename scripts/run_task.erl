#! /usr/local/bin/escript
%%! -pa ebin

main([Path, Type]) ->
    inets:start(),
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
