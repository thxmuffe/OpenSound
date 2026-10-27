%% OTP connection events plus a bounded application-level responsiveness check.
-module(parvi_node_status).
-behaviour(gen_server).
-export([ensure_started/0, start_link/0, rows/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

ensure_started() ->
    %% Do not call our parent supervisor synchronously during wx initialization.
    spawn(fun() -> supervisor:start_child(parvi_windows_sup,
        #{id => node_status, start => {?MODULE, start_link, []}}) end), ok.
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
rows() ->
    case whereis(?MODULE) of
        undefined -> [{atom_to_binary(node()), checking, pending}];
        _ -> gen_server:call(?MODULE, rows)
    end.

init([]) ->
    ok = net_kernel:monitor_nodes(true, #{nodedown_reason => true}),
    Saved = maps:get(node_states, parvi_windows_model:get(), #{}),
    Connected = [node() | nodes()],
    Entries = maps:map(fun(N, Value) ->
        case lists:member(N, Connected) of true -> Value; false -> {down, disconnected} end
    end, Saved),
    self() ! probe,
    {ok, #{entries => Entries, pending => #{}}}.
handle_call(rows, _, #{entries := Entries} = S) ->
    Names = [node() | lists:sort(maps:keys(maps:remove(node(), Entries)))],
    {reply, [{atom_to_binary(N), State, Reason} || N <- Names,
             {State, Reason} <- [maps:get(N, Entries, {checking, pending})]], S}.
handle_cast(_, S) -> {noreply, S}.

handle_info(probe, S) ->
    erlang:send_after(2000, self(), probe),
    {noreply, lists:foldl(fun check/2, S, [node() | nodes()])};
handle_info({nodeup, Node, _}, #{pending := Pending} = S) ->
    {noreply, check(Node, store(Node, checking, pending, S#{pending := maps:remove(Node, Pending)}))};
handle_info({nodedown, Node, Info}, #{pending := Pending} = S) ->
    {noreply, store(Node, down, maps:get(nodedown_reason, Info, disconnected),
                    S#{pending := maps:remove(Node, Pending)})};
handle_info({probe_result, Node, Ref, Result}, #{pending := Pending} = S) ->
    case maps:find(Node, Pending) of
        {ok, Ref} ->
            {Status, Reason} = Result,
            {noreply, store(Node, Status, Reason, S#{pending := maps:remove(Node, Pending)})};
        _ -> {noreply, S} %% A disconnect/reconnect superseded this probe.
    end;
handle_info(_, S) -> {noreply, S}.

check(Node, #{pending := Pending, entries := Entries} = S) ->
    case maps:is_key(Node, Pending) of
        true -> S;
        false ->
            Parent = self(), Ref = make_ref(),
            spawn(fun() ->
                Result = try gen_server:call({parvi_chat, Node}, status, 1500) of
                    #{node := Node} -> {running, responsive};
                    _ -> {unresponsive, unexpected_reply}
                catch exit:{timeout, _} -> {unresponsive, timeout};
                      exit:_ -> {unresponsive, worker_unavailable} end,
                Parent ! {probe_result, Node, Ref, Result}
            end),
            S#{entries := Entries#{Node => maps:get(Node, Entries, {checking, pending})},
               pending := Pending#{Node => Ref}}
    end.
store(Node, State, Reason, #{entries := Entries} = S) ->
    Next = Entries#{Node => {State, Reason}},
    parvi_windows_model:put(#{node_states => Next}),
    S#{entries := Next}.
