-module(erlami_app).
-behaviour(application).

-include_lib("erlami.hrl").
-include_lib("erlami_message.hrl").

%% Application callbacks
-export([start/2, start/1, stop/1, restart/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================
start(_StartType, _StartArgs) ->
    {ok, SupPid} = erlami_sup:start_link(),
    sql:start(),
    Clients = sql:sql(get,<<"clients">>,"crm_api_url,ami_server,ami_port,ami_username,ami_secret","enabled=1"),
    lists:map(fun(X) ->
      [Crm_Api_Url,Ip,Port1,Username,Secret] = X,
      Port = case Port1 of
        <<>> -> 5038;
        P -> P
      end,
      case Ip =/= <<>> andalso Username =/= <<>> andalso Secret =/= <<>> of
        true -> 
          case ets:info(processes) of
            undefined -> ets:new(processes,[set,named_table,public,{write_concurrency,false},{read_concurrency,true}]);
            _ -> ok
          end,
          A = erlami_sup:start_child(binary_to_atom(Ip,utf8), erlami_client:get_worker_name(binary_to_atom(Ip,utf8)),
              [{connection,{erlami_tcp_connection,[{host, binary_to_list(Ip)},{port,Port}]}},
              {username,binary_to_list(Username)},{secret,binary_to_list(Secret)}]),
          io:fwrite("AMI Start ~p",[A]),
          ets:insert(processes,{Ip,{z_convert:to_binary(Crm_Api_Url),A}});
        false -> ok
      end
    end,
    Clients),
  {ok, SupPid}.

start(Server) ->
   % {ok, SupPid} = erlami_sup:start_link(),
    sql:start(),
    io:fwrite("Server: ~p\n",[Server]),
    Client = sql:sql(get,<<"clients">>,"crm_api_url,ami_server,ami_port,ami_username,ami_secret","enabled!=2 and ami_server = \"" ++ z_convert:to_list(Server) ++ "\""),
    [[Crm_Api_Url,Ip,Port1,Username,Secret]] = Client,
    Port = case Port1 of
      <<>> -> 5038;
      P -> P
    end,
    case Ip =/= <<>> andalso Username =/= <<>> andalso Secret =/= <<>> of
        true -> 
          case ets:info(processes) of
            undefined -> ets:new(processes,[set,named_table,public,{write_concurrency,false},{read_concurrency,true}]);
            _ -> ok
          end,
          A = erlami_sup:start_child(binary_to_atom(Ip,utf8), erlami_client:get_worker_name(binary_to_atom(Ip,utf8)),
              [{connection,{erlami_tcp_connection,[{host, binary_to_list(Ip)},{port,Port}]}},
              {username,binary_to_list(Username)},{secret,binary_to_list(Secret)}]),
          ets:insert(processes,{Ip,{z_convert:to_binary(Crm_Api_Url),A}});
        false -> ok
    end.
%  {ok, SupPid}.

stop(Server) ->
  sql:start(),
  sql:sql(update,<<"clients">>,"enabled=0, disabled_cause=\"No AMI Connected\"","ami_server = \"" ++ z_convert:to_list(Server) ++ "\""),
  ets:delete(processes,Server),
  supervisor:terminate_child(erlami_sup,whereis(erlami_client:get_worker_name(binary_to_atom(Server,utf8)))).

restart(Server) ->
  supervisor:terminate_child(erlami_sup,whereis(erlami_client:get_worker_name(binary_to_atom(Server,utf8)))),
  start(Server).
