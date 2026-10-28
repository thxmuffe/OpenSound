%% Isolated OTP 29 carrier proof. Only pre-established probe channels are usable.
%% Handshakes, cookies, ticks and native distribution semantics belong to OTP.
-module(parvi_webrtc_dist).
-export([listen/1, listen/2, address/0, accept/1, accept_connection/5,
         setup/5, close/1, select/1, is_node_name/1, route/2, admit/1]).
-include_lib("kernel/include/dist_util.hrl").
-include_lib("kernel/include/net_address.hrl").

address() -> #net_address{host = "127.0.0.1", protocol = webrtc, family = inet}.
listen(Name) -> listen(Name, "127.0.0.1").
listen(_, _) -> {ok, {parvi_webrtc, address(), rand:uniform(16#fffffffc) + 3}}.
select(Node) -> maps:is_key(Node, persistent_term:get(?MODULE, #{})).
is_node_name(Node) -> inet_tcp_dist:is_node_name(Node).
route(Node, Ctrl) ->
    persistent_term:put(?MODULE, (persistent_term:get(?MODULE, #{}))#{Node => Ctrl}).
admit(Ctrl) -> parvi_webrtc_accept ! {channel, Ctrl}, ok.

accept(parvi_webrtc) ->
    Kernel = self(),
    spawn_link(fun() -> register(parvi_webrtc_accept, self()), accept_loop(Kernel) end).
accept_loop(Kernel) ->
    receive
        {channel, Ctrl} ->
            Kernel ! {accept, self(), Ctrl, inet, webrtc},
            receive
                {Kernel, controller, Sup} ->
                    ok = gen_server:call(Ctrl, {supervisor, Sup}),
                    Sup ! {self(), controller};
                {Kernel, unsupported_protocol} -> exit(unsupported_protocol)
            end,
            accept_loop(Kernel)
    end.

accept_connection(Acceptor, Ctrl, MyNode, Allowed, SetupTime) ->
    Kernel = self(),
    spawn_opt(fun() ->
        receive {Acceptor, controller} -> ok end,
        HS = (hs_data(Ctrl))#hs_data{kernel_pid = Kernel, this_node = MyNode,
            allowed = Allowed, timer = dist_util:start_timer(SetupTime)},
        dist_util:handshake_other_started(HS)
    end, dist_util:net_ticker_spawn_options()).

setup(Node, Type, MyNode, _, SetupTime) ->
    Kernel = self(),
    spawn_opt(fun() ->
        Ctrl = maps:get(Node, persistent_term:get(?MODULE)),
        ok = gen_server:call(Ctrl, {supervisor, self()}),
        HS = (hs_data(Ctrl))#hs_data{kernel_pid = Kernel, this_node = MyNode,
            other_node = Node, request_type = Type, other_version = 6,
            timer = dist_util:start_timer(SetupTime)},
        dist_util:handshake_we_started(HS)
    end, dist_util:net_ticker_spawn_options()).

hs_data(Ctrl) ->
    #hs_data{socket = Ctrl, this_flags = 0,
        f_send = fun(C, Data) -> gen_server:call(C, {send, iolist_to_binary(Data)}) end,
        f_recv = fun(C, 0, Timeout) -> gen_server:call(C, recv, Timeout) end,
        f_setopts_pre_nodeup = fun(_) -> ok end,
        f_setopts_post_nodeup = fun(_) -> ok end,
        f_getll = fun(C) -> {ok, C} end,
        f_address = fun(_, _) -> address() end,
        f_handshake_complete = fun(C, _, Handle) -> gen_server:call(C, {activate, Handle}) end,
        mf_tick = fun(C) -> gen_server:cast(C, tick) end,
        mf_getstat = fun(C) -> gen_server:call(C, getstat, 1000) end}.

close(Ctrl) when is_pid(Ctrl) -> gen_server:stop(Ctrl);
close(parvi_webrtc) ->
    case whereis(parvi_webrtc_accept) of undefined -> ok; P -> exit(P, shutdown) end.
