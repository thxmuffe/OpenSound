%% Watch compiled UI code; the supervisor owns processes, the model owns state.
-module(parvi_windows_host).
-behaviour(gen_server).
-export([main/0, run/0, run/1, start_link/1, reload/0, status/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

main() ->
    {ok, _} = application:ensure_all_started(crypto),
    true = node() =/= nonode@nohost,
    erlang:set_cookie(binary_to_atom(binary:encode_hex(crypto:strong_rand_bytes(24)))),
    {ok, _} = parvi:start(), run(), init:stop().

run() -> run(#{}).
run(Seed) ->
    {ok, Sup} = parvi_windows_sup:start_link(self(), Seed),
    receive ui_closed -> gen_server:stop(Sup) end.

start_link(Owner) -> gen_server:start_link({local, ?MODULE}, ?MODULE, Owner, []).
reload() -> gen_server:cast(?MODULE, reload).
status() -> gen_server:call(?MODULE, status).
init(Owner) ->
    Path = code:which(parvi_windows),
    {ok, Binary} = file:read_file(Path),
    self() ! start_ui,
    erlang:send_after(750, self(), check),
    {ok, #{owner => Owner, path => Path, hash => erlang:md5(Binary),
           pid => undefined, generation => -1, last_error => none}}.
handle_call(status, _, S) -> {reply, maps:with([pid, generation, last_error], S), S}.
handle_cast(reload, S) -> {noreply, check(S, true)}.
handle_info(start_ui, S) -> {noreply, start_ui(S)};
handle_info(check, S) ->
    erlang:send_after(750, self(), check),
    {noreply, track(check(S, false))};
handle_info({'DOWN', _, process, Pid, normal}, #{pid := Pid, owner := Owner} = S) ->
    Owner ! ui_closed, {noreply, S#{pid := undefined}};
handle_info(_, S) -> {noreply, S}.

check(#{path := Path, hash := Hash} = S, Force) ->
    case file:read_file(Path) of
        {ok, Binary} ->
            NewHash = erlang:md5(Binary),
            case {Force orelse NewHash =/= Hash, beam_lib:chunks(Binary, [exports])} of
                {true, {ok, {parvi_windows, [{exports, Exports}]}}} ->
                    case lists:member({start_link, 0}, Exports) of
                        true ->
                            _ = supervisor:terminate_child(parvi_windows_sup, window),
                            _ = supervisor:delete_child(parvi_windows_sup, window),
                            S1 = S#{hash := NewHash, pid := undefined},
                            case code:soft_purge(parvi_windows) of
                                true ->
                                    case code:load_binary(parvi_windows, Path, Binary) of
                                        {module, parvi_windows} -> start_ui(S1);
                                        {error, Reason} -> S1#{last_error := {ui_load_failed, Reason}}
                                    end;
                                false -> S1#{last_error := old_ui_code_in_use}
                            end;
                        false -> S
                    end;
                _ -> S %% Ignore a compiler's incomplete output.
            end;
        _ -> S
    end.

start_ui(S) ->
    case supervisor:start_child(parvi_windows_sup, #{id => window,
            start => {parvi_windows, start_link, []}, restart => transient}) of
        {ok, Pid} -> attach(Pid, S);
        {error, _} ->
            logger:error("UI failed to start; waiting for a corrected build."),
            S#{last_error := ui_start_failed}
    end.
track(S) ->
    case lists:keyfind(window, 1, supervisor:which_children(parvi_windows_sup)) of
        {window, Pid, _, _} when is_pid(Pid) -> attach(Pid, S);
        _ -> S
    end.
attach(Pid, #{pid := Pid} = S) -> S;
attach(Pid, S) ->
    monitor(process, Pid),
    S#{pid := Pid, generation := maps:get(generation, S) + 1, last_error := none}.
