%% Small adapter around the attributed OTP Reltool graph view.
-module(parvi_graph_view).
-export([new/1, update/2, pause/2, stop/1]).

new(Panel) ->
    {Pid, Sizer} = parvi_fgraph_win:new(Panel, []),
    %% Reltool's release-editing controls have no meaning for a live topology.
    wxSizer:hide(Sizer, 0),
    wxPanel:setSizer(Panel, Sizer),
    #{pid => Pid, nodes => #{}, edges => []}.
update(#{nodes := Rows, edges := Edges}, #{pid := Pid, nodes := Previous, edges := OldEdges} = View) ->
    Current = maps:from_list([{Name, Status} || {Name, Status, _} <- Rows]),
    [parvi_fgraph_win:del_link(Pid, keys(Edge)) || Edge <- OldEdges -- Edges],
    [parvi_fgraph_win:del_node(Pid, key(Name)) || Name <- maps:keys(Previous) -- maps:keys(Current)],
    [case maps:find(Name, Previous) of
        error -> parvi_fgraph_win:add_node(Pid, key(Name), {{65,75,80}, colour(Status)});
        {ok, Status} -> ok;
        _ -> parvi_fgraph_win:change_node(Pid, key(Name), {{65,75,80}, colour(Status)})
     end || {Name, Status} <- maps:to_list(Current)],
    [parvi_fgraph_win:add_link(Pid, keys(Edge)) || Edge <- Edges -- OldEdges],
    View#{nodes := Current, edges := Edges}.
pause(#{pid := Pid}, Paused) -> Pid ! {set_paused, Paused}, ok.
stop(#{pid := Pid}) -> parvi_fgraph_win:stop(Pid, shutdown).
key(Name) -> binary_to_existing_atom(Name).
keys({A,B}) -> {key(A), key(B)}.
colour(running) -> {152,248,152};
colour(unresponsive) -> {255,255,123};
colour(down) -> {255,122,122};
colour(checking) -> {221,221,221}.
