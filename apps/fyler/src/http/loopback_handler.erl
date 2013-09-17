-module(loopback_handler).
-include("../../include/log.hrl").


-export([
  init/3,
  process_post/2,
  allowed_methods/2,
  content_types_accepted/2,
  content_types_provided/2,
  to_json/2,
  terminate/3
]).

init({tcp, http}, _Req, _Opts) ->
  {upgrade, protocol, cowboy_rest}.

content_types_accepted(Req, State) ->
  {[{'*',process_post}],Req,State}.

content_types_provided(Req, State) ->
  {[{{<<"text">>, <<"html">>, '*'}, to_json}],Req,State}.

allowed_methods(Req, State) ->
  {[<<"GET">>, <<"POST">>, <<"DELETE">>], Req, State}.

to_json(Req,State) ->
  {<<"ok">>,Req,State}.

process_post(Req, State) ->
  case cowboy_req:body_qs(Req) of
    {ok, X, _} ->
       ?D({post_data,X});
    _ -> ?D(<<"no data">>)
  end,
  {true, Req, State}.

terminate(_Reason, _Req, _State) ->
  ok.