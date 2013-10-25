%% Copyright
-author("palkan").

-define(D(X), lager:debug("~p:~p ~p",[?MODULE, ?LINE, X])).
-define(I(X), lager:info("~p:~p ~p",[?MODULE, ?LINE, X])).
-define(E(X), lager:error("~p:~p ~p",[?MODULE, ?LINE, X])).
