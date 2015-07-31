-module(exec_command).

-export([run/1, run/2, run_link/2]).

run(Command) ->
  run(Command, stdout).

run(Command, Out) ->
  {ok, _, _} = exec:run(["/bin/bash", "-c", Command], [Out, monitor]),
  loop(<<>>, Out).

run_link(Command, Options) ->
  exec:run_link(["/bin/bash", "-c", Command], Options).

loop(Data, Out) ->
  receive
    {Out, _, Part} ->
      loop(<<Data/binary, Part/binary>>, Out);
    _ ->
      Data
  end.