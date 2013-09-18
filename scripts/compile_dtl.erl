#! /usr/local/bin/escript
%%! -pa ebin -pa deps/erlydtl/ebin

main(_) ->
  c_tpl().

c_tpl() ->
  c_tpl([{out_dir,"apps/fyler/ebin"}]).

c_tpl(Opts) ->
  c_tpl(filelib:wildcard("apps/fyler/tpl/*.dtl"), Opts).

c_tpl([], _Opts) -> ok;
c_tpl([File | Files], Opts) ->
  ok = erlydtl:compile(File, re:replace(filename:basename(File), ".dtl", "_tpl", [global, {return, list}]), Opts),
  c_tpl(Files, Opts).