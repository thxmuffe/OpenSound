%% Probe-only process distribution controller, backed by ex_webrtc/ex_sctp.
%% A 32-bit length frames OTP packets; 16 KiB SCTP messages avoid size assumptions.
-module(parvi_dist_channel).
-behaviour(gen_server).
-export([start_link/2, signal/2, stats/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-define(PC, 'Elixir.ExWebRTC.PeerConnection').
-define(SD, 'Elixir.ExWebRTC.SessionDescription').
-define(ICE, 'Elixir.ExWebRTC.ICECandidate').
-define(MAX_PACKET, 8388608).

start_link(Owner, Initiator) -> gen_server:start_link(?MODULE, {Owner, Initiator}, []).
signal(Pid, Signal) -> gen_server:cast(Pid, {signal, Signal}).
stats(Pid) -> gen_server:call(Pid, stats).
init({Owner, Initiator}) ->
    {ok, PC} = ?PC:start_link([{ice_servers, []}, {audio_codecs, []}, {video_codecs, []}]),
    self() ! start,
    {ok, #{owner => Owner, pc => PC, initiator => Initiator, channel => undefined,
        ready => false, handle => undefined, pending => [], buffer => <<>>,
        packets => queue:new(), waiter => undefined, sent => 0, received => 0,
        sent_bytes => 0, received_bytes => 0}}.

handle_call({supervisor, Sup}, _, S) -> link(Sup), {reply, ok, S};
handle_call(blackhole, _, S) -> {reply, ok, S#{blackhole => true}};
handle_call({send, Data}, _, S) -> {reply, ok, send_packet(Data, S)};
handle_call(recv, From, #{packets := Q} = S) ->
    case queue:out(Q) of
        {{value, Packet}, Rest} -> {reply, {ok, binary_to_list(Packet)}, S#{packets := Rest}};
        {empty, _} -> {noreply, S#{waiter := From}}
    end;
handle_call({activate, Handle}, _, #{packets := Q} = S) ->
    [ok = erlang:dist_ctrl_put_data(Handle, P) || P <- queue:to_list(Q)],
    erlang:dist_ctrl_get_data_notification(Handle),
    {reply, ok, S#{handle := Handle, packets := queue:new()}};
handle_call(getstat, _, #{received := R, sent := W} = S) -> {reply, {ok, R, W, 0}, S};
handle_call(stats, _, S) ->
    {reply, (maps:with([ready, sent, received, sent_bytes, received_bytes], S))#{
        native => maps:get(handle, S) =/= undefined}, S}.

handle_cast(tick, S) -> {noreply, send_packet(<<>>, S)};
handle_cast({signal, #{<<"kind">> := Kind, <<"sdp">> := SDP}}, #{pc := PC} = S) ->
    Type = case Kind of <<"offer">> -> offer; <<"answer">> -> answer end,
    ok = ?PC:set_remote_description(PC, ?SD:'__struct__'([{type, Type}, {sdp, SDP}])),
    case Type of
        offer ->
            {ok, Answer} = ?PC:create_answer(PC),
            ok = ?PC:set_local_description(PC, Answer), description(Answer, S);
        answer -> ok
    end,
    [ok = ?PC:add_ice_candidate(PC, C) || C <- maps:get(pending, S)],
    {noreply, S#{pending := []}};
handle_cast({signal, #{<<"kind">> := <<"candidate">>, <<"candidate">> := JSON}}, #{pc := PC} = S) ->
    Candidate = ?ICE:from_json(JSON),
    case ?PC:get_remote_description(PC) of
        nil -> {noreply, S#{pending := maps:get(pending, S) ++ [Candidate]}};
        _ -> ok = ?PC:add_ice_candidate(PC, Candidate), {noreply, S}
    end.

handle_info(start, #{initiator := true, pc := PC} = S) ->
    {ok, #{ref := Ref}} = ?PC:create_data_channel(PC, <<"parvi-otp-dist/v1">>),
    {ok, Offer} = ?PC:create_offer(PC),
    ok = ?PC:set_local_description(PC, Offer), description(Offer, S),
    {noreply, S#{channel := Ref}};
handle_info(start, S) -> {noreply, S};
handle_info({ex_webrtc, PC, {ice_candidate, C}}, #{pc := PC} = S) ->
    JSON = #{<<"candidate">> => maps:get(candidate, C),
        <<"sdpMid">> => default(maps:get(sdp_mid, C), <<"0">>),
        <<"sdpMLineIndex">> => default(maps:get(sdp_m_line_index, C), 0)},
    notify(S, {signal, #{kind => <<"candidate">>, candidate => JSON}}), {noreply, S};
handle_info({ex_webrtc, PC, {data_channel, #{label := <<"parvi-otp-dist/v1">>, ref := Ref}}},
        #{pc := PC} = S) -> {noreply, S#{channel := Ref}};
handle_info({ex_webrtc, PC, {data_channel_state_change, Ref, open}}, #{pc := PC, channel := Ref} = S) ->
    notify(S, ready), {noreply, S#{ready := true}};
handle_info({ex_webrtc, PC, {data_channel_state_change, Ref, closed}}, #{pc := PC, channel := Ref} = S) ->
    {stop, {shutdown, channel_closed}, S};
handle_info({ex_webrtc, PC, {connection_state_change, Status}}, #{pc := PC} = S)
        when Status =:= failed; Status =:= disconnected; Status =:= closed ->
    {stop, {shutdown, Status}, S};
handle_info({ex_webrtc, PC, {data, _, _}}, #{pc := PC, blackhole := true} = S) ->
    {noreply, S}; %% Test-only silent packet-loss injection below native distribution.
handle_info({ex_webrtc, PC, {data, Ref, Data}}, #{pc := PC, channel := Ref, buffer := Buffer} = S) ->
    true = byte_size(Buffer) + byte_size(Data) =< ?MAX_PACKET + 4,
    {noreply, receive_packets(<<Buffer/binary, Data/binary>>, S)};
handle_info(dist_data, S) -> {noreply, drain(16, S)};
handle_info(_, S) -> {noreply, S}.

terminate(_, #{pc := PC}) ->
    case is_process_alive(PC) of true -> ?PC:close(PC); false -> ok end.

description(#{type := Type, sdp := SDP}, S) ->
    notify(S, {signal, #{kind => atom_to_binary(Type), sdp => SDP}}).
notify(#{owner := Owner}, Event) -> Owner ! {channel, self(), Event}.

send_packet(Data, #{ready := true, pc := PC, channel := Ref, sent := Sent, sent_bytes := Bytes} = S)
        when byte_size(Data) =< ?MAX_PACKET ->
    {message_queue_len, N} = process_info(PC, message_queue_len),
    true = N < 1024, %% Fail closed on local overload; production backpressure is a later gate.
    send_chunks(PC, Ref, <<(byte_size(Data)):32, Data/binary>>),
    S#{sent := Sent + 1, sent_bytes := Bytes + byte_size(Data)}.
send_chunks(PC, Ref, <<Chunk:16384/binary, Rest/binary>>) ->
    ok = ?PC:send_data(PC, Ref, Chunk, binary), send_chunks(PC, Ref, Rest);
send_chunks(_, _, <<>>) -> ok;
send_chunks(PC, Ref, Rest) -> ?PC:send_data(PC, Ref, Rest, binary).

receive_packets(<<Length:32, Rest/binary>>, S) when Length > ?MAX_PACKET ->
    exit({oversized_distribution_packet, Length, byte_size(Rest), maps:get(received, S)});
receive_packets(<<Length:32, Packet:Length/binary, Rest/binary>>, S) ->
    receive_packets(Rest, deliver(Packet, S));
receive_packets(Buffer, S) -> S#{buffer := Buffer}.

deliver(Packet, #{received := Count, received_bytes := Bytes} = S) ->
    Next = S#{received := Count + 1, received_bytes := Bytes + byte_size(Packet)},
    case maps:get(handle, S) of
        undefined ->
            case maps:get(waiter, S) of
                undefined -> Next#{packets := queue:in(Packet, maps:get(packets, S))};
                From -> gen_server:reply(From, {ok, binary_to_list(Packet)}), Next#{waiter := undefined}
            end;
        Handle -> ok = erlang:dist_ctrl_put_data(Handle, Packet), Next
    end.

drain(0, S) -> self() ! dist_data, S;
drain(N, #{handle := Handle} = S) ->
    case erlang:dist_ctrl_get_data(Handle) of
        none -> erlang:dist_ctrl_get_data_notification(Handle), S;
        Data -> drain(N - 1, send_packet(iolist_to_binary(Data), S))
    end.

default(nil, Value) -> Value;
default(Value, _) -> Value.
