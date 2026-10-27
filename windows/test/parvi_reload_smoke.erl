%% Isolated native-wx integration test; never replaces a user's running UI files.
-module(parvi_reload_smoke).
-export([main/0]).

main() ->
    try exercise(), io:format("PASS: supervised UI restart, model/peer preservation, repeated reload, failed build without rollback, corrected-build recovery~n"), halt(0)
    catch Class:Reason:Stack ->
        %% Do not print saved UI state: connection fields contain credentials.
        io:format("FAIL: ~p ~p at ~p~n", [Class, safe_reason(Reason), locations(Stack)]), halt(1)
    end.

exercise() ->
    {ok, _} = parvi:start(),
    Peer = list_to_atom(os:getenv("PARVI_TEST_PEER")),
    PeerCookie = list_to_atom(os:getenv("PARVI_TEST_PEER_COOKIE")),
    erlang:set_cookie(Peer, PeerCookie),
    ok = parvi:connect(Peer),
    await(fun() -> lists:member(Peer, maps:get(chat_nodes, parvi:status())) end),
    {ok, _} = parvi:send(<<"before UI reload">>),
    await(fun() -> has_text(erpc:call(Peer, parvi, history, []), <<"before UI reload">>) end),
    Worker = whereis(parvi_chat), Pg = whereis(parvi_pg), Cookie = erlang:get_cookie(),
    Node = node(), History = parvi:history(),
    Seed = #{draft => "Unsent draft - survives reload", position => {90, 90},
             size => {940, 680}, dialog => true, url => "http://127.0.0.1:8765",
             connection => binary_to_list(parvi_connection:format(atom_to_binary(Peer), atom_to_binary(PeerCookie)))},
    {Host, Monitor} = spawn_monitor(fun() -> parvi_windows_host:run(Seed) end),
    await(fun() -> whereis(parvi_windows_host) =/= undefined end),
    #{pid := First} = parvi_windows_host:status(),
    await(fun() -> node_state(Peer) =:= running end),
    await(fun() -> topology_edge(Node, Peer) end),
    Other = list_to_atom(os:getenv("PARVI_TEST_OTHER")),
    await(fun() -> topology_edge(Peer, Other) end),
    true = lists:keymember(atom_to_binary(Other), 1, maps:get(nodes, parvi_topology:snapshot())),
    [_, ViewState, parvi_windows, _] = sys:get_state(First),
    FirstGraph = maps:get(pid, maps:get(graph, ViewState)),
    true = is_process_alive(FirstGraph),
    ok = erpc:call(Peer, sys, suspend, [parvi_chat]),
    try
        await(fun() -> node_state(Peer) =:= unresponsive end),
        true = lists:member(Peer, nodes())
    after erpc:call(Peer, sys, resume, [parvi_chat]) end,
    await(fun() -> node_state(Peer) =:= running end),
    timer:sleep(200),
    Baseline = parvi_windows_model:get(),
    true = maps:get(draft, Baseline) =:= maps:get(draft, Seed),
    Path = code:which(parvi_windows),
    {ok, Original} = file:read_file(Path),
    {ok, Source} = file:read_file(os:getenv("PARVI_TEST_UI_SOURCE")),
    %% Invalid files must leave the original window and node untouched.
    ok = file:write_file(Path, <<"partial compiler output">>),
    timer:sleep(1100),
    #{pid := First, generation := 0} = parvi_windows_host:status(),
    %% An actual BEAM change must automatically replace the wx process.
    Good = build(binary:replace(Source, <<"Swarm chat">>, <<"Swarm chat - reloaded">>), Path),
    ok = file:write_file(Path, Good),
    Second = await_generation(1),
    true = First =/= Second,
    false = is_process_alive(FirstGraph),
    check_state(Second, Baseline),
    true = Worker =:= whereis(parvi_chat), true = Pg =:= whereis(parvi_pg),
    true = Cookie =:= erlang:get_cookie(), true = Node =:= node(),
    true = History =:= parvi:history(), true = lists:member(Peer, nodes()),
    {ok, _} = parvi:send(<<"after UI reload">>),
    await(fun() -> has_text(erpc:call(Peer, parvi, history, []), <<"after UI reload">>) end),
    %% A second change catches references that accidentally pin the first version.
    ok = file:write_file(Path, Original),
    Third = await_generation(2),
    true = Third =/= Second,
    check_state(Third, Baseline),
    %% Broken new code stays failed. The backend and model remain available.
    Broken = build(binary:replace(Source, <<"build_window(Saved) ->">>,
        <<"build_window(Saved) when map_size(Saved) >= 0 -> erlang:error(reload_test_failure);\nbuild_window(Saved) ->">>), Path),
    ok = file:write_file(Path, Broken),
    await(fun() -> maps:get(last_error, parvi_windows_host:status()) =:= ui_start_failed end),
    #{pid := undefined, generation := 2} = parvi_windows_host:status(),
    false = is_process_alive(Third),
    check_state(undefined, Baseline),
    true = Worker =:= whereis(parvi_chat), true = lists:member(Peer, nodes()),
    {ok, _} = parvi:send(<<"while UI is broken">>),
    await(fun() -> has_text(erpc:call(Peer, parvi, history, []), <<"while UI is broken">>) end),
    %% A corrected build starts a fresh window from the live model.
    ok = file:write_file(Path, Good),
    _ = await_generation(3),
    #{pid := BeforeCrash} = parvi_windows_host:status(),
    exit(BeforeCrash, kill),
    Final = await_generation(4),
    true = Final =/= BeforeCrash,
    check_state(Final, Baseline),
    true = Worker =:= whereis(parvi_chat),
    %% An in-flight send belongs to the model, not the disposable window.
    ok = parvi_windows_model:put(#{draft => "send survives window replacement"}),
    Tag = make_ref(),
    parvi_windows_model:request(#{method => send, text => <<"send survives window replacement">>}, send, self(), Tag),
    parvi_windows_host:reload(),
    receive {reply, Tag, send, #{<<"error">> := null}} -> ok after 3000 -> error(send_lost) end,
    await(fun() -> has_text(erpc:call(Peer, parvi, history, []), <<"send survives window replacement">>) end),
    _ = await_generation(5),
    "" = maps:get(draft, parvi_windows_model:get()),
    #{pid := Last} = parvi_windows_host:status(),
    true = erlang:disconnect_node(Peer),
    await(fun() -> node_state(Peer) =:= down end),
    false = topology_edge(Node, Peer),
    parvi_windows_host:reload(),
    _ = await_generation(6),
    down = node_state(Peer),
    ok = parvi:connect(Peer),
    await(fun() -> node_state(Peer) =:= running end),
    await(fun() -> topology_edge(Node, Peer) end),
    false = is_process_alive(Last),
    #{pid := Closing} = parvi_windows_host:status(),
    ok = wx_object:stop(Closing, normal, 5000),
    receive {'DOWN', Monitor, process, Host, normal} -> ok after 5000 -> error(host_did_not_stop) end.

build(Source, BeamPath) ->
    File = filename:join(filename:dirname(BeamPath), "parvi_windows.erl"),
    ok = file:write_file(File, Source),
    case compile:file(File, [binary, debug_info, warnings_as_errors, return_errors, return_warnings]) of
        {ok, parvi_windows, Binary, []} -> Binary;
        _ -> error(test_compilation_failed)
    end.

check_state(_, Baseline) ->
    Saved = parvi_windows_model:get(),
    Keys = [draft, position, size, maximized, dialog, url, connection],
    true = maps:with(Keys, Saved) =:= maps:with(Keys, Baseline).

await_generation(Generation) ->
    await(fun() -> maps:get(generation, parvi_windows_host:status()) =:= Generation end),
    maps:get(pid, parvi_windows_host:status()).
await(Fun) -> await(Fun, 120).
await(_, 0) -> error(test_timeout);
await(Fun, N) ->
    case Fun() of true -> ok; false -> timer:sleep(50), await(Fun, N-1) end.
has_text(Messages, Text) -> lists:any(fun(M) -> maps:get(text, M) =:= Text end, Messages).
node_state(Node) ->
    case lists:keyfind(atom_to_binary(Node), 1, parvi_node_status:rows()) of
        {_, State, _} -> State;
        false -> unknown
    end.
topology_edge(A, B) ->
    [First, Second] = lists:sort([atom_to_binary(A), atom_to_binary(B)]),
    lists:member({First, Second}, maps:get(edges, parvi_topology:snapshot())).
safe_reason(Reason) when is_atom(Reason) -> Reason;
safe_reason(_) -> assertion_failed.
locations(Stack) -> [{M,F,proplists:get_value(line, Info)} || {M,F,_,Info} <- Stack].
