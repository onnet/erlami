-module(erlami_app).
-behaviour(application).

-include_lib("erlami.hrl").
-include_lib("erlami_message.hrl").

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================
start(_StartType, _StartArgs) ->
    {ok, AsteriskServers} = application:get_env(servers),
    {ok, SupPid} = erlami_sup:start_link(),
    lists:foreach(
        fun({ServerName, ServerInfo}) ->
            WorkerName = erlami_client:get_worker_name(ServerName),
            lager:debug("Starting client supervisor: ~p", [WorkerName]),
            erlami_sup:start_child(ServerName, WorkerName, ServerInfo)
        end,
        AsteriskServers
    ),
    {ok, SupPid}.

stop(_State) ->
    ok.
