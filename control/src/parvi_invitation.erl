%% Swarm-scoped invitations for the trusted, loopback-only prototype.
-module(parvi_invitation).
-export([format/2, parse/1]).

format(Swarm, Token) ->
    Query = uri_string:compose_query([{<<"node">>, atom_to_binary(node())},
        {<<"cookie">>, atom_to_binary(erlang:get_cookie())},
        {<<"swarm">>, Swarm}, {<<"token">>, Token}]),
    <<"parvi://swarm/v1?", Query/binary>>.

parse(Input) when is_binary(Input), byte_size(Input) =< 2048 ->
    try
        #{scheme := <<"parvi">>, host := <<"swarm">>, path := <<"/v1">>, query := Query} =
            URI = uri_string:parse(string:trim(Input)),
        4 = map_size(URI),
        [{<<"cookie">>, Cookie}, {<<"node">>, Node}, {<<"swarm">>, Swarm}, {<<"token">>, Token}] =
            lists:sort(uri_string:dissect_query(Query)),
        {ok, _} = parvi_connection:parse(parvi_connection:format(Node, Cookie)),
        true = valid_id(Swarm) andalso valid_id(Token),
        {ok, #{node => Node, cookie => Cookie, swarm => Swarm, token => Token}}
    catch _:_ -> {error, invalid_invitation} end;
parse(_) -> {error, invalid_invitation}.

valid_id(Id) when is_binary(Id), byte_size(Id) =:= 32 ->
    re:run(Id, <<"^[0-9A-F]{32}$">>, [{capture, none}]) =:= match;
valid_id(_) -> false.
