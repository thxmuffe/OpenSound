%% Outbound, authenticated WebSocket transport. No distribution ports required.
-module(parvi_relay).
-behaviour(gen_server).
-export([start_link/0, id/0, enabled/0, url/0, valid_url/1, open/2, close/1, send/3, watch/1, status/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
id() -> persistent_term:get({?MODULE, id}, node()).
enabled() -> is_binary(id()).
url() -> persistent_term:get({?MODULE, url}, undefined).
open(Swarm, Cap) -> gen_server:cast(?MODULE, {open, Swarm, Cap}).
close(Cap) -> gen_server:cast(?MODULE, {close, Cap}).
watch(Nodes) -> gen_server:cast(?MODULE, {watch, Nodes}).
send(To, Cap, Payload) -> gen_server:call(?MODULE, {send, To, Cap, Payload}, 2000).
status() -> gen_server:call(?MODULE, status).
valid_url(URL) when is_binary(URL), byte_size(URL) =< 512 ->
    try
        #{scheme := Scheme, host := Host} = Map = uri_string:parse(URL),
        true = byte_size(Host) > 0,
        false = maps:is_key(userinfo, Map) orelse maps:is_key(fragment, Map) orelse maps:is_key(query, Map),
        true = Scheme =:= <<"wss">> orelse
               (Scheme =:= <<"ws">> andalso lists:member(Host, [<<"127.0.0.1">>, <<"localhost">>, <<"::1">>])),
        true = maps:get(path, Map, <<>>) =:= <<"/relay/v1">>,
        true = maps:get(port, Map, 443) > 0 andalso maps:get(port, Map, 443) < 65536,
        true
    catch _:_ -> false end;
valid_url(_) -> false.
init([]) ->
    URL = case application:get_env(parvi, reception_desk_url) of
        {ok, U} -> U;
        undefined -> case os:getenv("PARVI_RECEPTION_DESK_URL") of false -> undefined; V -> list_to_binary(V) end
    end,
    {Identity, Private} = case URL of
        undefined -> {node(), undefined};
        _ -> true = valid_url(URL), {Pub, Priv} = crypto:generate_key(eddsa, ed25519), {binary:encode_hex(Pub), Priv}
    end,
    persistent_term:put({?MODULE, id}, Identity), persistent_term:put({?MODULE, url}, URL),
    case URL of undefined -> ok; _ -> self() ! connect end,
    {ok, #{url => URL, private => Private, conn => undefined, stream => undefined,
           ready => false, boxes => #{}, watch => [], online => [], backoff => 500, error => null}}.
handle_call(status, _, S) ->
    {reply, #{id => name(id()), url => case url() of undefined -> null; U -> U end,
              connected => maps:get(ready, S), online => maps:get(online, S), watched => maps:get(watch, S), error => maps:get(error, S)}, S};
handle_call({send, To, Cap, Payload}, _, #{ready := true} = S) ->
    Frame = #{op => <<"send">>, to => To, mailbox => Cap, payload => Payload,
              request => maps:get(<<"request">>, Payload, null)},
    {reply, ws(Frame, S), S};
handle_call({send, _, _, _}, _, S) -> {reply, {error, disconnected}, S}.
handle_cast({open, Swarm, Cap}, #{boxes := Boxes} = S) ->
    Next = S#{boxes := Boxes#{Cap => Swarm}}, maybe_ws(#{op => <<"open">>, swarm => Swarm, mailbox => Cap}, Next), {noreply, Next};
handle_cast({close, Cap}, #{boxes := Boxes} = S) ->
    maybe_ws(#{op => <<"close">>, mailbox => Cap}, S), {noreply, S#{boxes := maps:remove(Cap, Boxes)}};
handle_cast({watch, Nodes}, S) ->
    Next = S#{watch := lists:sublist(lists:usort([N || N <- Nodes, is_binary(N)]), 256)},
    maybe_ws(#{op => <<"watch">>, nodes => maps:get(watch, Next)}, Next), {noreply, Next};
handle_cast(_, S) -> {noreply, S}.
handle_info(connect, #{conn := undefined, url := URL} = S) when is_binary(URL) ->
    #{scheme := Scheme, host := Host} = U = uri_string:parse(URL),
    TLS = Scheme =:= <<"wss">>, Port = maps:get(port, U, case TLS of true -> 443; false -> 80 end),
    try
        Opts = #{protocols => [http], retry => 0, connect_timeout => 5000,
                 domain_lookup_timeout => 5000, tls_handshake_timeout => 5000,
                 transport => case TLS of true -> tls; false -> tcp end},
        Options = case TLS of true -> Opts#{tls_opts => tls_options()}; false -> Opts end,
        {ok, Pid} = gun:open(binary_to_list(Host), Port, Options),
        monitor(process, Pid),
        erlang:send_after(10000, self(), {handshake_timeout, Pid}),
        {noreply, S#{conn := Pid}}
    catch _:_ -> {noreply, retry(S)} end;
handle_info({gun_up, Pid, http}, #{conn := Pid} = S) ->
    Stream = gun:ws_upgrade(Pid, "/relay/v1", [],
        #{silence_pings => false, max_frame_size => 131072, compress => false}),
    {noreply, S#{stream := Stream}};
handle_info({gun_upgrade, Pid, Stream, [<<"websocket">>], _}, #{conn := Pid, stream := Stream} = S) -> {noreply, S};
handle_info({gun_ws, Pid, Stream, {text, Text}}, #{conn := Pid, stream := Stream} = S) when byte_size(Text) =< 131072 ->
    try {noreply, incoming(json:decode(Text), S)} catch _:_ -> {noreply, retry(S)} end;
handle_info({gun_ws, Pid, Stream, {ping, Data}}, #{conn := Pid, stream := Stream} = S) ->
    gun:ws_send(Pid, Stream, {pong, Data}), {noreply, S};
handle_info({gun_down, Pid, _, _, _}, #{conn := Pid} = S) -> {noreply, retry(S)};
handle_info({'DOWN', _, process, Pid, _}, #{conn := Pid} = S) -> {noreply, retry(S)};
handle_info({handshake_timeout, Pid}, #{conn := Pid, ready := false} = S) -> {noreply, retry(S)};
handle_info({gun_error, Pid, _, _}, #{conn := Pid} = S) -> {noreply, retry(S)};
handle_info({gun_error, Pid, _}, #{conn := Pid} = S) -> {noreply, retry(S)};
handle_info({gun_response, Pid, _, _, _, _}, #{conn := Pid} = S) -> {noreply, retry(S)};
handle_info(_, S) -> {noreply, S}.
incoming(#{<<"op">> := <<"challenge">>, <<"v">> := 1, <<"nonce">> := Nonce}, S)
        when is_binary(Nonce), byte_size(Nonce) =:= 64 ->
    Sig = crypto:sign(eddsa, none, <<"parvi-desk/v1:", Nonce/binary>>, [maps:get(private, S), ed25519]),
    ok = ws(#{op => <<"hello">>, v => 1, id => id(), signature => binary:encode_hex(Sig)}, S), S;
incoming(#{<<"op">> := <<"ready">>, <<"v">> := 1, <<"id">> := Id}, S) ->
    Id = id(), Next = S#{ready := true, backoff := 500, error := null},
    [ws(#{op => <<"open">>, swarm => Swarm, mailbox => Cap}, Next) || {Cap, Swarm} <- maps:to_list(maps:get(boxes, S))],
    ws(#{op => <<"watch">>, nodes => maps:get(watch, S)}, Next),
    notify(connected), Next;
incoming(#{<<"op">> := <<"delivery">>, <<"from">> := From, <<"mailbox">> := Cap, <<"payload">> := Payload}, #{boxes := Boxes} = S) ->
    case maps:find(Cap, Boxes) of
        {ok, Swarm} ->
            case parvi_swarm_wire:decode(Payload) of
                {ok, Swarm, Event} -> notify({delivery, From, Event});
                _ -> ok
            end;
        _ -> ok
    end, S;
incoming(#{<<"op">> := <<"presence">>, <<"online">> := Online}, S) when is_list(Online), length(Online) =< 256 -> S#{online := Online};
incoming(#{<<"op">> := <<"error">>, <<"request">> := Request, <<"error">> := Error}, S) ->
    notify({error, Request, Error}), S#{error := Error};
incoming(_, S) -> S.
retry(#{conn := Pid, backoff := Delay} = S) ->
    case Pid of undefined -> ok; _ -> try gun:close(Pid) catch _:_ -> ok end end,
    erlang:send_after(Delay + rand:uniform(250), self(), connect), notify(disconnected),
    S#{conn := undefined, stream := undefined, ready := false, online := [],
       error := <<"Connection failed. Check the desk URL and TLS trust.">>, backoff := min(10000, Delay * 2)}.
maybe_ws(Msg, #{ready := true} = S) -> ws(Msg, S);
maybe_ws(_, _) -> ok.
ws(Msg, #{conn := Pid, stream := Stream}) ->
    Data = iolist_to_binary(json:encode(Msg)),
    case byte_size(Data) =< 131072 of
        true ->
            case process_info(Pid, message_queue_len) of
                {message_queue_len, N} when N < 256 -> gun:ws_send(Pid, Stream, {text, Data});
                _ -> {error, overloaded}
            end;
        false -> {error, too_large}
    end.
notify(Event) -> case whereis(parvi_swarms) of undefined -> ok; Pid -> Pid ! {relay, Event} end.
name(N) when is_atom(N) -> atom_to_binary(N);
name(N) -> N.
tls_options() ->
    Setting = case os:getenv("PARVI_RELAY_CA_FILE") of
        false -> application:get_env(parvi, relay_cacertfile);
        Path0 -> {ok, Path0}
    end,
    CA = case Setting of
        {ok, Path} -> [{cacertfile, Path}];
        undefined -> [{cacerts, public_key:cacerts_get()}]
    end,
    [{verify, verify_peer}, {depth, 10},
     {customize_hostname_check, [{match_fun, public_key:pkix_verify_hostname_match_fun(https)}]} | CA].
terminate(_, #{conn := Pid}) -> case Pid of undefined -> ok; _ -> try gun:close(Pid) catch _:_ -> ok end end, ok.
