%% Native desktop adapter. All messaging and discovery remain in control/.
-module(parvi_windows).
-behaviour(wx_object).
-include_lib("wx/include/wx.hrl").
-export([main/0, start/0, init/1, handle_event/2, handle_info/2,
         handle_call/3, handle_cast/2, terminate/2, code_change/3]).

main() ->
    {ok, _} = application:ensure_all_started(crypto),
    Cookie = binary:encode_hex(crypto:strong_rand_bytes(24)),
    %% The launcher starts distribution with loopback binding and an ephemeral cookie.
    true = node() =/= nonode@nohost,
    erlang:set_cookie(binary_to_atom(Cookie)),
    {ok, _} = parvi:start(),
    Object = start(),
    Ref = monitor(process, wx_object:get_pid(Object)),
    receive {'DOWN', Ref, process, _, normal} -> init:stop();
            {'DOWN', Ref, process, _, _} -> init:stop(1)
    end.

start() -> wx_object:start(?MODULE, [], []).

init([]) ->
    wx:new(),
    Frame = wxFrame:new(wx:null(), ?wxID_ANY, "Parvi", [{size, {1020, 740}}]),
    wxFrame:setMinSize(Frame, {760, 560}),
    Root = wxPanel:new(Frame),
    Row = wxBoxSizer:new(?wxHORIZONTAL),
    Sidebar = wxPanel:new(Root, [{size, {230, -1}}]),
    wxPanel:setBackgroundColour(Sidebar, {241, 245, 245}),
    Side = wxBoxSizer:new(?wxVERTICAL),
    add(Side, title(Sidebar, "Parvi", 24), 0, 20),
    add(Side, wxStaticText:new(Sidebar, ?wxID_ANY, "Erlang running"), 0, 12),
    add(Side, wxStaticText:new(Sidebar, ?wxID_ANY, "DEVICES"), 0, 12),
    Peers = wxListBox:new(Sidebar, ?wxID_ANY),
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
    Summary = wxStaticText:new(Content, ?wxID_ANY, "1 device - This Windows PC"),
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
    wxFrame:show(Frame),
    wxTextCtrl:setFocus(Draft),
    self() ! refresh,
    {Frame, #{frame => Frame, peers => Peers, summary => Summary,
              conversation => Conversation, messages => Messages, draft => Draft,
              error => Error, send => Send, connect => Connect, dialog => undefined,
              history => undefined, busy => false}}.

handle_event(#wx{event = #wxClose{}, obj = Obj}, #{frame := Obj} = S) ->
    {stop, normal, S};
handle_event(#wx{event = #wxClose{}}, S) -> {noreply, close_dialog(S)};
handle_event(#wx{event = #wxSize{}}, S) ->
    self() ! relayout,
    {noreply, S};
handle_event(#wx{userData = connect}, S) -> {noreply, open_dialog(S)};
handle_event(#wx{userData = cancel}, S) -> {noreply, close_dialog(S)};
handle_event(#wx{userData = copy_node}, S) ->
    copy(atom_to_binary(node())), {noreply, S};
handle_event(#wx{userData = copy_cookie}, S) ->
    copy(atom_to_binary(erlang:get_cookie())), {noreply, S};
handle_event(#wx{userData = select_node, event = #wxCommand{cmdString = Name}}, S) ->
    wxTextCtrl:changeValue(maps:get(peer_name, S), Name), {noreply, S};
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
    {noreply, request(#{method => connect, node => value(peer_name, S),
                       cookie => value(peer_cookie, S)}, join, S)};
handle_event(_, S) -> {noreply, S}.

handle_info(refresh, S) ->
    erlang:send_after(600, self(), refresh),
    {noreply, request(#{method => snapshot}, snapshot, S)};
handle_info(relayout, S) -> {noreply, render(maps:get(history, S), S)};
handle_info(run_queued, #{queued := {Command, Kind}} = S) ->
    {noreply, request(Command, Kind, maps:remove(queued, S))};
handle_info({reply, Ref, Kind, Result}, #{busy := Ref} = S0) ->
    S = busy(false, S0),
    case maps:is_key(queued, S) of true -> self() ! run_queued; false -> ok end,
    case Result of
        #{<<"messages">> := History, <<"peers">> := Peers, <<"error">> := Error} ->
            wxListBox:set(maps:get(peers, S), ["This Windows PC" | Peers]),
            wxStaticText:setLabel(maps:get(summary, S),
                io_lib:format("~B device(s) - This Windows PC", [length(Peers) + 1])),
            wxFrame:setStatusText(maps:get(frame, S),
                [atom_to_list(node()), " | ", maps:get(<<"runtime_info">>, Result)]),
            case {Kind, Error} of
                {snapshot, null} -> ok;
                {_, null} -> wxStaticText:setLabel(maps:get(error, S), "");
                _ -> wxStaticText:setLabel(maps:get(error, S), Error)
            end,
            S1 = case {Kind, Error} of
                {send, null} ->
                    wxTextCtrl:changeValue(maps:get(draft, S), ""),
                    wxTextCtrl:setFocus(maps:get(draft, S)), S;
                {join, null} -> close_dialog(S);
                _ -> S
            end,
            update_nodes(Result, S1),
            S2 = case History =:= maps:get(history, S1) of
                true -> S1;
                false -> render(History, S1)
            end,
            {noreply, S2};
        _ ->
            wxStaticText:setLabel(maps:get(error, S), "Erlang worker unavailable. Retrying..."),
            {noreply, S}
    end;
handle_info(_, S) -> {noreply, S}.

request(_, snapshot, #{busy := Ref} = S) when Ref =/= false -> S;
request(Command, Kind, #{busy := Ref} = S) when Ref =/= false ->
    busy(Ref, S#{queued => {Command, Kind}});
request(Command, Kind, S) ->
    Parent = self(), Ref = make_ref(),
    spawn(fun() ->
        Reply = try json:decode(parvi_bridge:request(iolist_to_binary(json:encode(Command))))
                catch _:_ -> unavailable end,
        Parent ! {reply, Ref, Kind, Reply}
    end),
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
    Label = case Mine of true -> <<"This Windows PC">>; false -> Sender end,
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
    D = wxDialog:new(maps:get(frame, S), ?wxID_ANY, "Connect a Parvi instance",
        [{size, {610, 610}}, {style, ?wxDEFAULT_DIALOG_STYLE bor ?wxRESIZE_BORDER}]),
    Column = wxBoxSizer:new(?wxVERTICAL),
    add(Column, wxStaticText:new(D, ?wxID_ANY,
        "Connect instances on this Windows PC. Share the node and cookie separately."), 0, 12),
    add(Column, wxStaticText:new(D, ?wxID_ANY, atom_to_list(node())), 0, 12),
    Row = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(Row, button(D, "Copy node", copy_node)),
    wxSizer:add(Row, button(D, "Copy cookie", copy_cookie), [{flag, ?wxLEFT}, {border, 12}]),
    wxSizer:add(Column, Row, [{flag, ?wxALL}, {border, 12}]),
    add(Column, title(D, "Reception desk", 14), 0, 12),
    URL = field(D, Column, "Reception desk URL", "http://127.0.0.1:8765", 0),
    Discover = button(D, "Register / Find nodes", discover),
    add(Column, Discover, 0, 12),
    Nodes = wxListBox:new(D, ?wxID_ANY),
    wxListBox:connect(Nodes, command_listbox_selected, [{userData, select_node}]),
    add(Column, Nodes, 1, 12),
    Peer = field(D, Column, "Other instance's node name", "", 0),
    Cookie = field(D, Column, "Other instance's cookie", "", ?wxTE_PASSWORD),
    add(Column, wxStaticText:new(D, ?wxID_ANY,
        "Discovery introduces names; it does not connect devices.\nLAN and phone connections are not enabled in this build."), 0, 12),
    Actions = wxBoxSizer:new(?wxHORIZONTAL),
    Join = button(D, "Connect", join),
    wxSizer:add(Actions, button(D, "Close", cancel)),
    wxSizer:add(Actions, Join, [{flag, ?wxLEFT}, {border, 12}]),
    wxSizer:add(Column, Actions, [{flag, ?wxALL bor ?wxALIGN_RIGHT}, {border, 12}]),
    wxDialog:setSizer(D, Column),
    wxDialog:connect(D, close_window),
    wxDialog:show(D),
    busy(maps:get(busy, S), S#{dialog := D, broker_url => URL, peer_name => Peer,
        peer_cookie => Cookie, known_nodes => Nodes, discover => Discover, join => Join}).

close_dialog(#{dialog := undefined} = S) -> S;
close_dialog(#{dialog := D} = S) -> wxDialog:destroy(D), S#{dialog := undefined}.

update_nodes(Reply, #{dialog := D, known_nodes := List}) when D =/= undefined ->
    Nodes = maps:get(<<"known_nodes">>, Reply, []),
    Current = [wxListBox:getString(List, I) || I <- lists:seq(0, wxListBox:getCount(List)-1)],
    case [unicode:characters_to_binary(N) || N <- Current] =:= Nodes of
        true -> ok;
        false -> wxListBox:set(List, Nodes)
    end;
update_nodes(_, _) -> ok.

value(Key, S) -> string:trim(unicode:characters_to_binary(wxTextCtrl:getValue(maps:get(Key, S)))).
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
copy(Text) ->
    Clipboard = wxClipboard:get(),
    case wxClipboard:open(Clipboard) of
        true ->
            Data = wxTextDataObject:new([{text, Text}]),
            wxClipboard:setData(Clipboard, Data), wxClipboard:close(Clipboard);
        false -> ok
    end.
handle_call(_, _, S) -> {reply, {error, unsupported}, S}.
handle_cast(_, S) -> {noreply, S}.
terminate(_, S) -> wxFrame:destroy(maps:get(frame, S)), wx:destroy(), ok.
code_change(_, S, _) -> {ok, S}.
