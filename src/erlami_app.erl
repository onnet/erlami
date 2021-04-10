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
    {ok,Filelist} = file:list_dir("/etc/crm_conductor/"),
    lists:map(fun(X) ->
      Filename = <<"/etc/crm_conductor/", (z_convert:to_binary(X))/binary>>,
      {ok,File} = file:read_file(binary:bin_to_list(Filename)),
      Data = jiffy:decode(File),
      Ip = crm_utils:get_value([z_convert:to_binary(X),<<"ami_server">>],Data),
      Port = case crm_utils:get_value([z_convert:to_binary(X),<<"ami_port">>],Data) of
        <<>> -> 5038;
        Port1 -> Port1
      end,
      Username = crm_utils:get_value([z_convert:to_binary(X),<<"ami_username">>],Data),
      Secret = crm_utils:get_value([z_convert:to_binary(X),<<"ami_secret">>],Data),
      Enabled = crm_utils:get_value([z_convert:to_binary(X),<<"enabled">>],Data),
      case Enabled == 1 andalso Ip =/= <<>> andalso Username =/= <<>> andalso Secret =/= <<>> of
        true -> 
          erlami_sup:start_child(binary_to_atom(Ip,utf8), erlami_client:get_worker_name(binary_to_atom(Ip,utf8)),
                     [{connection,{erlami_tcp_connection,[{host, binary_to_list(Ip)},{port,Port}]}},{enabled,Enabled},
                     {username,binary_to_list(Username)},{secret,binary_to_list(Secret)}]);
        false -> ok
      end
  end, Filelist),
  {ok, SupPid}.

start(Server) ->
      Filename = <<"/etc/crm_conductor/", Server/binary>>,
      {ok,File} = file:read_file(binary:bin_to_list(Filename)),
      Data = jiffy:decode(File),
      Ip = crm_utils:get_value([Server,<<"ami_server">>],Data),
      Port = case crm_utils:get_value([Server,<<"ami_port">>],Data) of
        <<>> -> 5038;
        Port1 -> Port1
      end,
      Username = crm_utils:get_value([Server,<<"ami_username">>],Data),
      Secret = crm_utils:get_value([Server,<<"ami_secret">>],Data),
      Enabled = crm_utils:get_value([Server,<<"enabled">>],Data),
      case Enabled == 1 andalso Ip =/= <<>> andalso Username =/= <<>> andalso Secret =/= <<>> of
        true -> 
          erlami_sup:start_child(binary_to_atom(Ip,utf8), erlami_client:get_worker_name(binary_to_atom(Ip,utf8)),
                     [{connection,{erlami_tcp_connection,[{host, binary_to_list(Ip)},{port,Port}]}},{enabled,Enabled},
                     {username,binary_to_list(Username)},{secret,binary_to_list(Secret)}]);
        false -> ok
      end.

stop(Server) ->
  supervisor:terminate_child(erlami_sup,whereis(erlami_client:get_worker_name(binary_to_atom(Server,utf8)))).

restart(Server) ->
  supervisor:terminate_child(erlami_sup,whereis(erlami_client:get_worker_name(binary_to_atom(Server,utf8)))),
  {ok,Filelist} = file:list_dir("/etc/crm_conductor/"),
    lists:map(fun(X) ->
      Filename = <<"/etc/crm_conductor/", (z_convert:to_binary(X))/binary>>,
      {ok,File} = file:read_file(binary:bin_to_list(Filename)),
      Data = jiffy:decode(File),
      Ip = crm_utils:get_value([z_convert:to_binary(X),<<"ami_server">>],Data),
      Port = case crm_utils:get_value([z_convert:to_binary(X),<<"ami_port">>],Data) of
        <<>> -> 5038;
        Port1 -> Port1
      end,
      Username = crm_utils:get_value([z_convert:to_binary(X),<<"ami_username">>],Data),
      Secret = crm_utils:get_value([z_convert:to_binary(X),<<"ami_secret">>],Data),
      Enabled = crm_utils:get_value([z_convert:to_binary(X),<<"enabled">>],Data),
      case Enabled == 1 andalso Ip == Server andalso Username =/= <<>> andalso Secret =/= <<>> of
        true -> 
          erlami_sup:start_child(binary_to_atom(Ip,utf8), erlami_client:get_worker_name(binary_to_atom(Ip,utf8)),
                     [{connection, {erlami_tcp_connection, [{host, binary_to_list(Ip)}, {port, Port}]}},{enabled, Enabled},
                     {username, binary_to_list(Username)},{secret, binary_to_list(Secret)}]);
        false -> ok
      end
  end, Filelist).
