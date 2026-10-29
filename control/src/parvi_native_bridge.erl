%% Mac JSON boundary for one native trust domain. No swarm routing or liveness worker.
-module(parvi_native_bridge).
-export([request/1]).

request(JSON) ->
    Reply = try
        Request = json:decode(JSON),
        Result = command(Request),
        Response = case Result of
            {ok, Data} -> (snapshot())#{error => null, result => Data};
            ok -> (snapshot())#{error => null};
            {error, Reason} -> (snapshot())#{error => error_text(Reason)}
        end,
        maps:merge(Response, maps:with([<<"request_id">>], Request))
    catch
        _:_ -> (snapshot())#{error => <<"Native operation unavailable. Check runtime status; restart for a fresh session.">>}
    end,
    iolist_to_binary(json:encode(Reply)).

command(#{<<"method">> := <<"snapshot">>}) -> ok;
command(#{<<"method">> := <<"create_swarm">>}) ->
    case parvi_cluster_desk:create() of
        {ok, #{<<"cluster">> := Id}} -> {ok, #{swarm_id => Id}};
        Error -> Error
    end;
command(#{<<"method">> := <<"join_swarm">>, <<"invitation">> := Link}) ->
    case parvi_cluster_desk:join(Link) of
        ok -> {ok, #{notice => <<"Invitation submitted; waiting for native admission and connection.">>}};
        Error -> Error
    end;
command(#{<<"method">> := <<"send_swarm">>, <<"swarm_id">> := Id, <<"text">> := Text}) ->
    case parvi_cluster_trust:policy() of
        #{<<"cluster">> := Id} ->
            case parvi:send(Text) of {ok, _} -> ok; Error -> Error end;
        _ -> {error, not_a_member}
    end;
command(#{<<"method">> := <<"remove_both">>, <<"swarm_id">> := Id, <<"target">> := Target}) ->
    case parvi_cluster_trust:policy() of
        #{<<"cluster">> := Id, <<"members">> := Members} ->
            case [Key || {Key, #{<<"node">> := Name}} <- maps:to_list(Members), Name =:= Target] of
                [Key] ->
                    case parvi_cluster_trust:remove_both(Key) of
                        {ok, complete} -> ok;
                        {ok, _} -> {ok, #{notice => <<"Local access retired; remote removal completion is unconfirmed.">>}};
                        Error -> Error
                    end;
                _ -> {error, not_a_member}
            end;
        _ -> {error, not_a_member}
    end;
command(#{<<"method">> := <<"leave_swarm">>}) ->
    {error, <<"Native voluntary leave is not implemented yet. Quit to disconnect; this does not revoke cluster membership.">>};
command(#{<<"method">> := <<"configure_desk">>}) ->
    {error, <<"This native increment uses the global Render desk. Restart to begin a fresh session.">>};
command(_) -> {error, <<"Unsupported native request.">>}.

snapshot() ->
    #{policy := Policy, event := Event} = parvi_cluster_desk:status(),
    #{chat_nodes := ChatNodes} = parvi:status(),
    Messages = [message(M) || M <- parvi:history()],
    Swarms = case Policy of
        #{<<"cluster">> := Id} ->
            Invitation = case parvi_cluster_desk:invitation() of {ok, Link} -> Link; _ -> null end,
            [#{id => Id, name => <<"Native cluster">>, invitation => Invitation,
               members => [atom_to_binary(N) || N <- ChatNodes], messages => Messages}];
        _ -> []
    end,
    #{node => atom_to_binary(node()), native_cluster => true,
      relay => parvi_relay:status(),
      direct => #{enabled => true, peers => [atom_to_binary(N) || N <- nodes()]},
      connection_string => null, known_nodes => [],
      %% Only OTP-observed local connections are edges; no topology polling.
      network => #{nodes => [#{id => atom_to_binary(N), state => <<"running">>,
                               detail => <<"otp_process_group">>} || N <- ChatNodes],
                   edges => [[atom_to_binary(node()), atom_to_binary(N)] || N <- nodes()]},
      swarms => Swarms,
      runtime_info => iolist_to_binary(io_lib:format("OTP ~s / ERTS ~s / native WebRTC / ~p",
          [erlang:system_info(otp_release), erlang:system_info(version), Event])),
      peers => [atom_to_binary(N) || N <- ChatNodes, N =/= node()], messages => Messages}.

message(#{id := Id, text := Text, sender := Sender, sent_at_ms := Time}) ->
    #{id => list_to_binary(erlang:ref_to_list(Id)), text => Text,
      sender => atom_to_binary(Sender), time => Time}.

error_text(already_clustered_or_not_created) ->
    <<"This increment supports one native cluster per session. Restart to create or join another.">>;
error_text(Reason) when is_binary(Reason) -> Reason;
error_text(Reason) -> iolist_to_binary(io_lib:format("Native operation: ~p", [Reason])).
