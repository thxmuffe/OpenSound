%% Runs inside the iPhone BEAM, sharing the actual OTP app and JSON handler.
-module(parvi_ios).
-export([main/0, probe/0]).
main() ->
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
    ok = parvi_swarms:send(SwarmId, <<"On-device Erlang self-test passed.">>),
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
