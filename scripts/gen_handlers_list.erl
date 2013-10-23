#! /usr/local/bin/escript
%%! -pa ebin

main(_) ->
  case filelib:wildcard("*.erl","apps/fyler/src/handlers") of
    [] -> io:format("handlers not found~n");
    List -> io:format("Add handlers: ~p~n",[List]),
            {ok,F} = file:open("apps/fyler/include/handlers.hrl",[write]),
            AtomList = to_atom_list(List),
            ok = file:write(F,io_lib:format("-define(Handlers,~p).",[AtomList])),
            file:close(F)
  end.

to_atom_list(List) -> to_atoms(List,[]).

to_atoms([],List) -> List;

to_atoms([File | Files], Acc) ->
  to_atoms(Files,[list_to_atom(lists:sublist(File,length(File)-4)) |Acc]).