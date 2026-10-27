%% Native desktop adapter. All messaging and discovery remain in control/.
-module(parvi_windows).
-behaviour(wx_object).
-include_lib("wx/include/wx.hrl").
-export([main/0, start/0, start_link/0, init/1, handle_event/2, handle_info/2,
         handle_call/3, handle_cast/2, terminate/2, code_change/3]).

main() ->
    %% Tail-call the stable host: no old UI code remains on its stack at reload.
    parvi_windows_host:main().

start() -> wx_object:start(?MODULE, [], []).
start_link() ->
    case wx_object:start_link(?MODULE, [], []) of
        {error, _} = Error -> Error;
        Object -> {ok, wx_object:get_pid(Object)}
    end.

init([]) ->
    wx:new(),
    try build_window(parvi_windows_model:get())
    catch Class:Reason:Stack -> wx:destroy(), erlang:raise(Class, Reason, Stack) end.

build_window(Saved) ->
    Frame = wxFrame:new(wx:null(), ?wxID_ANY, "Parvi",
        [{size, maps:get(size, Saved, {1020, 740})}]),
    wxFrame:setMinSize(Frame, {760, 560}),
    Root = wxPanel:new(Frame),
    Row = wxBoxSizer:new(?wxHORIZONTAL),
    Sidebar = wxPanel:new(Root, [{size, {230, -1}}]),
    wxPanel:setBackgroundColour(Sidebar, {241, 245, 245}),
    Side = wxBoxSizer:new(?wxVERTICAL),
    add(Side, title(Sidebar, "Parvi", 24), 0, 20),
    add(Side, wxStaticText:new(Sidebar, ?wxID_ANY, "Erlang running"), 0, 12),
    add(Side, wxStaticText:new(Sidebar, ?wxID_ANY, "NODES"), 0, 12),
    Peers = wxListBox:new(Sidebar, ?wxID_ANY),
    wxListBox:connect(Peers, command_listbox_selected, [{userData, copy_node_connection}]),
    wxListBox:setToolTip(Peers, "Click a node to copy its connection string"),
    add(Side, Peers, 1, 12),
    add(Side, wxStaticText:new(Sidebar, ?wxID_ANY,
        "PARVI PROTOTYPE\nChat runs in Erlang/OTP.\nHistory lasts for this session."), 0, 16),
    wxPanel:setSizer(Sidebar, Side),
    wxSizer:add(Row, Sidebar, [{flag, ?wxEXPAND}]),
    Content = wxPanel:new(Root),
    wxPanel:setBackgroundColour(Content, {255,255,255}),
    Column = wxBoxSizer:new(?wxVERTICAL),
    Header = wxBoxSizer:new(?wxHORIZONTAL),
    Heading = wxBoxSizer:new(?wxVERTICAL),
    wxSizer:add(Heading, title(Content, "Swarm chat", 20)),
    Summary = wxStaticText:new(Content, ?wxID_ANY, "1 node"),
    wxSizer:add(Heading, Summary, [{flag, ?wxTOP}, {border, 6}]),
    wxSizer:add(Header, Heading, [{proportion, 1}]),
    Connect = button(Content, "Connect", connect),
    wxSizer:add(Header, Connect),
    wxSizer:add(Column, Header, [{flag, ?wxEXPAND bor ?wxALL}, {border, 22}]),
    Conversation = wxScrolledWindow:new(Content),
    wxScrolledWindow:setScrollRate(Conversation, 0, 16),
    Messages = wxBoxSizer:new(?wxVERTICAL),
    wxScrolledWindow:setSizer(Conversation, Messages),
    add(Column, Conversation, 1, 12),
    Error = wxStaticText:new(Content, ?wxID_ANY, ""),
    wxStaticText:setForegroundColour(Error, {155,65,25}),
    add(Column, Error, 0, 12),
    Composer = wxBoxSizer:new(?wxHORIZONTAL),
    Draft = wxTextCtrl:new(Content, ?wxID_ANY,
        [{style, ?wxTE_PROCESS_ENTER}, {value, ""}]),
    wxTextCtrl:setToolTip(Draft, "Message the swarm (Enter to send)"),
    wxTextCtrl:connect(Draft, command_text_enter, [{userData, send}]),
    wxTextCtrl:connect(Draft, command_text_updated, [{userData, edit_draft}]),
    wxSizer:add(Composer, Draft, [{proportion, 1}, {flag, ?wxEXPAND bor ?wxRIGHT}, {border, 12}]),
    Send = button(Content, "Send", send),
    wxSizer:add(Composer, Send),
    wxSizer:add(Column, Composer, [{flag, ?wxEXPAND bor ?wxALL}, {border, 20}]),
    wxPanel:setSizer(Content, Column),
    wxSizer:add(Row, Content, [{proportion, 1}, {flag, ?wxEXPAND}]),
    wxPanel:setSizer(Root, Row),
    wxFrame:createStatusBar(Frame),
    wxFrame:connect(Frame, close_window),
    wxFrame:connect(Frame, size, [{skip, true}]),
    wxFrame:connect(Frame, move, [{skip, true}]),
    case maps:find(position, Saved) of
        {ok, Position} -> wxFrame:move(Frame, Position);
        error -> ok
    end,
    wxFrame:show(Frame),
    wxFrame:maximize(Frame, [{maximize, maps:get(maximized, Saved, false)}]),
    wxTextCtrl:changeValue(Draft, maps:get(draft, Saved, "")),
    wxTextCtrl:setFocus(Draft),
    self() ! refresh,
    State = #{frame => Frame, peers => Peers, summary => Summary,
              conversation => Conversation, messages => Messages, draft => Draft,
              error => Error, send => Send, connect => Connect, dialog => undefined,
              history => undefined, busy => false, node_names => []},
    Restored = case maps:get(dialog, Saved, false) of
        false -> State;
        true -> open_dialog(State)
    end,
    {Frame, Restored}.

handle_event(#wx{event = #wxClose{}, obj = Obj}, #{frame := Obj} = S) ->
    {stop, normal, S};
handle_event(#wx{event = #wxClose{}}, S) -> {noreply, close_dialog(S)};
handle_event(#wx{event = #wxSize{}}, S) ->
    remember_geometry(S),
    self() ! relayout,
    {noreply, S};
handle_event(#wx{event = #wxMove{}}, S) -> remember_geometry(S), {noreply, S};
handle_event(#wx{userData = edit_draft}, S) ->
    parvi_windows_model:put(#{draft => wxTextCtrl:getValue(maps:get(draft, S))}), {noreply, S};
handle_event(#wx{userData = {edit, Key}, obj = Ctrl}, S) ->
    parvi_windows_model:put(#{Key => wxTextCtrl:getValue(Ctrl)}), {noreply, S};
handle_event(#wx{userData = connect}, S) -> {noreply, open_dialog(S)};
handle_event(#wx{userData = cancel}, S) -> {noreply, close_dialog(S)};
handle_event(#wx{userData = copy_node_connection, event = #wxCommand{cmdString = Label}}, S) ->
    Selected = unicode:characters_to_binary(Label),
    LocalLabel = <<(atom_to_binary(node()))/binary, " (this node)">>,
    Name = case Selected of LocalLabel -> atom_to_binary(node()); _ -> Selected end,
    case lists:member(Name, maps:get(node_names, S)) of
        false -> {noreply, S};
        true ->
            Ref = make_ref(), Parent = self(),
            spawn(fun() ->
                Result = try
                    Node = binary_to_existing_atom(Name),
                    String = case Node =:= node() of
                        true -> parvi_connection:local();
                        false -> erpc:call(Node, parvi_connection, local, [], 2000)
                    end,
                    {ok, #{node := Name}} = parvi_connection:parse(String),
                    {ok, String}
                catch _:_ -> unavailable end,
                Parent ! {node_connection, Ref, Result}
            end),
            {noreply, S#{copy_ref => Ref}}
    end;
handle_event(#wx{userData = send}, S) ->
    Text = unicode:characters_to_binary(wxTextCtrl:getValue(maps:get(draft, S))),
    case string:trim(Text) of
        <<>> -> {noreply, S};
        _ -> {noreply, request(#{method => send, text => Text}, send, S)}
    end;
handle_event(#wx{userData = discover}, S) ->
    URL = value(broker_url, S),
    {noreply, request(#{method => discover, url => URL}, discover, S)};
handle_event(#wx{userData = join}, S) ->
    {noreply, request(#{method => connect, connection_string => value(connection_string, S)}, join, S)};
handle_event(_, S) -> {noreply, S}.

handle_info(refresh, S) ->
    erlang:send_after(600, self(), refresh),
    Model = parvi_windows_model:get(),
    Draft = maps:get(draft, S),
    Text = maps:get(draft, Model, ""),
    case wxTextCtrl:getValue(Draft) =:= Text of
        true -> ok;
        false -> wxTextCtrl:changeValue(Draft, Text)
    end,
    Current = case {maps:get(dialog, Model, false), maps:get(dialog, S)} of
        {false, D} when D =/= undefined -> close_dialog(S);
        _ -> S
    end,
    {noreply, request(#{method => snapshot}, snapshot, Current)};
handle_info(relayout, S) -> {noreply, render(maps:get(history, S), S)};
handle_info({node_connection, Ref, Result}, #{copy_ref := Ref} = S) ->
    case Result of
        {ok, String} ->
            Clipboard = wxClipboard:get(),
            case wxClipboard:open(Clipboard) of
                true ->
                    try
                        Data = wxTextDataObject:new([{text, String}]),
                        case wxClipboard:setData(Clipboard, Data) of
                            true ->
                                show_error("", S),
                                wxFrame:setStatusText(maps:get(frame, S), "Connection string copied.");
                            false -> show_error("Could not copy the connection string. Try again.", S)
                        end
                    after wxClipboard:close(Clipboard) end;
                false -> show_error("Clipboard is unavailable. Click the node to try again.", S)
            end;
        _ -> show_error("Could not get this node's connection string. Check the connection and restart older app instances.", S)
    end,
    {noreply, maps:remove(copy_ref, S)};
handle_info({reply, Ref, Kind, Result}, #{busy := Ref} = S0) ->
    S = busy(false, S0),
    case Result of
        #{<<"messages">> := History, <<"peers">> := Peers, <<"error">> := Error} ->
            Names = [atom_to_binary(node()) | Peers],
            case Names =:= maps:get(node_names, S) of
                true -> ok;
                false -> wxListBox:set(maps:get(peers, S), [[atom_to_list(node()), " (this node)"] | Peers])
            end,
            WithNodes = S#{node_names := Names},
            wxStaticText:setLabel(maps:get(summary, S),
                case length(Peers) of
                    0 -> "1 node";
                    N -> io_lib:format("~B nodes", [N + 1])
                end),
            wxFrame:setStatusText(maps:get(frame, S),
                [atom_to_list(node()), " | ", maps:get(<<"runtime_info">>, Result)]),
            case {Kind, Error} of
                {snapshot, null} -> ok;
                {_, null} -> show_error("", S);
                _ -> show_error(Error, S)
            end,
            S1 = case {Kind, Error} of
                {send, null} ->
                    wxTextCtrl:changeValue(maps:get(draft, S), ""),
                    wxTextCtrl:setFocus(maps:get(draft, S)), WithNodes;
                {join, null} -> close_dialog(WithNodes);
                _ -> WithNodes
            end,
            update_nodes(Result, S1),
            S2 = case History =:= maps:get(history, S1) of
                true -> S1;
                false -> render(History, S1)
            end,
            {noreply, S2};
        _ ->
            show_error("Erlang worker unavailable. Retrying...", S),
            {noreply, S}
    end;
handle_info(_, S) -> {noreply, S}.

request(_, snapshot, #{busy := Ref} = S) when Ref =/= false -> S;
request(Command, Kind, S) ->
    Ref = make_ref(),
    parvi_windows_model:request(Command, Kind, self(), Ref),
    case Kind of snapshot -> S#{busy := Ref}; _ -> busy(Ref, S) end.

busy(Ref, S) ->
    Enabled = Ref =:= false,
    [wxWindow:enable(maps:get(K, S), [{enable, Enabled}]) || K <- [send, draft]],
    case maps:get(dialog, S) of
        undefined -> ok;
        _ -> [wxWindow:enable(maps:get(K, S), [{enable, Enabled}]) || K <- [discover, join]]
    end,
    S#{busy := Ref}.

render(undefined, S) -> S;
render(History, S) ->
    Window = maps:get(conversation, S), Sizer = maps:get(messages, S),
    wxWindow:freeze(Window),
    try
        wxSizer:clear(Sizer, [{delete_windows, true}]),
        case History of
            [] ->
                add(Sizer, title(Window, "A small start for the swarm", 18), 0, 24),
                add(Sizer, wxStaticText:new(Window, ?wxID_ANY,
                    "Send your first message to the swarm."), 0, 24);
            _ -> [bubble(Window, Sizer, M) || M <- History]
        end,
        wxScrolledWindow:fitInside(Window),
        wxScrolledWindow:scroll(Window, 0, 1000000)
    after wxWindow:thaw(Window) end,
    S#{history := History}.

bubble(Parent, Sizer, #{<<"sender">> := Sender, <<"text">> := Text, <<"time">> := Time}) ->
    Mine = Sender =:= atom_to_binary(node()),
    Panel = wxPanel:new(Parent),
    wxPanel:setBackgroundColour(Panel, case Mine of true -> {219,241,238}; false -> {240,242,244} end),
    Column = wxBoxSizer:new(?wxVERTICAL),
    Label = case Mine of true -> <<Sender/binary, " (this node)">>; false -> Sender end,
    add(Column, wxStaticText:new(Panel, ?wxID_ANY, Label), 0, 8),
    Body = wxStaticText:new(Panel, ?wxID_ANY, binary:replace(Text, <<"&">>, <<"&&">>, [global])),
    {Width, _} = wxWindow:getClientSize(Parent),
    wxStaticText:wrap(Body, max(160, Width - 130)),
    add(Column, Body, 0, 8),
    {{_,_,_},{H,M,_}} = calendar:system_time_to_local_time(Time, millisecond),
    add(Column, wxStaticText:new(Panel, ?wxID_ANY, io_lib:format("~2..0B:~2..0B", [H,M])), 0, 8),
    wxPanel:setSizerAndFit(Panel, Column),
    Align = case Mine of true -> ?wxALIGN_RIGHT; false -> ?wxALIGN_LEFT end,
    wxSizer:add(Sizer, Panel, [{flag, Align bor ?wxALL}, {border, 8}]).

open_dialog(#{dialog := D} = S) when D =/= undefined -> wxDialog:raise(D), S;
open_dialog(S) ->
    Model = parvi_windows_model:get(),
    parvi_windows_model:put(#{dialog => true}),
    D = wxDialog:new(maps:get(frame, S), ?wxID_ANY, "Connect a Parvi instance",
        [{size, {610, 610}}, {style, ?wxDEFAULT_DIALOG_STYLE bor ?wxRESIZE_BORDER}]),
    Column = wxBoxSizer:new(?wxVERTICAL),
    add(Column, wxStaticText:new(D, ?wxID_ANY,
        "Copy a connection string here and paste it into the other instance."), 0, 12),
    OwnConnection = parvi_connection:local(),
    field(D, Column, "This instance's connection string", OwnConnection, ?wxTE_READONLY),
    Connection = field(D, Column, "Other instance's connection string", maps:get(connection, Model, ""), 0),
    wxTextCtrl:connect(Connection, command_text_updated, [{userData, {edit, connection}}]),
    add(Column, wxStaticText:new(D, ?wxID_ANY,
        "The string includes the address and private session credentials.\nThis build connects instances on this Windows PC only."), 0, 12),
    DialogError = wxStaticText:new(D, ?wxID_ANY, ""),
    wxStaticText:setForegroundColour(DialogError, {155,65,25}),
    add(Column, DialogError, 0, 8),
    add(Column, title(D, "Reception desk", 14), 0, 12),
    URL = field(D, Column, "Reception desk URL", maps:get(url, Model, "http://127.0.0.1:8765"), 0),
    wxTextCtrl:connect(URL, command_text_updated, [{userData, {edit, url}}]),
    Discover = button(D, "Register / Find nodes", discover),
    add(Column, Discover, 0, 12),
    Nodes = wxListBox:new(D, ?wxID_ANY),
    add(Column, Nodes, 1, 12),
    add(Column, wxStaticText:new(D, ?wxID_ANY,
        "Optional discovery lists names only. To connect, ask the other\ninstance for its connection string."), 0, 12),
    Actions = wxBoxSizer:new(?wxHORIZONTAL),
    Join = button(D, "Connect", join),
    wxSizer:add(Actions, button(D, "Close", cancel)),
    wxSizer:add(Actions, Join, [{flag, ?wxLEFT}, {border, 12}]),
    wxSizer:add(Column, Actions, [{flag, ?wxALL bor ?wxALIGN_RIGHT}, {border, 12}]),
    wxDialog:setSizer(D, Column),
    wxDialog:connect(D, close_window),
    wxDialog:show(D),
    busy(maps:get(busy, S), S#{dialog := D, broker_url => URL, connection_string => Connection,
        dialog_error => DialogError, known_nodes => Nodes, discover => Discover, join => Join}).

close_dialog(#{dialog := undefined} = S) -> S;
close_dialog(#{dialog := D} = S) ->
    parvi_windows_model:put(#{dialog => false}), wxDialog:destroy(D), S#{dialog := undefined}.

update_nodes(Reply, #{dialog := D, known_nodes := List}) when D =/= undefined ->
    Nodes = maps:get(<<"known_nodes">>, Reply, []),
    Current = [wxListBox:getString(List, I) || I <- lists:seq(0, wxListBox:getCount(List)-1)],
    case [unicode:characters_to_binary(N) || N <- Current] =:= Nodes of
        true -> ok;
        false -> wxListBox:set(List, Nodes)
    end;
update_nodes(_, _) -> ok.

value(Key, S) -> string:trim(unicode:characters_to_binary(wxTextCtrl:getValue(maps:get(Key, S)))).
show_error(Text, S) ->
    wxStaticText:setLabel(maps:get(error, S), Text),
    case maps:get(dialog, S) of
        undefined -> ok;
        D ->
            Label = maps:get(dialog_error, S),
            wxStaticText:setLabel(Label, Text),
            wxStaticText:wrap(Label, 540),
            wxDialog:layout(D)
    end.
field(D, Sizer, Label, Value, Style) ->
    add(Sizer, wxStaticText:new(D, ?wxID_ANY, Label), 0, 4),
    Ctrl = wxTextCtrl:new(D, ?wxID_ANY, [{value, Value}, {style, Style}]),
    add(Sizer, Ctrl, 0, 6), Ctrl.
button(Parent, Label, Action) ->
    B = wxButton:new(Parent, ?wxID_ANY, [{label, Label}]),
    wxButton:connect(B, command_button_clicked, [{userData, Action}]), B.
title(Parent, Text, Size) ->
    T = wxStaticText:new(Parent, ?wxID_ANY, Text),
    Font = wxFont:new(Size, ?wxFONTFAMILY_DEFAULT, ?wxFONTSTYLE_NORMAL, ?wxFONTWEIGHT_BOLD),
    wxStaticText:setFont(T, Font), wxFont:destroy(Font), T.
add(Sizer, Item, Proportion, Border) ->
    wxSizer:add(Sizer, Item, [{proportion, Proportion}, {flag, ?wxEXPAND bor ?wxALL}, {border, Border}]).
remember_geometry(S) ->
    Frame = maps:get(frame, S),
    parvi_windows_model:put(#{position => wxFrame:getPosition(Frame),
        size => wxFrame:getSize(Frame), maximized => wxFrame:isMaximized(Frame)}).
handle_call(_, _, S) -> {reply, {error, unsupported}, S}.
handle_cast(_, S) -> {noreply, S}.
terminate(_, S) -> wxFrame:destroy(maps:get(frame, S)), wx:destroy(), ok.
code_change(_, S, _) -> {ok, S}.
