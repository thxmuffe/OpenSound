%% Shared JSON interface for native hosts. request/1 is transport-independent.
%% macOS main/0 uses app-owned stdin/stdout pipes, never a network listener.
-module(parvi_bridge).
-export([main/0, request/1]).

main() ->
    logger:update_handler_config(default, config, #{type => standard_error}),
    io:setopts(standard_io, [binary, {encoding, utf8}]),
    {ok, _} = parvi:start(),
    loop().

loop() ->
    case io:get_line(standard_io, "") of
        eof -> init:stop();
        {error, _} -> init:stop(1);
        Line ->
            io:put_chars(standard_io, [request(Line), $\n]),
            loop()
    end.

%% An embedded host can call this same function without emulating terminal I/O.
request(JSON) ->
    Reply = try
        Request = json:decode(JSON),
        Result = command(Request),
        (snapshot())#{<<"error">> => Result}
    catch
        _:_ -> (snapshot())#{<<"error">> => <<"Invalid request or unavailable worker. Try again.">>}
    end,
    iolist_to_binary(json:encode(Reply)).

command(#{<<"method">> := <<"snapshot">>}) -> null;
command(#{<<"method">> := <<"discover">>, <<"url">> := URL}) ->
    case parvi_discovery:discover(URL) of
        ok -> null;
        {error, Error} -> Error
    end;
command(#{<<"method">> := <<"send">>, <<"text">> := Text}) ->
    case parvi:send(Text) of
        {ok, _} -> null;
        {error, _} -> <<"Use 1–4096 bytes of UTF-8 text.">>
    end;
command(#{<<"method">> := <<"connect">>, <<"node">> := Name, <<"cookie">> := Cookie})
        when is_binary(Name), byte_size(Name) > 0, byte_size(Name) =< 128,
             is_binary(Cookie), byte_size(Cookie) > 0, byte_size(Cookie) =< 128 ->
    %% Developer-only loopback prototype. Bound the names accepted by the UI.
    case re:run(Name, <<"^parvi_mac_[0-9]+@127\\.0\\.0\\.1$">>, [{capture, none}]) of
        match ->
            Node = binary_to_atom(Name, utf8),
            erlang:set_cookie(Node, binary_to_atom(Cookie, utf8)),
            case parvi:connect(Node) of
                ok -> null;
                _ -> <<"Could not connect. Check the node name and shared cookie.">>
            end;
        _ -> <<"This build connects to Parvi app instances on this Mac only.">>
    end;
command(_) -> <<"Unsupported request.">>.

snapshot() ->
    Status = parvi:status(),
    #{<<"node">> => atom_to_binary(node()),
      <<"runtime_info">> => iolist_to_binary(io_lib:format("OTP ~s / ERTS ~s / worker ~p",
          [erlang:system_info(otp_release), erlang:system_info(version), whereis(parvi_chat)])),
      <<"known_nodes">> => parvi_discovery:nodes(),
      <<"peers">> => [atom_to_binary(N) || N <- maps:get(chat_nodes, Status), N =/= node()],
      <<"messages">> => [message(M) || M <- parvi:history()]}.

message(#{id := Id, text := Text, sender := Sender, sent_at_ms := Time}) ->
    #{<<"id">> => list_to_binary(erlang:ref_to_list(Id)), <<"text">> => Text,
      <<"sender">> => atom_to_binary(Sender), <<"time">> => Time}.
