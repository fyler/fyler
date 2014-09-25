-module(fyler_queue).
-author("ilia").
-define(MOD, 1000000007).

%% API
-export([new/0, is_empty/1, in/2, in/3, out/1, to_list/1, len/1]).

-export_type([fyler_queue/0, fyler_queue/1]).

-opaque fyler_queue(Item) :: {list({pos_integer(), {queue:queue(Item), pos_integer()}}), non_neg_integer(), non_neg_integer()}.

-opaque fyler_queue() :: fyler_queue(_).

-spec new() -> fyler_queue().
new() ->
  {[], 0, 0}.

-spec is_empty(Q :: fyler_queue()) -> boolean().
is_empty({[], 0, 0}) ->
  true;

is_empty(_) ->
  false.

-spec in(Item, Q1 :: fyler_queue(Item)) -> Q2 :: fyler_queue(Item).
in(Item, Queue) ->
  in(Item, 1, Queue).

in(Item, Priority, {[], 0, 0}) ->
  {[{1, {queue:in({Priority, Item}, queue:new()), 1}}], 1, 1};

in(Item, Priority, {[], Start, Counter}) ->
  {[{Priority, {queue:in({Priority, Item}, queue:new()), (((Counter - 1) div Priority) + 1) * Priority}}], Start, Counter};

in(Item, Priority, {[{MinPriority, {Queue, NextCounter}}|Queues], Start, Counter}) when Priority < MinPriority ->
  {[{Priority, {queue:in({Priority, Item}, queue:new()), (((Counter - 1) div Priority) + 1) * Priority}}, {MinPriority, {Queue, NextCounter}}|Queues], Start, Counter};

in(Item, Priority, {[{MinPriority, {Queue, NextCounter}}|Queues], Start, Counter}) ->
  {[{MinPriority, {queue:in({Priority, Item}, Queue), NextCounter}}|Queues], Start, Counter}.

-spec out(Q1 :: fyler_queue(Item)) ->
  {{value, Item}, Q2 :: fyler_queue(Item)} |
  {empty, Q1 :: fyler_queue(Item)}.
out({[], 0, 0}) ->
  {empty, {[], 0, 0}};

out({Queues, Start, Counter}) ->
  case find(Queues, Start, Counter) of
    {{value, Value}, NewQueue} ->
      {{value, Value}, NewQueue};
    {empty, {NewQueues, Start, Counter}} ->
      NewCounter = find_min_counter(NewQueues),
      if NewCounter > ?MOD -> out({lists:map(fun({MinPriority, {Queue, _}}) -> {MinPriority, {Queue, MinPriority}} end, NewQueues), Start, 1});
                      true -> out({NewQueues, 1, NewCounter})
      end
  end.

-spec to_list(Q :: fyler_queue(Item)) -> list(Item).

to_list(Queue) ->
  to_list(Queue, []).

to_list(Queue, Acc) ->
  case out(Queue) of
    {{value, Value}, NewQueue} ->
      to_list(NewQueue, [Value|Acc]);
    {empty, Queue} ->
      lists:reverse(Acc)
  end.

-spec len(Q :: fyler_queue()) -> non_neg_integer().

len({Queues, _, _}) ->
  lists:foldl(fun({_, {Queue, _}}, Acc) -> queue:len(Queue) + Acc end, 0, Queues).

%% internal functions
-spec find(list({pos_integer(), {queue:queue(Item), pos_integer()}}), non_neg_integer(), non_neg_integer()) ->
  {{value, Item}, Q2 :: fyler_queue(Item)} |
  {empty, Q1 :: fyler_queue(Item)}.

find(Queues, Start, Counter) ->
  find(Queues, Start, Counter, []).

find([], Start, Counter, Acc) ->
  {empty, {lists:reverse(Acc), Start, Counter}};

find([{MinPriority, {Queue, Counter}}|Queues], Start, Counter, Acc) when Start =< MinPriority ->
  case pop_queue(Queue, MinPriority, {Queues, Start, Counter}) of
    {{value, Value}, {NewQueues, Start, Counter}} ->
      AllQueues = lists:reverse(Acc) ++ NewQueues,
      case AllQueues of
        [] ->
          {{value, Value}, {[], 0, 0}};
        AllQueues ->
          {{value, Value}, {AllQueues, Start + 1, Counter}}
      end;
    {empty, {NewQueues, Start, Counter}} ->
      find(NewQueues, Start, Counter, Acc)
  end;

find([Queue|Queues], Start, Counter, Acc) ->
  find(Queues, Start, Counter, [Queue|Acc]).

-spec pop_queue(queue:queue(Item), pos_integer(), fyler_queue(Item)) ->
  {{value, Item}, Q2 :: fyler_queue(Item)} |
  {empty, Q1 :: fyler_queue(Item)}.

pop_queue(Queue, MinPriority, {Queues, Start, Counter} = PriorityQueue) ->
  case queue:out(Queue) of
    {{value, {MinPriority, Value}}, NewQueue} ->
      case queue:is_empty(NewQueue) of
        true ->
          {{value, Value}, {Queues, Start, Counter}};
        false ->
          {{value, Value}, {[{MinPriority, {NewQueue, Counter + MinPriority}}|Queues], Start, Counter}}
      end;
    {{value, {Priority, Value}}, NewQueue} ->
      NewPriorityQueue = in(Value, Priority, PriorityQueue),
      pop_queue(NewQueue, MinPriority, NewPriorityQueue);
    {empty, _} ->
      {empty, PriorityQueue}
  end.

-spec find_min_counter(list({pos_integer(), {queue:queue(), pos_integer()}})) -> pos_integer().

find_min_counter(Queues) ->
  find_min_counter(Queues, ?MOD + 1).

find_min_counter([{_, {_, Counter}}|Queues], Result) when Counter < Result ->
  find_min_counter(Queues, Counter);

find_min_counter([_|Queues], Result) ->
  find_min_counter(Queues, Result);

find_min_counter([], Result) ->
  Result.

-ifdef(TEST).

-include_lib("eunit/include/eunit.hrl").

new_test() ->
  ?assertEqual(new(), {[], 0, 0}).

in_test() ->
  Queue = new(),
  Queue1 = in(item1, Queue),
  Queue2 = in(item2, Queue1),
  Queue3 = in(item3, 2, Queue2),
  Queue4 = in(item4, Queue3),
  Queue5 = in(item5, 2, Queue4),
  {[{1, {Q1, 1}}], 1, 1} = Queue5,
  ?assertEqual(queue:to_list(Q1), [{1, item1}, {1, item2}, {2, item3}, {1, item4}, {2, item5}]).

is_empty_test() ->
  Queue = new(),
  Queue1 = in(a, Queue),
  Queue2 = in(a, 2, Queue1),
  ?assertEqual(is_empty(Queue), true),
  ?assertEqual(is_empty(Queue1), false),
  ?assertEqual(is_empty(Queue2), false),
  ?assertEqual(is_empty(in(a, 2, Queue)), false).

len_test() ->
  Queue = in(5, 3, in(4, 1, in(3, 4, in(2, 2, in(1, 1, new()))))),
  ?assertEqual(5, len(Queue)).

to_list_test() ->
  Queue = new(),
  Queue1 = in(5, in(4, in(3, in(2, in(1, Queue))))),
  Queue2 = in(5, 2, in(4, 2, in(3, 2, in(2, 2, in(1, 2, Queue))))),
  ?assertEqual([1, 2, 3, 4, 5], to_list(Queue1)),
  ?assertEqual([1, 2, 3, 4, 5], to_list(Queue2)).

out_test() ->
  Queue = new(),
  Queue0 = in(1, Queue),
  ?assertEqual({{value, 1}, {[], 0, 0}}, out(Queue0)),
  Queue1 = in(1, 1, in(2, 2, in(1, 1, in(2, 2, in(1, 1, Queue))))),
  ?assertEqual([1, 1, 2, 1, 2], to_list(Queue1)),
  Queue2 = in(3, 3, in(2, 2, in(3, 3, in(2, 2, in(3, 3, Queue))))),
  ?assertEqual([2, 3, 2, 3, 3], to_list(Queue2)),
  Queue3 = in(1, 1, in(2, 2, in(2, 2, in(1, 1, in(3, 3, in(2, 2, in(1, 1, in(2, 2, in(3, 3, Queue))))))))),
  ?assertEqual([1, 1, 2, 1, 3, 2, 2, 3, 2], to_list(Queue3)),
  Queue4 = in(3, 3, in(1, 1, in(1, 1, in(1, 1, Queue)))),
  ?assertEqual([1, 1, 1, 3], to_list(Queue4)),
  {{value, _}, Queue5} = out(Queue2),
  ?assertEqual([3, 2, 3, 3, 10], to_list(in(10, 10, Queue5))).

-endif.
