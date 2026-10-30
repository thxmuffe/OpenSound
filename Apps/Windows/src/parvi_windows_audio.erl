%% Node-local audio input owns its native port independently of the window.
-module(parvi_windows_audio).
-behaviour(gen_server).
-export([start/0, stop/0, status/0, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

start() ->
    case supervisor:start_child(parvi_windows_sup,
            #{id => audio_input, start => {?MODULE, start_link, []}}) of
        {ok, _} -> gen_server:call(?MODULE, start);
        {error, {already_started, _}} -> gen_server:call(?MODULE, start);
        Error -> Error
    end.
stop() -> gen_server:call(?MODULE, stop).
status() -> case whereis(?MODULE) of undefined -> #{state => stopped}; _ -> gen_server:call(?MODULE, status) end.
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
init([]) -> {ok, #{state => stopped, port => undefined}}.
handle_call(start, _, #{port := undefined} = S) ->
    Root = filename:dirname(filename:dirname(code:which(?MODULE))),
    try open_port({spawn_executable, filename:join(Root, "parvi_audio_input.exe")},
                  [binary, {line, 4096}, exit_status, use_stdio, hide]) of
        Port -> {reply, ok, #{state => starting, port => Port}}
    catch error:Reason -> {reply, {error, Reason}, S#{state := error, error => <<"Build parvi_audio_input.exe first.">>}} end;
handle_call(start, _, S) -> {reply, ok, S};
handle_call(stop, _, S) ->
    close(S), {reply, ok, #{state => stopped, port => undefined}};
handle_call(status, _, S) -> {reply, maps:remove(port, S), S}.
handle_cast(_, S) -> {noreply, S}.
handle_info({Port, {data, {eol, JSON}}}, #{port := Port} = S) ->
    Data = json:decode(JSON),
    case Data of
        #{<<"error">> := Error} -> {noreply, S#{state := error, error => Error}};
        _ -> {noreply, #{state => running, port => Port, meter => Data}}
    end;
handle_info({Port, {exit_status, Code}}, #{port := Port} = S) ->
    {noreply, S#{port := undefined, state := error,
                error => maps:get(error, S, iolist_to_binary(io_lib:format("Audio input stopped (~B). Start to reconnect.", [Code])))}};
handle_info(_, S) -> {noreply, S}.
terminate(_, S) -> close(S).
close(#{port := undefined}) -> ok;
close(#{port := Port}) -> try port_close(Port) catch error:badarg -> ok end, ok.
