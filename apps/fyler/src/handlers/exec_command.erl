-module(exec_command).

-export([run/1, run/2]).

run(Command) ->
  run(Command, stdout).

run(Command, Out) ->
  {ok, _, _} = exec:run(["/bin/bash", "-c", Command], [Out, monitor]),
  loop(<<>>, Out).

loop(Data, Out) ->
  receive
    {Out, _, Part} ->
      loop(<<Data/binary, Part/binary>>, Out);
    _ ->
      Data
  end.