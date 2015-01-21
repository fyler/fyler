-module(task_handler).
-include("../../include/log.hrl").


-export([
  init/2,
  malformed_request/2,
  process_post/2,
  allowed_methods/2,
  is_authorized/2,
  content_types_accepted/2,
  content_types_provided/2,
  resource_exists/2,
  get_task_status/2,
  delete_resource/2,
  delete_completed/2
]).

-record(state, {
  method :: get | post | delete,
  id :: non_neg_integer(),
  status :: queued | progress | success | abort
}).

init(Req, _Opts) ->
  {cowboy_rest, Req, #state{}}.

allowed_methods(Req, State) ->
  {[<<"GET">>, <<"POST">>, <<"DELETE">>], Req, State}.

malformed_request(Req, #state{} = State) ->
  BindingId = cowboy_req:binding(id, Req),
  case cowboy_req:method(Req) of
    <<"POST">> ->
      if BindingId =:= undefined -> {false, Req, State#state{method = post}};
                            true -> {true, Req, State}
      end;
    <<"GET">> ->
      if BindingId =:= undefined -> {true, Req, State};
                            true -> {false, Req, State#state{method = get, id = BindingId}}
      end;
    <<"DELETE">> ->
      if BindingId =:= undefined -> {true, Req, State};
                            true -> {false, Req, State#state{method = delete, id = BindingId}}
      end
  end.

is_authorized(Req, #state{method = get} = State) ->
  Opts = cowboy_req:parse_qs(Req),
  Reply = case proplists:get_value(<<"fkey">>, Opts, undefined) of
            undefined -> {false,<<"">>};
            Key -> fyler_server:is_authorized(Key)
          end,
  {Reply, Req, State};

is_authorized(Req, State) ->
  Reply = case cowboy_req:body_qs(Req) of
            {ok, X, _} ->
              ?D({req_data,X}),
              case proplists:get_value(<<"fkey">>,X) of
                undefined -> {false,<<"">>};
                Key -> fyler_server:is_authorized(Key)
              end;
            _ -> {false,<<"">>}
          end,
  {Reply, Req, State}.

content_types_accepted(Req, State) ->
  {[{'*',process_post}],Req,State}.

content_types_provided(Req, State) ->
  {[{{<<"text">>, <<"html">>, '*'}, get_task_status}],Req,State}.

resource_exists(Req, #state{method = post} = State) ->
  {false, Req, State};

resource_exists(Req, #state{id = Id} = State) ->
  case fyler_server:task_status(Id) of
    undefined ->
      {false, Req, State};
    Status ->
      {true, Req, State#state{status = Status}}
  end.

get_task_status(Req, #state{status = Status} = State) ->
  {jiffy:encode({[{status, Status}]}), cowboy_req:set_resp_header(<<"content-type">>, <<"application/json">>, Req), State}.


process_post(Req, State) ->
  case cowboy_req:body_qs(Req) of
    {ok, X, _} ->
      case validate_post_data(X) of
        [Url, Type, Options] -> 
          ?D({post_data, Url, Type}), 
          case fyler_server:run_task(Url, Type, Options) of
            {ok, Id} ->
              Resp_ = cowboy_req:set_resp_header(<<"content-type">>, <<"application/json">>, Req),
              {true, cowboy_req:set_resp_body(jiffy:encode({[{id, Id}]}), Resp_), State};
            _ ->
              {stop, cowboy_req:reply(403,Req), State}
          end;
        false -> ?D(<<"wrong post data">>),
          {stop, cowboy_req:reply(403,Req), State}
      end;
    Else -> 
      ?D({<<"no data">>,Else}),
      {stop, cowboy_req:reply(403,Req), State}
  end.

delete_resource(Req, #state{id = Id, status = queued} = State) ->
  fyler_server:cancel_task(Id),
  {true, Req, State};

delete_resource(Req, #state{id = Id, status = progress} = State) ->
  fyler_server:cancel_task(Id),
  {true, Req, State};

delete_resource(Req, State) ->
  {true, Req, State}.

delete_completed(Req, State) ->
  Resp = cowboy_req:set_resp_header(<<"content-type">>, <<"application/json">>, Req),
  {true, cowboy_req:set_resp_body(jiffy:encode({[{status, ok}]}), Resp), State}.

validate_post_data(Data) ->
  ?D(Data),
  Keys = [<<"url">>, <<"type">>],
  Opts = proplists:get_keys(Data),
  BinData = [proplists:get_value(Key, Data) || Key <- Keys],
  Options = [{binary_to_atom(Opt,latin1),proplists:get_value(Opt, Data)} || Opt <- Opts],
  Reply = [binary_to_list(X) || X <- BinData, X =/= undefined]++[Options],
  if length(Reply) == length(Keys)+1 ->
    Reply;
    true -> false
  end.
