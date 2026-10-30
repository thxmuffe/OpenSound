%% Session UI data outlives disposable windows. Swarms own all chat history.
-module(parvi_windows_model).
-behaviour(gen_server).
-export([start_link/1, get/0, put/1, request/4, selected/1, draft/1, network/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link(Seed) -> gen_server:start_link({local, ?MODULE}, ?MODULE, Seed, []).
get() -> gen_server:call(?MODULE, get).
put(Values) -> gen_server:call(?MODULE, {put, Values}).
request(Command, Kind, ReplyTo, Ref) -> gen_server:cast(?MODULE, {request, Command, Kind, ReplyTo, Ref}).
init(Seed) ->
    Desk = case parvi_relay:url() of undefined -> ""; URL -> unicode:characters_to_list(URL) end,
    {ok, maps:merge(#{selected => undefined, drafts => #{}, view => 0, incoming => "", desk => Desk,
                     snapshot => #{}, pending => #{}, error => "", notice => "", serial => 0, applied => 0}, Seed)}.
handle_call(get, _, S) -> {reply, S, S};
handle_call({put, Values}, _, S) -> {reply, ok, maps:merge(S, Values)}.
handle_cast({request, _, snapshot, _, _}, #{pending := Pending} = S) when map_size(Pending) > 0 ->
    {noreply, S};
handle_cast({request, Command, Kind, ReplyTo, Ref}, #{pending := Pending, serial := Serial} = S) ->
    Model = self(), NextSerial = Serial + 1,
    spawn(fun() ->
        Reply = try json:decode(parvi_bridge:request(iolist_to_binary(json:encode(Command))))
                catch _:_ -> unavailable end,
        Model ! {reply, Ref, Reply}
    end),
    Entry = #{command => Command, kind => Kind, target => ReplyTo, serial => NextSerial},
    {noreply, S#{pending := Pending#{Ref => Entry}, serial := NextSerial}};
handle_cast(_, S) -> {noreply, S}.
handle_info({reply, Ref, Reply}, #{pending := Pending} = S) ->
    case maps:take(Ref, Pending) of
        error -> {noreply, S};
        {#{command := Command, kind := Kind, target := Target, serial := Serial}, Rest} ->
            S1 = S#{pending := Rest},
            S2 = case Reply of
                #{<<"swarms">> := _} when Serial >= map_get(applied, S) ->
                    choose(S1#{snapshot := Reply, applied := Serial});
                _ -> S1
            end,
            Next = case Reply of
                #{<<"error">> := null} ->
                    Notice = maps:get(<<"notice">>, maps:get(<<"result">>, Reply, #{}), ""),
                    S3 = case Kind of snapshot -> S2; _ -> S2#{notice := Notice} end,
                    complete(Command, Kind, Reply, S3);
                #{<<"error">> := Error} -> S2#{error := Error};
                _ -> S2#{error := "Erlang worker unavailable. Retrying..."}
            end,
            Target ! {reply, Ref, Kind, Reply},
            {noreply, Next}
    end;
handle_info(_, S) -> {noreply, S}.

complete(#{swarm_id := Id, text := Text}, send, _, #{drafts := Drafts} = S) ->
    case unicode:characters_to_binary(maps:get(Id, Drafts, "")) =:= Text of
        true -> S#{drafts := Drafts#{Id => ""}, error := ""};
        false -> S#{error := ""}
    end;
complete(Command, Kind, Reply, S) when Kind =:= join; Kind =:= create ->
    S1 = case {Kind, maps:get(invitation, Command, undefined)} of
        {join, Invitation} ->
            case string:trim(unicode:characters_to_binary(maps:get(incoming, S))) =:= Invitation of
                true -> S#{incoming := ""}; false -> S
            end;
        _ -> S
    end,
    case Reply of
        #{<<"result">> := #{<<"swarm_id">> := Id}} -> choose(S1#{selected := Id, error := ""});
        _ -> S1#{error := ""}
    end;
complete(Command, snapshot,
         #{<<"relay">> := #{<<"connected">> := true}} = Reply,
         #{error := <<"Reception desk disconnected. Wait for reconnection.">>} = S) ->
    complete(Command, snapshot, Reply, S#{error := ""});
complete(_, snapshot, Reply, S) ->
    case Reply of
        #{<<"native_cluster">> := true, <<"swarms">> := [_ | _]} -> S#{notice := ""};
        _ -> S
    end;
complete(_, configure, _, S) -> S#{drafts := #{}, incoming := "", error := ""};
complete(_, _, _, S) -> S#{error := ""}.

choose(#{selected := Id, snapshot := Snapshot} = S) ->
    Swarms = maps:get(<<"swarms">>, Snapshot, []),
    case lists:any(fun(Swarm) -> maps:get(<<"id">>, Swarm) =:= Id end, Swarms) of
        true -> S;
        false -> S#{selected := case Swarms of [First | _] -> maps:get(<<"id">>, First); [] -> undefined end}
    end.
selected(#{selected := Id, snapshot := Snapshot}) ->
    case [Swarm || #{<<"id">> := I} = Swarm <- maps:get(<<"swarms">>, Snapshot, []), I =:= Id] of
        [Swarm] -> Swarm; [] -> undefined
    end.
draft(#{selected := Id, drafts := Drafts}) -> maps:get(Id, Drafts, "").

%% Transport observations are filtered by logical membership, never a global chat.
network(S) ->
    Members = case selected(S) of undefined -> []; Swarm -> maps:get(<<"members">>, Swarm) end,
    Observed = maps:get(<<"network">>, maps:get(snapshot, S), #{}),
    Rows = maps:from_list([{maps:get(<<"id">>, N), N} || N <- maps:get(<<"nodes">>, Observed, [])]),
    #{nodes => [{N, status(maps:get(<<"state">>, maps:get(N, Rows, #{}), <<"checking">>)), observed} || N <- Members],
      edges => [{A, B} || [A, B] <- maps:get(<<"edges">>, Observed, []),
                          lists:member(A, Members), lists:member(B, Members)]}.
status(<<"running">>) -> running;
status(<<"unresponsive">>) -> unresponsive;
status(<<"down">>) -> down;
status(_) -> checking.
