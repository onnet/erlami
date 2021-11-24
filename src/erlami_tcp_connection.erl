%%% Helper functions for connecting and sending data to the asterisk server.
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
-module(erlami_tcp_connection).
-author("Marcelo Gornstein <marcelog@gmail.com>").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").
-define(SERVER, ?MODULE).

-behaviour(erlami_connection).

-include_lib("kernel/include/inet.hrl").
-include_lib("erlami_connection.hrl").

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([open/1, read_line/2, send/2, close/1]).

%% @doc Will resolve and try to establish a connection to an asterisk box.
-spec open(Options::[{Key::atom(),Value::term()}]) -> {gen_tcp:socket()}.
open(Options) ->
    {host, Host} = lists:keyfind(host, 1, Options),
    {port, Port} = lists:keyfind(port, 1, Options),
    {ok, #hostent{h_addr_list=Addresses}}
        = erlami_connection:resolve_host(Host),
    try real_connect(Addresses, Port) of
        {ok, Socket} ->
            {ok, #erlami_connection{
                send = fun(Data) ->
                    ?MODULE:send(Socket, Data)
                end,
                read_line = fun(Timeout) ->
                    ?MODULE:read_line(Socket, Timeout)
                end,
                close = fun() ->
                    ?MODULE:close(Socket)
                end
            }};
        _ ->
            'error'
    catch
        _ ->
            'error'
    end.

%% @doc Establishes a connection to the asterisk box, either via normal tcp or
%% tcp+ssl. Will try to get all available address for the given hostname or
%% ip address and try to connect to them in order. Will stop when a connection
%% can be established or when failed after trying each one of the addresses
%% found.
-spec real_connect(
    [Host::inet:hostname()], Port::inet:port_number()
) -> {ok, gen_tcp:socket()}.
real_connect([], _Port) ->
    outofaddresses;

real_connect([Address|Tail], Port) ->
    case gen_tcp:connect(Address, Port, [{active, false}, {packet, line}]) of
        {ok, Socket} ->
            {ok, Socket};
        _ -> real_connect(Tail, Port)
    end.

%% @doc Used to send an action() via a tcp or tcp+ssl socket, selected by
%% pattern matching.
-spec send(Socket::gen_tcp:socket(), Action::erlami_message:action()) -> ok.
send(Socket, Action) ->
    ok = gen_tcp:send(Socket, erlami_message:marshall(Action)).

%% @doc Closes and cleans up the connection.
-spec close(gen_tcp:socket()) -> ok.
close(Socket) ->
    ok = gen_tcp:close(Socket).

%% @doc Used to get 1 line from AMI server.
-spec read_line(
    Socket::gen_tcp:socket(), Timeout::integer()
) -> {ok, Line::string()} | {error, Reason::term()}.
read_line(Socket, Timeout) ->
    gen_tcp:recv(Socket, 0, Timeout).
