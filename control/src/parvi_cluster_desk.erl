%% Desk introductions only. OTP traffic stays on the WebRTC carrier.
%% Start after net_kernel; supervised by the Mac native runtime profile.
-module(parvi_cluster_desk).
-behaviour(gen_server).
-export([start_link/0, create/0, invite/1, invitation/0, join/1, status/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
create() -> gen_server:call(?MODULE, create).
invite(TTL) -> gen_server:call(?MODULE, {invite, TTL}).
invitation() -> gen_server:call(?MODULE, invitation).
join(Link) -> gen_server:call(?MODULE, {join, Link}).
status() -> gen_server:call(?MODULE, status).

init([]) ->
    process_flag(trap_exit, true),
    {ok, _} = application:ensure_all_started(parvi_transport),
    {ok, Trust} = parvi_cluster_trust:start_link(self()),
    {ok, Relay} = parvi_relay:start_link(#{owner => self(), delivery => raw}),
    {ok, #{trust => Trust, relay => Relay, cluster => undefined,
           mailbox => parvi_cluster_auth:fresh(16), sessions => #{}, event => starting,
           invitation => undefined}}.

handle_call(create, _, #{cluster := undefined} = S) ->
    {ok, Policy} = parvi_cluster_trust:create(),
    {reply, {ok, Policy}, mailbox(maps:get(<<"cluster">>, Policy), S)};
handle_call(invitation, _, S) ->
    Policy = parvi_cluster_trust:policy(),
    case {Policy, maps:get(connected, parvi_relay:status())} of
        {#{<<"cluster">> := Cluster, <<"epoch">> := Epoch}, true} ->
            Now = erlang:system_time(second),
            case maps:get(invitation, S) of
                {Cluster, Epoch, Expiry, Link} when Expiry > Now -> {reply, {ok, Link}, S};
                _ ->
                    case make_invitation(259200, S) of
                        {ok, Link} -> {reply, {ok, Link}, S#{invitation := {Cluster, Epoch, Now + 259200, Link}}};
                        Error -> {reply, Error, S}
                    end
            end;
        _ -> {reply, {error, not_ready}, S}
    end;
handle_call({invite, TTL}, _, #{cluster := Cluster} = S) when is_binary(Cluster) ->
    Reply = case maps:get(connected, parvi_relay:status()) of
        false -> {error, desk_disconnected};
        true ->
            make_invitation(TTL, S)
    end,
    {reply, Reply, S};
handle_call({join, Link}, _, #{cluster := undefined} = S) ->
    case parse_link(Link) of
        {ok, Peer, Cap, Cluster, Invitation} ->
            case maps:get(connected, parvi_relay:status()) of
                false -> {reply, {error, desk_disconnected}, S};
                true ->
                    Id = parvi_cluster_auth:fresh(16),
                    case channel(Id, Peer, Cap, {join, Invitation}, S) of
                        {ok, Next} ->
                            Open = mailbox(Cluster, Next),
                            Result = send(Peer, Cap, Id, #{<<"kind">> => <<"hello">>}, Open),
                            {reply, Result, Open};
                        {error, Reason} -> {reply, {error, Reason}, S}
                    end
            end;
        Error -> {reply, Error, S}
    end;
handle_call(status, _, S) ->
    {reply, #{desk => parvi_relay:status(), connected_nodes => nodes(),
              policy => parvi_cluster_trust:policy(), event => maps:get(event, S)}, S};
handle_call(_, _, S) -> {reply, {error, already_clustered_or_not_created}, S}.
handle_cast(_, S) -> {noreply, S}.

handle_info({relay, {delivery, From, Cap, Payload}}, #{mailbox := Cap} = S) ->
    {noreply, incoming(From, Payload, S)};
handle_info({relay, Event}, S) -> {noreply, S#{event := {desk, Event}}};
handle_info({channel, Ctrl, {signal, Signal}}, #{sessions := Sessions} = S) ->
    case route(Ctrl, Sessions) of
        [#{id := Id, peer := Peer, mailbox := Cap}] ->
            Result = send(Peer, Cap, Id, Signal, S),
            {noreply, S#{event := {signalling, Result}}};
        [] -> {noreply, S}
    end;
handle_info({trust, Ctrl, authorized, Node}, #{sessions := Sessions} = S) ->
    case route(Ctrl, Sessions) of
        [#{role := server}] -> ok = parvi_webrtc_dist:admit(Ctrl);
        [#{role := {join, _}}] ->
            Owner = self(),
            spawn(fun() -> Owner ! {native_connected, Node, net_kernel:connect_node(Node)} end);
        [] -> ok
    end,
    {noreply, S#{event := {authorized, Node}}};
handle_info({trust, _, rejected, Reason}, S) -> {noreply, S#{event := {rejected, Reason}}};
handle_info({native_connected, Node, Result}, S) -> {noreply, S#{event := {native_connected, Node, Result}}};
handle_info({'EXIT', Pid, Reason}, #{trust := Pid} = S) -> {stop, {trust_stopped, Reason}, S};
handle_info({'EXIT', Pid, Reason}, #{relay := Pid} = S) -> {stop, {relay_stopped, Reason}, S};
handle_info({'EXIT', Pid, Reason}, #{sessions := Sessions} = S) ->
    Kept = maps:filter(fun(_, #{ctrl := Ctrl}) -> Ctrl =/= Pid end, Sessions),
    {noreply, S#{sessions := Kept, event := {channel_stopped, Reason}}};
handle_info(_, S) -> {noreply, S}.

mailbox(Cluster, S) ->
    parvi_relay:open(Cluster, maps:get(mailbox, S)), S#{cluster := Cluster}.

channel(Id, Peer, Cap, Role, #{sessions := Sessions} = S) ->
    Ice = application:get_env(parvi_transport, native_ice_servers,
        [#{urls => application:get_env(parvi, direct_stun_urls, [])}]),
    {ok, Ctrl} = parvi_dist_channel:start_link(self(), Role =:= server, Ice),
    case parvi_cluster_trust:attach(Ctrl, Role) of
        ok ->
            Route = #{id => Id, ctrl => Ctrl, peer => Peer, mailbox => Cap, role => Role},
            {ok, S#{sessions := Sessions#{Id => Route}}};
        {error, Reason} -> gen_server:stop(Ctrl), {error, Reason}
    end.

incoming(From, #{<<"type">> := <<"otp_signal">>, <<"swarm">> := Cluster,
                 <<"connection">> := Id, <<"reply">> := Cap, <<"signal">> := Signal},
         #{cluster := Cluster, sessions := Sessions} = S) ->
    case maps:find(Id, Sessions) of
        {ok, #{peer := From, mailbox := Cap}} when Signal =:= #{<<"kind">> => <<"hello">>} -> S;
        {ok, #{peer := From, mailbox := Cap, ctrl := Ctrl}} ->
            parvi_dist_channel:signal(Ctrl, Signal), S;
        error when Signal =:= #{<<"kind">> => <<"hello">>} ->
            case channel(Id, From, Cap, server, S) of
                {ok, Next} -> Next;
                {error, Reason} -> S#{event := {rejected, Reason}}
            end;
        _ -> S
    end;
incoming(_, _, S) -> S.

route(Ctrl, Sessions) -> [R || R = #{ctrl := P} <- maps:values(Sessions), P =:= Ctrl].

send(Peer, Cap, Id, Signal, S) ->
    parvi_relay:send(Peer, Cap, #{<<"type">> => <<"otp_signal">>,
        <<"swarm">> => maps:get(cluster, S), <<"connection">> => Id,
        <<"reply">> => maps:get(mailbox, S), <<"signal">> => Signal}).

parse_link(Link) ->
    try
        #{scheme := <<"parvi">>, host := <<"cluster">>, path := <<"/v2">>, query := Query} =
            uri_string:parse(string:trim(Link)),
        #{<<"desk">> := URL, <<"node">> := Peer, <<"mailbox">> := Cap,
          <<"invitation">> := Invitation} = maps:from_list(uri_string:dissect_query(Query)),
        true = parvi_relay:valid_url(URL), URL = parvi_relay:url(),
        32 = byte_size(binary:decode_hex(Peer)), 16 = byte_size(binary:decode_hex(Cap)),
        {ok, #{<<"cluster">> := Cluster}} = parvi_cluster_auth:parse_invitation(Invitation),
        {ok, Peer, Cap, Cluster, Invitation}
    catch _:_ -> {error, invalid_invitation_or_different_desk} end.

terminate(_, #{trust := Trust, relay := Relay}) ->
    %% Stop the local authority too; a normal linked shutdown alone leaves it alive.
    try parvi_cluster_trust:retire() catch exit:_ -> ok end,
    [try gen_server:stop(Pid) catch exit:_ -> ok end || Pid <- [Trust, Relay]], ok.

make_invitation(TTL, S) ->
    case parvi_cluster_trust:invite(TTL) of
        {ok, Invitation} ->
            Query = uri_string:compose_query([
                {<<"desk">>, parvi_relay:url()}, {<<"node">>, parvi_relay:id()},
                {<<"mailbox">>, maps:get(mailbox, S)}, {<<"invitation">>, Invitation}]),
            {ok, <<"parvi://cluster/v2?", Query/binary>>};
        Error -> Error
    end.
