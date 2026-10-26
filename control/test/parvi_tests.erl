-module(parvi_tests).
-include_lib("eunit/include/eunit.hrl").

chat_test_() ->
    {setup, fun() -> {ok, _} = parvi:start() end,
     fun(_) -> application:stop(parvi) end,
     [fun messaging/0, fun validation_and_bounds/0, fun restart/0]}.

messaging() ->
    ok = parvi:subscribe(),
    ok = parvi:subscribe(),
    {ok, Message} = parvi:send(<<"Hei parvi!", 240, 159, 144, 166>>),
    receive {parvi_message, Message} -> ok after 1000 -> error(no_ui_event) end,
    receive {parvi_message, Message} -> error(duplicate_ui_event) after 0 -> ok end,
    ?assertEqual([Message], parvi:history()),
    ok = parvi:unsubscribe(),
    {ok, _} = parvi:send(<<"after unsubscribe">>),
    receive {parvi_message, _} -> error(unsubscribed_event) after 0 -> ok end.

validation_and_bounds() ->
    ?assertMatch({error, _}, parvi:send(<<>>)),
    ?assertMatch({error, _}, parvi:send("not a binary")),
    ?assertMatch({error, invalid_utf8}, parvi:send(<<255>>)),
    ?assertMatch({error, _}, parvi:send(binary:copy(<<"x">>, 4097))),
    {ok, _} = parvi:send(binary:copy(<<"x">>, 4096)),
    [parvi:send(integer_to_binary(I)) || I <- lists:seq(1, 205)],
    History = parvi:history(),
    ?assertEqual(200, length(History)),
    ?assertEqual(<<"6">>, maps:get(text, hd(History))),
    ?assertEqual(<<"205">>, maps:get(text, lists:last(History))),
    gen_server:cast(parvi_chat, {message, #{version => 999}}),
    ?assertEqual(History, parvi:history()).

restart() ->
    Old = whereis(parvi_chat),
    exit(Old, kill),
    New = await_restart(parvi_chat, Old, 100),
    ?assert(is_pid(New)),
    ?assertEqual([], parvi:history()),
    %% A pg restart must also restart the chat worker so membership is restored.
    OldPg = whereis(parvi_pg),
    exit(OldPg, kill),
    _ = await_restart(parvi_pg, OldPg, 100),
    _ = await_restart(parvi_chat, New, 100),
    ?assertEqual([node()], maps:get(chat_nodes, parvi:status())),
    ?assertMatch({ok, _}, parvi:send(<<"alive">>)).

await_restart(_Name, _Old, 0) -> error(restart_timeout);
await_restart(Name, Old, Attempts) ->
    case whereis(Name) of
        Pid when is_pid(Pid), Pid =/= Old -> Pid;
        _ -> timer:sleep(10), await_restart(Name, Old, Attempts - 1)
    end.
