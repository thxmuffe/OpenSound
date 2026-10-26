-module(parvi_chat).
-behaviour(gen_server).
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-define(GROUP, {parvi, chat, 1}).
-define(MAX_BYTES, 4096).
-define(HISTORY_LIMIT, 200).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    ok = pg:join(parvi_pg, ?GROUP, self()),
    logger:notice("Parvi chat started on ~p", [node()]),
    {ok, #{history => queue:new(), count => 0, subscribers => #{}}}.

handle_call({send, Text}, _From, State) ->
    case text(Text) of
        {ok, Binary} ->
            Message = #{version => 1, id => make_ref(), sender => node(),
                        text => Binary, sent_at_ms => erlang:system_time(millisecond)},
            %% Record locally before replying. Remote delivery is best effort.
            Members = pg:get_members(parvi_pg, ?GROUP),
            [gen_server:cast(Pid, {message, Message}) || Pid <- Members, Pid =/= self()],
            {reply, {ok, Message}, record_message(Message, State)};
        Error -> {reply, Error, State}
    end;
handle_call(history, _From, State) ->
    {reply, queue:to_list(maps:get(history, State)), State};
handle_call(status, _From, State) ->
    ChatNodes = lists:usort([node(Pid) || Pid <- pg:get_members(parvi_pg, ?GROUP)]),
    Status = case node() of nonode@nohost -> local_only; _ -> distributed end,
    {reply, #{node => node(), mode => Status, connected_nodes => nodes(),
              chat_nodes => ChatNodes, history_count => maps:get(count, State),
              history_limit => ?HISTORY_LIMIT}, State};
handle_call({subscribe, Pid}, _From, #{subscribers := Subs} = State) when is_pid(Pid) ->
    case maps:is_key(Pid, Subs) of
        true -> {reply, ok, State};
        false ->
            Ref = monitor(process, Pid),
            {reply, ok, State#{subscribers := Subs#{Pid => Ref}}}
    end;
handle_call({unsubscribe, Pid}, _From, #{subscribers := Subs} = State) ->
    case maps:take(Pid, Subs) of
        {Ref, Rest} ->
            demonitor(Ref, [flush]),
            {reply, ok, State#{subscribers := Rest}};
        error -> {reply, ok, State}
    end;
handle_call(_Request, _From, State) -> {reply, {error, unsupported_request}, State}.

handle_cast({message, #{version := 1, id := Id, sender := Sender,
                        text := Text, sent_at_ms := Time} = Message}, State)
        when is_reference(Id), is_atom(Sender), is_binary(Text), is_integer(Time) ->
    case text(Text) of
        {ok, Text} -> {noreply, record_message(Message, State)};
        _ -> {noreply, State}
    end;
handle_cast(_Message, State) -> {noreply, State}.

handle_info({'DOWN', Ref, process, Pid, _Reason}, #{subscribers := Subs} = State) ->
    case maps:find(Pid, Subs) of
        {ok, Ref} -> {noreply, State#{subscribers := maps:remove(Pid, Subs)}};
        _ -> {noreply, State}
    end;
handle_info(_Message, State) -> {noreply, State}.

text(Text) when is_binary(Text), byte_size(Text) > 0, byte_size(Text) =< ?MAX_BYTES ->
    case unicode:characters_to_binary(Text, utf8, utf8) of
        Binary when is_binary(Binary) -> {ok, Binary};
        _ -> {error, invalid_utf8}
    end;
text(_) -> {error, expected_utf8_binary_1_to_4096_bytes}.

record_message(Message, #{history := History, count := Count, subscribers := Subs} = State) ->
    Added = queue:in(Message, History),
    {Kept, NewCount} = case Count < ?HISTORY_LIMIT of
        true -> {Added, Count + 1};
        false -> {queue:drop(Added), Count}
    end,
    maps:foreach(fun(Pid, _Ref) -> Pid ! {parvi_message, Message} end, Subs),
    %% Do not put private message contents in logs.
    logger:info("Parvi message received from ~p", [maps:get(sender, Message)]),
    State#{history := Kept, count := NewCount}.
