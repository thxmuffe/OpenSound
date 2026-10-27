%% Observation-based distribution topology. Never infer links from membership.
-module(parvi_topology).
-behaviour(gen_server).
-export([ensure_started/0, start_link/0, snapshot/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

ensure_started() ->
    spawn(fun() -> supervisor:start_child(parvi_windows_sup,
        #{id => topology, start => {?MODULE, start_link, []}}) end), ok.
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
snapshot() ->
    case whereis(?MODULE) of
        undefined -> #{nodes => parvi_node_status:rows(), edges => []};
        _ -> gen_server:call(?MODULE, snapshot)
    end.
init([]) -> self() ! poll, {ok, #{reports => #{}, pending => #{}}}.
handle_call(snapshot, _, #{reports := Reports} = S) ->
    Connected = nodes(),
    %% Discard reports from disconnected reporters immediately, even between polls.
    Local = [{node(), N} || N <- Connected],
    Remote = [{From, To} || {From, Peers} <- maps:to_list(Reports),
                           lists:member(From, Connected), To <- Peers, From =/= To],
    Edges = lists:usort([pair(A, B) || {A,B} <- Local ++ Remote]),
    Known = parvi_node_status:rows(),
    Extra = lists:usort([N || {A,B} <- Edges, N <- [A,B], not lists:keymember(N, 1, Known)]),
    {reply, #{nodes => Known ++ [{N, checking, reported_by_peer} || N <- Extra], edges => Edges}, S}.
handle_cast(_, S) -> {noreply, S}.
handle_info(poll, #{pending := Pending} = S) ->
    erlang:send_after(3000, self(), poll),
    Next = lists:foldl(fun(Node, Acc) ->
        case maps:is_key(Node, Acc) of
            true -> Acc;
            false ->
                Parent = self(), Ref = make_ref(),
                spawn(fun() ->
                    Result = try erpc:call(Node, erlang, nodes, [], 1500) of
                        Peers when is_list(Peers), length(Peers) =< 256 -> Peers;
                        _ -> unavailable
                    catch _:_ -> unavailable end,
                    Parent ! {report, Node, Ref, Result}
                end),
                Acc#{Node => Ref}
        end
    end, maps:with(nodes(), Pending), nodes()),
    {noreply, S#{pending := Next}};
handle_info({report, Node, Ref, Result}, #{reports := Reports, pending := Pending} = S) ->
    case maps:find(Node, Pending) of
        {ok, Ref} ->
            Next = case Result of
                Peers when is_list(Peers) -> Reports#{Node => [N || N <- Peers, is_atom(N)]};
                _ -> maps:remove(Node, Reports)
            end,
            {noreply, S#{reports := maps:with(nodes(), Next), pending := maps:remove(Node, Pending)}};
        _ -> {noreply, S}
    end;
handle_info(_, S) -> {noreply, S}.

pair(A, B) ->
    [First, Second] = lists:sort([atom_to_binary(A), atom_to_binary(B)]), {First, Second}.
