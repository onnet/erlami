%%% This is the main code for the ami client. Each one of these
%%% will monitor a particular asterisk box. These processes will be
%%% registered by the name "asterisk-listener-Name", where Name is
%%% particular id for an asterisk box given in the configuration file.
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
-module(erlami_client).
-author("Marcelo Gornstein <marcelog@gmail.com>").
-github("https://github.com/marcelog").
-homepage("http://marcelog.github.com/").
-license("Apache License 2.0").
-behaviour(gen_fsm).
-define(SERVER, ?MODULE).
-include_lib("erlami_connection.hrl").

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
-type clienteventevent() :: {event, erlami_message:event()}.
-type clientresponseevent() :: {response, erlami_message:response()}.
-type listenerfun() :: fun(
    (ServerName::atom(), Event::erlami_message:event()) -> none()
).
-type listenerpred() :: fun(() -> boolean()).
-type listener() :: {listenerfun(), listenerpred()}.
-type responsecallback() :: fun((
    Response::erlami_message:attributes(),
    Events::[erlami_message:attributes()]
) -> none()).
%% ------------------------------------------------------------------
%% Needed imports and includes.
%% ------------------------------------------------------------------
-include_lib("kernel/include/inet.hrl").
-include_lib("erlami_message.hrl").

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
-record(clientstate, {name, worker_name, serverinfo, listeners, actions, connection}).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([
    start_link/2
   ,get_worker_name/1
   ,process_salutation/2
   ,wait_salutation/2
   ,process_event/2
   ,process_response/2
   ,wait_login_response/2
   ,receiving/2
   ,register_listener/2
   ,send_action/3
   ,wait_reconnect/2
   ,send_delayed_reconnect/2
   ,move_to_reconnect/2
   ,listeners/1
]).

%% ------------------------------------------------------------------
%% gen_fsm Function Exports
%% ------------------------------------------------------------------
-export([
    init/1, handle_event/3,
    handle_sync_event/4, handle_info/3, terminate/3,
    code_change/4
]).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------
-spec start_link(
    ServerName::string(),
    ServerInfo::erlami_server_config:serverinfo()
) -> ok.
start_link(ServerName, ServerInfo) ->
    gen_fsm:start_link(
        {local, get_worker_name(ServerName)}, ?MODULE, [ServerName, ServerInfo], []
    ).

%% @doc Returns a worker name (erlagi_client) based on an asterisk server
%% name.
-spec get_worker_name(AsteriskServerName::atom()) -> atom().
get_worker_name(AsteriskServerName) ->
    list_to_atom(lists:concat([?MODULE, "_", AsteriskServerName])).

%% ------------------------------------------------------------------
%% gen_fsm Function Definitions
%% ------------------------------------------------------------------
init([ServerName, ServerInfo]) ->
    {ConnModule, ConnOptions} = erlami_server_config:extract_connection(ServerInfo),

    try erlang:apply(ConnModule, open, [ConnOptions]) of
        {ok, Conn} ->
            _Reader = erlami_reader:start_link(get_worker_name(ServerName), Conn),
            lager:info("connected: ~p", [ServerName]),
            {ok
            ,wait_salutation
            ,#clientstate{name=ServerName
                         ,serverinfo=ServerInfo
                         ,listeners=[]
                         ,actions=[]
                         ,connection=Conn
            }};
        R ->
            lager:info("failed attempt to init erlami_client: ~p error: ~p", [ServerName, R]),
            spawn('erlami_client', 'send_delayed_reconnect', [get_worker_name(ServerName), 10000]),
            {ok
            ,wait_reconnect
            ,#clientstate{name=ServerName
                         ,serverinfo=ServerInfo
            }}
    catch
        E ->
            lager:info("failed attempt to init erlami_client: ~p error: ~p", [ServerName, E]),
            spawn('erlami_client', 'send_delayed_reconnect', [get_worker_name(ServerName), 10000]),
            {ok
            ,wait_reconnect
            ,#clientstate{name=ServerName
                         ,serverinfo=ServerInfo
            }}
    end.

handle_event(
    {register, ListenerDescriptor}, StateName, #clientstate{
        name=Name, serverinfo=ServerInfo,
        listeners=Listeners, actions=Actions, connection=Conn
    }) ->
    {next_state, StateName, #clientstate{
        name=Name, serverinfo=ServerInfo,
        listeners=[ListenerDescriptor|Listeners], actions=Actions,
        connection=Conn
    }};

handle_event(_Event, StateName, State) ->
    lager:info("inside handle_event StateName: ~p", [StateName]),
    {next_state, StateName, State}.

handle_sync_event(_Event, _From, StateName, State) ->
    {reply, ok, StateName, State}.

handle_info(_Info, StateName, State) ->
    lager:info("inside handle_info StateName: ~p", [StateName]),
    {next_state, StateName, State}.

terminate(_Reason, _StateName, _State) ->
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%% ------------------------------------------------------------------
%% API.
%% ------------------------------------------------------------------

%% @doc Called by the erlagi_reader when the salutation has been received.
process_salutation(ErlamiClient, {salutation, Salutation}) ->
    gen_fsm:send_event(ErlamiClient, {salutation, Salutation}).

%% @doc Called by the erlagi_reader when a response has been received.
process_response(ErlamiClient, {response, Response}) ->
    gen_fsm:send_event(ErlamiClient, {response, Response}).

%% @doc Called by the erlagi_reader when an event has been received.
process_event(ErlamiClient, {event, Event}) ->
    gen_fsm:send_event(ErlamiClient, {event, Event}).

%% @doc Called to register a listener for an event.
-spec register_listener(
    ErlamiClient::atom(), ListenerDescriptor::listener()
) -> none().
register_listener(ErlamiClient, ListenerDescriptor) ->
    gen_fsm:send_all_state_event(
        get_worker_name(ErlamiClient), {register, ListenerDescriptor}
    ).

%% @doc Sends an action to the given asterisk server name.
-spec send_action(
    ErlamiClient::atom(), Action::erlami_message:action(),
    Callback::responsecallback()
) -> none().
send_action(ErlamiClient, Action, Callback) ->
    gen_fsm:send_event(
        get_worker_name(ErlamiClient), {action, Action, Callback}
    ).

send_delayed_reconnect(ErlamiClient, Timeout) ->
    timer:sleep(Timeout),
    gen_fsm:send_event(ErlamiClient, {reconnect, "try reconnect"}).

move_to_reconnect(ErlamiClient, Reason) ->
    gen_fsm:send_event(ErlamiClient, {go_reconnect, Reason}).

-spec listeners(ErlamiClient::atom()) -> none().
listeners(ErlamiClient) ->
    case sys:get_state(get_worker_name(ErlamiClient)) of
        {'receiving', #clientstate{listeners=Listeners}} ->
            {'ok', Listeners};
        _E ->
            {'wrong_state', _E}
    end.

%% ------------------------------------------------------------------
%% States.
%% ------------------------------------------------------------------

%% @doc After the connection has been established to asterisk, we need to wait
%% for the asterisk salutation, which is the first line received.
wait_salutation(
    {salutation, Salutation},
    #clientstate{
        serverinfo=ServerInfo, connection=#erlami_connection{}=Conn
    }=State
) ->
    lager:info("Got Salutation: ~p", [Salutation]),
    ok = validate_salutation(Salutation),
    Username = erlami_server_config:extract_username(ServerInfo),
    Secret = erlami_server_config:extract_secret(ServerInfo),
    Action = erlami_message:new_action(
        "login", [{"username", Username}, {"secret", Secret}, {"events","on"}]
    ),
    Fun = Conn#erlami_connection.send,
    ok = Fun(Action),
    {next_state, wait_login_response, State};
wait_salutation({go_reconnect, Reason} ,#clientstate{name=ServerName}=State) ->
    lager:info("moving from wait_salutation to reconnect state for: ~p Reason: ~p"
              ,[get_worker_name(ServerName), Reason]),
    spawn('erlami_client', 'send_delayed_reconnect', [get_worker_name(ServerName), 10000]),
    {next_state, wait_reconnect, State}.

wait_reconnect(
    {reconnect, Reconnect}
    ,#clientstate{name=ServerName
                 ,serverinfo=ServerInfo
                 ,connection=OldConn
                 }=State
) ->
    lager:info("Got Reconnect: ~p", [Reconnect]),
    case OldConn of
        #erlami_connection{} ->
            Fun = OldConn#erlami_connection.close,
            Fun();
        _Zero ->
            lager:info("No OldConn found: ~p", [OldConn])
    end,
    {ConnModule, ConnOptions} = erlami_server_config:extract_connection(ServerInfo),
    try erlang:apply(ConnModule, open, [ConnOptions]) of
        {ok, Conn} ->
            _Reader = erlami_reader:start_link(get_worker_name(ServerName), Conn),
            lager:info("reconnected: ~p", [ServerName]),
            {next_state
            ,wait_salutation
            ,#clientstate{name=ServerName
                         ,serverinfo=ServerInfo
                         ,listeners=[]
                         ,actions=[]
                         ,connection=Conn
            }};
        R ->
            lager:info("failed attempt to reconnect erlami_client: ~p, error: ~p ", [ServerName, R]),
            spawn('erlami_client', 'send_delayed_reconnect', [get_worker_name(ServerName), 10000]),
            {next_state, wait_reconnect, State}
    catch
        E ->
            lager:info("failed attempt to reconnect erlami_client: ~p, error: ~p ", [ServerName, E]),
            spawn('erlami_client', 'send_delayed_reconnect', [get_worker_name(ServerName), 10000]),
            {next_state, wait_reconnect, State}
    end;
wait_reconnect({action, _Action, _Callback}, State) ->
    lager:info("wait_reconnect state. No action for ~p possible", [State#clientstate.name]),
    {next_state, wait_reconnect, State};
wait_reconnect({go_reconnect, _} = Tuple, #clientstate{name=ServerName}=State) ->
    lager:info("~p received ~p, but already in wait_reconnect state", [ServerName, Tuple]),
    {next_state, wait_reconnect, State};
wait_reconnect(A, State) ->
    lager:info("wait_reconnect(A, State) A: ~p", [A]),
    lager:info("wait_reconnect(A, State) State: ~p", [State]),
    {next_state, wait_reconnect, State}.

%% @doc After sending the login action, we need to receive the
%% response/result.
wait_login_response({response, Response}, #clientstate{name=ServerName}=State) ->
    case erlami_message:is_response_success(Response) of
        false ->
            lager:error("Cant login to ~p: ~p", [ServerName, erlami_message:get(Response, "message")]),
    %        erlang:error(cantlogin);
            spawn('erlami_client', 'send_delayed_reconnect', [get_worker_name(ServerName), 10000]),
            {next_state, wait_reconnect, State};
        true -> {next_state, receiving, State}
    end.

%% @doc The principal state for this fsm is the receiving event, meaning that
%% it is connected to asterisk and receiving events, and able to send actions
%% and receive responses.
-spec receiving(
    clienteventevent()|clientresponseevent(), State
) -> {next_state, receiving, State}.
receiving({go_reconnect, Reason} ,#clientstate{name=ServerName}=State) ->
    lager:info("moving from receiving to reconnect state for: ~p Reason: ~p"
              ,[get_worker_name(ServerName), Reason]),
    spawn('erlami_client', 'send_delayed_reconnect', [get_worker_name(ServerName), 10000]),
    {next_state, wait_reconnect, State};

receiving({response, Response}, #clientstate{
    name=Name, serverinfo=ServerInfo, connection=Conn,
    actions=Actions, listeners=Listeners
} = State) ->
    % Find the correct action information for this response
%    lager:info("response state Actions: ~p ~p", [Actions,Response]),
    ActionId = case erlami_message:get(Response, "actionid") of
        {ok, ActionId1} -> ActionId1;
        _ -> notfound
    end,
%    lager:info("response ActionId: ~p", [ActionId]),
    case lists:keyfind(ActionId, 1, Actions) of
        {ActionId, {Action, none, Events, Callback}} ->
            % See if we should dispatch this right away or wait for the events needed
            % to complete the response.
            NewActions = case erlami_message:is_response_complete(Response) of
                true ->
                    % Complete response. Dispatch and remove the action from the queue.
                    Callback(Response, Events),
                    lists:keydelete(ActionId, 1, Actions);
                false ->
                    % Save the response so we can receive the associated events to
                    % dispatch later.
                    lists:keystore(
                        ActionId, 1, Actions,
                        {ActionId, {Action, Response, [], Callback}}
                    )
            end,
            NewState = #clientstate{
                name=Name,
                serverinfo=ServerInfo, connection=Conn,
                actions=NewActions, listeners=Listeners
            },
            {next_state, receiving, NewState};
        'false' ->
            % ignore: not ours, or stale.
            lager:info("ActionId ~p not recognised. Skipping", [ActionId]),
            {next_state, receiving, State}
    end;

receiving({event, Event}, #clientstate{
    name=Name, serverinfo=ServerInfo, connection=Conn,
    actions=Actions, listeners=Listeners
} = State) ->
    case erlami_message:get(Event, "actionid") of
        notfound ->
            % async event
            dispatch_event(Name, Event, Listeners),
            {next_state, receiving, State};
        {ok, ActionId} ->
            % this one belongs to a response
            case lists:keyfind(ActionId, 1, Actions) of
                false ->
                    % ignore: not ours, or stale.
                    {next_state, receiving, State};
                {ActionId, {Action, Response, Events, Callback}} ->
                    NewEvents = [Event|Events],
                    NewActions = case erlami_message:is_event_last_for_response(
                        Event
                    ) of
                        false ->
                            lists:keystore(
                                ActionId, 1, Actions,
                                {ActionId,
                                    {Action, Response, NewEvents, Callback}
                                }
                            );
                        true ->
                            Callback(Response, NewEvents),
                            lists:keydelete(ActionId, 1, Actions)
                    end,
                    NewState = #clientstate{
                        name=Name,
                        serverinfo=ServerInfo, connection=Conn,
                        actions=NewActions, listeners=Listeners
                    },
                    {next_state, receiving, NewState}
            end
    end;

receiving({action, Action, Callback}, #clientstate{
    name=Name, serverinfo=ServerInfo, connection=#erlami_connection{}=Conn,
    actions=Actions, listeners=Listeners
}) ->
    {ok, ActionId} = erlami_message:get(Action, "actionid"),
    NewState = #clientstate{
        name=Name,
        serverinfo=ServerInfo, connection=Conn,
        actions=lists:keystore(
            ActionId, 1, Actions, {ActionId, {Action, none, [], Callback}}
        ),
        listeners=Listeners
    },
    Fun = Conn#erlami_connection.send,
  %  lager:info("receiving action 1 Action: ~p", [Action]),
    ok = Fun(Action),
  %  lager:info("receiving action 2"),
    {next_state, receiving, NewState}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% @doc Validates an asterisk salutation by pattern matching.
-spec validate_salutation(Host::string()) -> ok | unknown_salutation.
validate_salutation(Salutation) ->
    case list_to_binary(Salutation) of
        <<"Asterisk Call Manager", _/binary>> ->
            lager:info("salutation: ~p", [Salutation]),
            ok;
        _ ->
            lager:info("invalid salutation: ~p", [Salutation]),
            unknown_salutation
    end.

%% @doc Dispatches an event to the interested listeners, will also run the
%% predicates before dispatching.
-spec dispatch_event(
    ServerName::string(), Event::erlami_message:event(),
    Listeners::[listener()]
) -> none().
dispatch_event(ServerName, Event, Listeners) ->
    lists:foreach(
        fun({Function, Predicate}) ->
            spawn(fun() ->
                case erlang:apply(Predicate, [Event]) of
                    true ->
                        Function(ServerName, Event);
                    _ -> ok
                end
            end)
        end,
        Listeners
    ).
