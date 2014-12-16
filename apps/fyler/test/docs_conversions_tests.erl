-module(docs_conversions_tests).
-include("../src/fyler.hrl").
-include("../include/log.hrl").
-include_lib("kernel/include/file.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(PATH(File), filename:join([code:priv_dir(fyler),"..","test","support", File])).

-define(setup(F), {setup, fun setup_/0, fun cleanup_/1, F}).

-define(TIMEOUT, 60).

file_size(Path) ->
  case file:read_file_info(Path) of
    {ok,#file_info{size = Size}} -> Size;
    _ -> 0
  end.

delete_files([]) ->
  ok;

delete_files([File|Files]) ->
  file:delete(?PATH(File)),
  delete_files(Files).

setup_() ->
  lager:start(),
  file:make_dir(?PATH("tmp")).

cleanup_(_) ->
  ulitos_file:recursively_del_dir(?PATH("tmp")),
  ulitos_file:recursively_del_dir(?PATH("thumbs")),
  ulitos_file:recursively_del_dir(?PATH("swfs")),
  file:delete(?PATH("10.pdf")),
  file:delete(?PATH("18.html")),
  file:delete(?PATH("13.pdf")),
  file:delete(?PATH("2.pdf")),
  file:delete(?PATH("3.pdf")),
  file:delete(?PATH("6.pdf")),
  file:delete(?PATH("7_split.pdf")),
  case filelib:wildcard("*.json",?PATH("")) of
    Files2 when is_list(Files2) -> delete_files(Files2);
    _ -> false
  end,
  case filelib:wildcard("*.png",?PATH("")) of
    Files4 when is_list(Files4) -> delete_files(Files4);
    _ -> false
  end,
  application:stop(lager).



doc_unoconv_test_() ->
  ?setup([
    {timeout, ?TIMEOUT, [ppt_to_pdf_t_()]},
    {timeout, ?TIMEOUT, [doc_to_pdf_t_()]},
    {timeout, ?TIMEOUT, [doc_to_pdf_2_t_()]},
    {timeout, ?TIMEOUT, [xls_to_pdf_t_()]},
    {timeout, ?TIMEOUT, [xls_to_pdf_2_t_()]}
   ]
  ).

doc_swftools_test_() ->
  ?setup(
    [
      {timeout, ?TIMEOUT, [doc_to_pdf_swf_t_()]},
      {timeout, ?TIMEOUT, [doc_to_pdf_thumbs_t_()]},
      {timeout, ?TIMEOUT, [pdf_to_swf_t_()]},
      {timeout, ?TIMEOUT, [pdf_to_swf_thumbs_t_()]}
    ]
  ).

doc_pdftk_test_()->
  ?setup(
    [ 
      {timeout, ?TIMEOUT, [pdf_split_t_()]}  
    ]
  ).

doc_unpack_test_()->
  ?setup(
    [ 
      {timeout, ?TIMEOUT, [zip_unpack_t_()]}  
    ]
  ).

doc_to_pdf_t_() ->
  fun() ->
    Res = doc_to_pdf:run(#file{tmp_path = ?PATH("2.docx"), name = "2", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(2, length(Stat#job_stats.result_path))
  end.     

doc_to_pdf_2_t_() ->
  fun() ->
    Res = doc_to_pdf:run(#file{tmp_path = ?PATH("3.doc"), name = "3", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(2, length(Stat#job_stats.result_path))
  end.     

xls_to_pdf_t_() ->
  fun() ->
    Res = doc_to_pdf:run(#file{tmp_path = ?PATH("6.xlsx"), name = "6", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(2, length(Stat#job_stats.result_path))
  end.    

xls_to_pdf_2_t_() ->
  fun() ->
    Res = doc_to_pdf:run(#file{tmp_path = ?PATH("10.xls"), name = "10", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(2, length(Stat#job_stats.result_path))
  end.  

ppt_to_pdf_t_() ->
  fun() ->
    Res = doc_to_pdf:run(#file{tmp_path = ?PATH("13.pptx"), name = "13", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(2, length(Stat#job_stats.result_path))
  end.     

doc_to_pdf_swf_t_() ->
  fun() ->
    Res = doc_to_pdf_swf:run(#file{tmp_path = ?PATH("2.docx"), name = "2", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(3, length(Stat#job_stats.result_path))
  end.  

doc_to_pdf_thumbs_t_() ->
  fun() ->
    Res = doc_to_pdf_thumbs:run(#file{tmp_path = ?PATH("2.docx"), name = "2", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(2, length(Stat#job_stats.result_path))
  end.  

pdf_split_t_() ->
  fun() ->
    OldSize = file_size(?PATH("7.pdf")),
    Res = split_pdf:run(#file{tmp_path = ?PATH("7.pdf"), name = "7", dir = ?PATH("")},[{split,<<"10-20 25-end">>}]),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(1, length(Stat#job_stats.result_path)),
    NewSize = file_size(?PATH("7_split.pdf")),
    ?assert(OldSize>NewSize)
  end.

pdf_to_swf_t_() ->
  fun() ->
    Res = pdf_to_swf:run(#file{tmp_path = ?PATH("7.pdf"), name = "7", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(1, length(Stat#job_stats.result_path))
  end. 

pdf_to_swf_thumbs_t_() ->
  fun() ->
    Res = pdf_to_swf_thumbs:run(#file{tmp_path = ?PATH("7.pdf"), name = "7", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(2, length(Stat#job_stats.result_path))
  end. 

zip_unpack_t_() ->
  fun() ->
    Res = unpack_html:run(#file{tmp_path = ?PATH("18.zip"), name = "18", dir = ?PATH("")}),
    ?assertMatch({ok,#job_stats{}}, Res),
    {_, Stat} = Res,
    ?assertEqual(1, length(Stat#job_stats.result_path))
  end. 