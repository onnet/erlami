%%% Main supervisor for Erlami application.
%%%
%%% Copyright 2012 Marcelo Gornstein <marcelog@gmail.com>
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
-module(erlami_sup).
-author("Marcelo Gornstein <marcelog@gmail.com>").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").
-behaviour(supervisor).

%% API
-export([start_link/0, start_child/2, stop_child/1]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(
    CHILD(Name, Args),
    {Name,
        {erlami_sup_client, start_link, Args},
        permanent, infinity, supervisor, [?MODULE]
    }
).

%% ===================================================================
%% API functions
%% ===================================================================
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(ServerName, ServerInfo) ->
    supervisor:start_child(?MODULE, [ServerName, ServerInfo]).

-spec stop_child(pid()|string()|atom()) -> 'ok' | {'error', 'not_found'}.
stop_child(Pid) when is_pid(Pid) ->
    supervisor:terminate_child(?MODULE, Pid);
stop_child(ServerName) ->
    case whereis(erlami_client:get_worker_name(ServerName)) of
        Pid when is_pid(Pid) ->
            supervisor:terminate_child(?MODULE, Pid);
        _ ->
            {'error', 'not_found'}
    end.


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init([]) ->
    Client = {erlami_client,
        {erlami_client, start_link, []},
        permanent, brutal_kill, worker, [erlami_client]
    },
    Children = [Client],
    RestartStrategy = {simple_one_for_one, 10, 1},
    {ok, {RestartStrategy, Children}}.
