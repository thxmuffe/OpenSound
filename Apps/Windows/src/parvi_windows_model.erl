%% Session UI data outlives disposable windows. No widget references or history.
-module(parvi_windows_model).
-behaviour(gen_server).
-export([start_link/1, get/0, put/1, request/4]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link(Seed) -> gen_server:start_link({local, ?MODULE}, ?MODULE, Seed, []).
get() -> gen_server:call(?MODULE, get).
put(Values) -> gen_server:call(?MODULE, {put, Values}).
request(Command, Kind, ReplyTo, Ref) -> gen_server:cast(?MODULE, {request, Command, Kind, ReplyTo, Ref}).
init(Seed) -> {ok, Seed}.
handle_call(get, _, S) -> {reply, S, S};
handle_call({put, Values}, _, S) -> {reply, ok, maps:merge(S, Values)}.
handle_cast({request, Command, Kind, ReplyTo, Ref}, S) ->
    Model = self(),
    spawn(fun() ->
        Reply = try json:decode(parvi_bridge:request(iolist_to_binary(json:encode(Command))))
                catch _:_ -> unavailable end,
        Model ! {reply, Command, Kind, ReplyTo, Ref, Reply}
    end),
    {noreply, S};
handle_cast(_, S) -> {noreply, S}.
handle_info({reply, Command, Kind, ReplyTo, Ref, Reply}, S) ->
    Next = case {Kind, Reply} of
        {send, #{<<"error">> := null}} ->
            case unicode:characters_to_binary(maps:get(draft, S, "")) =:= maps:get(text, Command) of
                true -> S#{draft => ""};
                false -> S
            end;
        {join, #{<<"error">> := null}} -> S#{dialog => false};
        _ -> S
    end,
    ReplyTo ! {reply, Ref, Kind, Reply},
    {noreply, Next};
handle_info(_, S) -> {noreply, S}.
