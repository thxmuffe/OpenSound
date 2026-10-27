-module(parvi_windows_sup).
-behaviour(supervisor).
-export([start_link/2, init/1]).

start_link(Owner, Seed) -> supervisor:start_link({local, ?MODULE}, ?MODULE, {Owner, Seed}).
init({Owner, Seed}) ->
    {ok, {#{strategy => rest_for_one, intensity => 3, period => 10}, [
        #{id => model, start => {parvi_windows_model, start_link, [Seed]}},
        #{id => reloader, start => {parvi_windows_host, start_link, [Owner]}}
    ]}}.
