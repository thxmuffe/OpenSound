%% Runs inside the iPhone BEAM, sharing the actual OTP app and JSON handler.
-module(parvi_ios).
-export([main/0, probe/0, resolve_host/1]).
main() ->
    %% iOS cannot spawn inet_gethost. Resolve through the statically linked
    %% prim_net NIF, then let Gun look up the original hostname in this VM.
    ok = inet_db:set_lookup([file]),
    application:set_env(parvi, relay_resolver, {?MODULE, resolve_host}),
    CA = filename:join(code:root_dir(), "cacerts.pem"),
    case filelib:is_file(CA) of true -> application:set_env(parvi, relay_cacertfile, CA); false -> ok end,
    {ok, _} = application:ensure_all_started(parvi),
    Proof = probe(),
    case os:getenv("PARVI_PROOF_PATH") of
        false -> ok;
        Path -> ok = file:write_file(Path, json:encode(Proof))
    end,
    Port = list_to_integer(os:getenv("PARVI_BRIDGE_PORT")),
    {ok, Socket} = gen_tcp:connect({127,0,0,1}, Port,
                                  [binary, {packet, line}, {packet_size, 8192}, {active, false}], 10000),
    serve(Socket).

resolve_host(Host) ->
    case net:getaddrinfo(binary_to_list(Host)) of
        {ok, Addresses} ->
            IPv4 = lists:usort([IP || #{family := inet, addr := #{addr := IP}} <- Addresses]),
            IPv6 = lists:usort([IP || #{family := inet6, addr := #{addr := IP}} <- Addresses]),
            case {IPv4, IPv6} of
                {[], []} -> {error, nxdomain};
                _ ->
                    ok = inet_db:clear_hosts(),
                    [ok = inet_db:add_host(IP, [binary_to_list(Host)]) || IP <- IPv4 ++ IPv6],
                    {ok, case IPv4 of [] -> inet6; _ -> inet end}
            end;
        Error -> Error
    end.

serve(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Request} ->
            ok = gen_tcp:send(Socket, [parvi_bridge:request(Request), $\n]),
            serve(Socket);
        {error, _} ->
            %% Do not call init:stop: the VM shares the native app process.
            gen_tcp:close(Socket),
            ok
    end.

%% Initial runtime feasibility check, completed before the UI connects.
%% The test messages pass through the same gen_server used by both apps.
probe() ->
    Before = whereis(parvi_chat),
    {ok, Sent} = parvi:send(<<"On-device runtime self-test">>),
    true = lists:member(Sent, parvi:history()),
    Ref = monitor(process, Before),
    exit(Before, kill),
    receive {'DOWN', Ref, process, Before, _} -> ok after 2000 -> error(worker_did_not_stop) end,
    After = await_worker(Before, 100),
    [] = parvi:history(),
    {ok, _} = parvi:send(<<"On-device Erlang self-test passed.">>),
    [#{id := SwarmId} | _] = parvi_swarms:snapshot(),
    case parvi_relay:enabled() of
        false -> ok = parvi_swarms:send(SwarmId, <<"On-device Erlang self-test passed.">>);
        true -> ok %% Runtime proof must not depend on external desk availability.
    end,
    #{status => <<"passed">>, otp => list_to_binary(erlang:system_info(otp_release)),
      erts => list_to_binary(erlang:system_info(version)),
      os_pid => list_to_binary(os:getpid()),
      worker_before => list_to_binary(pid_to_list(Before)),
      worker_after => list_to_binary(pid_to_list(After)),
      message_verified => true, supervisor_restart_verified => true}.

await_worker(_Before, 0) -> error(worker_restart_timeout);
await_worker(Before, Attempts) ->
    case {whereis(parvi_chat), whereis(parvi_discovery), whereis(parvi_swarms)} of
        {Pid, Discovery, Swarms} when is_pid(Pid), is_pid(Discovery), is_pid(Swarms), Pid =/= Before -> Pid;
        _ -> timer:sleep(20), await_worker(Before, Attempts - 1)
    end.
