%% Native swarm UI; memberships, invitations and histories belong to control/.
-module(parvi_windows).
-behaviour(wx_object).
-include_lib("wx/include/wx.hrl").
-export([main/0, start/0, start_link/0, init/1, handle_event/2, handle_info/2,
         handle_call/3, handle_cast/2, terminate/2, code_change/3]).

main() -> parvi_windows_host:main().
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
        [{size, maps:get(size, Saved, {1120, 820})}]),
    wxFrame:setMinSize(Frame, {940, 700}),
    Root = wxPanel:new(Frame), Row = wxBoxSizer:new(?wxHORIZONTAL),
    Sidebar = wxPanel:new(Root, [{size, {270, -1}}]),
    wxPanel:setBackgroundColour(Sidebar, {241,245,245}),
    Side = wxBoxSizer:new(?wxVERTICAL),
    add(Side, title(Sidebar, "Parvi", 24), 0, 20),
    add(Side, title(Sidebar, "Swarms", 14), 0, 12),
    Swarms = wxListBox:new(Sidebar, ?wxID_ANY),
    wxListBox:connect(Swarms, command_listbox_selected, [{userData, select_swarm}]),
    add(Side, Swarms, 1, 12),
    Create = button(Sidebar, "New swarm", create), add(Side, Create, 0, 12),
    add(Side, title(Sidebar, "Add a swarm", 13), 0, 12),
    Hint = wxStaticText:new(Sidebar, ?wxID_ANY, "Paste an invitation from a swarm member."),
    wxStaticText:wrap(Hint, 235), add(Side, Hint, 0, 8),
    Incoming = wxTextCtrl:new(Sidebar, ?wxID_ANY, [{style, ?wxTE_PROCESS_ENTER}]),
    wxTextCtrl:setToolTip(Incoming, "Swarm invitation to add"),
    wxTextCtrl:connect(Incoming, command_text_updated, [{userData, edit_incoming}]),
    wxTextCtrl:connect(Incoming, command_text_enter, [{userData, join}]),
    add(Side, Incoming, 0, 12),
    Join = button(Sidebar, "Add swarm", join), add(Side, Join, 0, 12),
    DeskLabel = wxStaticText:new(Sidebar, ?wxID_ANY, "Reception desk URL"),
    add(Side, DeskLabel, 0, 8),
    Desk = wxTextCtrl:new(Sidebar, ?wxID_ANY),
    wxTextCtrl:setToolTip(Desk, "wss://your-desk/relay/v1"),
    wxTextCtrl:connect(Desk, command_text_updated, [{userData, edit_desk}]),
    add(Side, Desk, 0, 8),
    Configure = button(Sidebar, "Use desk (new session)", configure), add(Side, Configure, 0, 8),
    Local = wxStaticText:new(Sidebar, ?wxID_ANY, "Starting node..."), add(Side, Local, 0, 16),
    wxPanel:setSizer(Sidebar, Side), wxSizer:add(Row, Sidebar, [{flag, ?wxEXPAND}]),
    Content = wxPanel:new(Root), wxPanel:setBackgroundColour(Content, {255,255,255}),
    Column = wxBoxSizer:new(?wxVERTICAL), InputRow = wxBoxSizer:new(?wxHORIZONTAL),
    wxSizer:add(InputRow, title(Content, "Audio input - Windows output", 14), [{proportion, 1}]),
    InputButton = button(Content, "Start input", audio_input), wxSizer:add(InputRow, InputButton),
    add(Column, InputRow, 0, 12),
    InputLevel = wxGauge:new(Content, ?wxID_ANY, 96, [{size, {-1, 12}}]),
    add(Column, InputLevel, 0, 8),
    InputInfo = wxStaticText:new(Content, ?wxID_ANY, "Input stopped. Captures the current default output; no virtual device is installed."),
    add(Column, InputInfo, 0, 12),
    Header = wxBoxSizer:new(?wxHORIZONTAL),
    Heading = title(Content, "Choose a swarm", 20),
    wxSizer:add(Header, Heading, [{proportion, 1}, {flag, ?wxALIGN_CENTER_VERTICAL}]),
    Leave = button(Content, "Leave swarm", leave), wxSizer:add(Header, Leave),
    add(Column, Header, 0, 20),
    Summary = wxStaticText:new(Content, ?wxID_ANY, "Create a swarm or add one with an invitation."),
    add(Column, Summary, 0, 12),
    InvitationLabel = wxStaticText:new(Content, ?wxID_ANY, "Invitation to this swarm"),
    add(Column, InvitationLabel, 0, 8),
    Invitation = wxTextCtrl:new(Content, ?wxID_ANY, [{style, ?wxTE_READONLY}]),
    wxTextCtrl:setToolTip(Invitation, "Select and copy with Ctrl+A, Ctrl+C. Contains private session credentials."),
    add(Column, Invitation, 0, 12),
    Notebook = wxNotebook:new(Content, ?wxID_ANY),
    Network = wxPanel:new(Notebook), NetworkSizer = wxBoxSizer:new(?wxVERTICAL),
    Canvas = wxPanel:new(Network),
    true = code:soft_purge(parvi_fgraph_win),
    {module, parvi_fgraph_win} = code:load_file(parvi_fgraph_win),
    Graph = parvi_graph_view:new(Canvas),
    add(NetworkSizer, Canvas, 1, 4),
    Peers = wxListCtrl:new(Network, [{style, ?wxLC_REPORT bor ?wxLC_SINGLE_SEL}, {size, {-1, 125}}]),
    wxListCtrl:insertColumn(Peers, 0, "Status", [{width, 140}]),
    wxListCtrl:insertColumn(Peers, 1, "Node", [{width, 430}]),
    wxListCtrl:assignImageList(Peers, status_lights(), ?wxIMAGE_LIST_SMALL),
    wxListCtrl:connect(Peers, command_list_item_selected, [{userData, select_node}]),
    add(NetworkSizer, Peers, 0, 6),
    Details = wxStaticText:new(Network, ?wxID_ANY, "Select a node to see its identity."),
    add(NetworkSizer, Details, 0, 8),
    Remove = button(Network, "Remove both of us", remove), add(NetworkSizer, Remove, 0, 8),
    wxPanel:setSizer(Network, NetworkSizer),
    wxNotebook:addPage(Notebook, Network, "Graph"),
    Chat = wxPanel:new(Notebook), ChatSizer = wxBoxSizer:new(?wxVERTICAL),
    Conversation = wxScrolledWindow:new(Chat), wxScrolledWindow:setScrollRate(Conversation, 0, 16),
    Messages = wxBoxSizer:new(?wxVERTICAL), wxScrolledWindow:setSizer(Conversation, Messages),
    add(ChatSizer, Conversation, 1, 4),
    Composer = wxBoxSizer:new(?wxHORIZONTAL),
    Draft = wxTextCtrl:new(Chat, ?wxID_ANY, [{style, ?wxTE_PROCESS_ENTER}]),
    wxTextCtrl:setToolTip(Draft, "Message the current swarm (Enter to send)"),
    wxTextCtrl:connect(Draft, command_text_enter, [{userData, send}]),
    wxTextCtrl:connect(Draft, command_text_updated, [{userData, edit_draft}]),
    wxSizer:add(Composer, Draft, [{proportion, 1}, {flag, ?wxEXPAND bor ?wxRIGHT}, {border, 12}]),
    Send = button(Chat, "Send", send), wxSizer:add(Composer, Send),
    add(ChatSizer, Composer, 0, 12), wxPanel:setSizer(Chat, ChatSizer),
    wxNotebook:addPage(Notebook, Chat, "Chat"),
    wxNotebook:connect(Notebook, command_notebook_page_changed, [{userData, change_view}]),
    add(Column, Notebook, 1, 12),
    Error = wxStaticText:new(Content, ?wxID_ANY, ""),
    wxStaticText:setForegroundColour(Error, {155,65,25}), add(Column, Error, 0, 12),
    wxPanel:setSizer(Content, Column),
    wxSizer:add(Row, Content, [{proportion, 1}, {flag, ?wxEXPAND}]), wxPanel:setSizer(Root, Row),
    wxFrame:createStatusBar(Frame),
    wxFrame:connect(Frame, close_window), wxFrame:connect(Frame, size, [{skip, true}]),
    wxFrame:connect(Frame, move, [{skip, true}]),
    case maps:find(position, Saved) of {ok, Position} -> wxFrame:move(Frame, Position); error -> ok end,
    S = #{frame => Frame, content => Content, swarms => Swarms, create => Create, join => Join,
          input_button => InputButton, input_level => InputLevel, input_info => InputInfo,
          incoming => Incoming, desk_label => DeskLabel, desk => Desk, configure => Configure, local => Local, heading => Heading, leave => Leave,
          summary => Summary, invitation => Invitation, invitation_label => InvitationLabel,
          notebook => Notebook, graph => Graph, peers => Peers, details => Details, remove => Remove,
          conversation => Conversation, messages => Messages, draft => Draft, send => Send, error => Error,
          history => undefined, selected => undefined, selected_node => undefined,
          node_names => [], node_rows => [], swarm_rows => []},
    Ready = sync(Saved, S),
    wxFrame:show(Frame), wxFrame:maximize(Frame, [{maximize, maps:get(maximized, Saved, false)}]),
    self() ! refresh, self() ! audio_refresh, {Frame, Ready}.

handle_event(#wx{event = #wxClose{}}, S) -> {stop, normal, S};
handle_event(#wx{event = #wxSize{}}, S) -> remember_geometry(S), self() ! relayout, {noreply, S};
handle_event(#wx{event = #wxMove{}}, S) -> remember_geometry(S), {noreply, S};
handle_event(#wx{userData = audio_input}, S) ->
    case parvi_windows_audio:status() of
        #{state := State} when State =:= running; State =:= starting -> parvi_windows_audio:stop();
        _ -> parvi_windows_audio:start()
    end,
    {noreply, S};
handle_event(#wx{userData = edit_draft}, S) ->
    Model = parvi_windows_model:get(),
    case maps:get(selected, S) of
        undefined -> ok;
        Id -> parvi_windows_model:put(#{drafts => (maps:get(drafts, Model))#{Id => wxTextCtrl:getValue(maps:get(draft, S))}})
    end,
    {noreply, sync(parvi_windows_model:get(), S)};
handle_event(#wx{userData = edit_desk}, S) ->
    parvi_windows_model:put(#{desk => wxTextCtrl:getValue(maps:get(desk, S))}),
    {noreply, S};
handle_event(#wx{userData = configure}, S) ->
    D = wxMessageDialog:new(maps:get(frame, S),
        "Use this desk for a new node session? Current transient swarm memberships and chats will be discarded.",
        [{caption, "Change Reception desk"}, {style, ?wxYES_NO bor ?wxNO_DEFAULT bor ?wxICON_QUESTION}]),
    Answer = wxMessageDialog:showModal(D), wxMessageDialog:destroy(D),
    case Answer of
        ?wxID_YES -> action(#{method => configure_desk, url => string:trim(unicode:characters_to_binary(wxTextCtrl:getValue(maps:get(desk, S))))}, configure, S);
        _ -> {noreply, S}
    end;
handle_event(#wx{userData = edit_incoming}, S) ->
    parvi_windows_model:put(#{incoming => wxTextCtrl:getValue(maps:get(incoming, S))}),
    {noreply, sync(parvi_windows_model:get(), S)};
handle_event(#wx{userData = select_swarm}, S) ->
    Index = wxListBox:getSelection(maps:get(swarms, S)),
    case Index >= 0 andalso Index < length(maps:get(swarm_rows, S)) of
        true ->
            {Id, _} = lists:nth(Index + 1, maps:get(swarm_rows, S)),
            parvi_windows_model:put(#{selected => Id, view => 0});
        false -> ok
    end,
    {noreply, sync(parvi_windows_model:get(), S)};
handle_event(#wx{userData = change_view}, S) ->
    parvi_windows_model:put(#{view => wxNotebook:getSelection(maps:get(notebook, S))}),
    {noreply, sync(parvi_windows_model:get(), S)};
handle_event(#wx{userData = select_node, event = #wxList{itemIndex = Index}}, S) ->
    Rows = maps:get(node_rows, S),
    case Index >= 0 andalso Index < length(Rows) of
        true -> {Name, _, _} = lists:nth(Index + 1, Rows), {noreply, sync(parvi_windows_model:get(), S#{selected_node := Name})};
        false -> {noreply, S}
    end;
handle_event(#wx{userData = create}, S) -> action(#{method => create_swarm}, create, S);
handle_event(#wx{userData = join}, S) ->
    Text = string:trim(unicode:characters_to_binary(wxTextCtrl:getValue(maps:get(incoming, S)))),
    case Text of <<>> -> {noreply, S}; _ -> action(#{method => join_swarm, invitation => Text}, join, S) end;
handle_event(#wx{userData = send}, #{selected := Id} = S) when Id =/= undefined ->
    Text = unicode:characters_to_binary(wxTextCtrl:getValue(maps:get(draft, S))),
    case string:trim(Text) of
        <<>> -> {noreply, S};
        _ -> action(#{method => send_swarm, swarm_id => Id, text => Text}, send, S)
    end;
handle_event(#wx{userData = leave}, #{selected := Id} = S) when Id =/= undefined ->
    action(#{method => leave_swarm, swarm_id => Id}, leave, S);
handle_event(#wx{userData = remove}, #{selected := Id, selected_node := Target} = S)
        when Id =/= undefined, Target =/= undefined ->
    D = wxMessageDialog:new(maps:get(frame, S),
        case native(parvi_windows_model:get()) of
            true -> "Both nodes will lose access to the entire native cluster, including other logical swarms. Their invitations will expire.";
            false -> "Both nodes will leave this swarm and their entry invitations will expire. Other swarms are unaffected."
        end,
        [{caption, "Remove both of us?"}, {style, ?wxYES_NO bor ?wxNO_DEFAULT bor ?wxICON_QUESTION}]),
    Answer = wxMessageDialog:showModal(D), wxMessageDialog:destroy(D),
    case Answer of ?wxID_YES -> action(#{method => remove_both, swarm_id => Id, target => Target}, remove, S); _ -> {noreply, S} end;
handle_event(_, S) -> {noreply, S}.

handle_info(audio_refresh, S) ->
    erlang:send_after(100, self(), audio_refresh),
    Audio = parvi_windows_audio:status(), State = maps:get(state, Audio),
    wxButton:setLabel(maps:get(input_button, S), case State of
        running -> "Stop input"; starting -> "Stop input"; _ -> "Start input"
    end),
    {Level, Info} = case Audio of
        #{state := running, meter := M} ->
            Peak = maps:get(<<"peak_db">>, M),
            {round(max(0, min(96, Peak + 96))), io_lib:format("~ts~nPeak ~.1f dBFS | RMS ~.1f dBFS | ~B Hz / ~B ch | ~B frames",
                [maps:get(<<"source">>, M), Peak, maps:get(<<"rms_db">>, M), maps:get(<<"rate">>, M),
                 maps:get(<<"channels">>, M), maps:get(<<"frames">>, M)])};
        #{state := error, error := Error} -> {0, Error};
        #{state := starting} -> {0, "Opening Windows default output (loopback)..."};
        _ -> {0, "Input stopped. Captures the current default output; no virtual device is installed."}
    end,
    wxGauge:setValue(maps:get(input_level, S), Level),
    wxStaticText:setLabel(maps:get(input_info, S), Info),
    {noreply, S};
handle_info(refresh, S) ->
    erlang:send_after(600, self(), refresh),
    parvi_windows_model:request(#{method => snapshot}, snapshot, self(), make_ref()),
    {noreply, sync(parvi_windows_model:get(), S)};
handle_info({reply, _, _, _}, S) -> {noreply, sync(parvi_windows_model:get(), S)};
handle_info(relayout, S) -> {noreply, render(maps:get(history, S), S)};
handle_info({graph_node, Node}, S) ->
    Name = case Node of N when is_atom(N) -> atom_to_binary(N); N -> N end,
    case lists:keymember(Name, 1, maps:get(node_rows, S)) of
        true -> {noreply, sync(parvi_windows_model:get(), S#{selected_node := Name})};
        false -> {noreply, S}
    end;
handle_info(_, S) -> {noreply, S}.

action(Command, Kind, S) ->
    Model = parvi_windows_model:get(),
    case active_request(Model) of
        true -> {noreply, S};
        false ->
            parvi_windows_model:request(Command, Kind, self(), make_ref()),
            {noreply, sync(parvi_windows_model:get(), S)}
    end.
active_request(#{pending := Pending}) ->
    lists:any(fun(#{kind := Kind}) -> Kind =/= snapshot end, maps:values(Pending)).

sync(Model, S0) ->
    Snapshot = maps:get(snapshot, Model), Swarms = maps:get(<<"swarms">>, Snapshot, []),
    Native = native(Model),
    Id = maps:get(selected, Model), Active = Id =/= undefined,
    Changed = Id =/= maps:get(selected, S0),
    S = case Changed of true -> S0#{selected := Id, selected_node := undefined, history := undefined}; false -> S0 end,
    Rows = [{maps:get(<<"id">>, Swarm),
             unicode:characters_to_binary([maps:get(<<"name">>, Swarm), "  (", count_label(length(maps:get(<<"members">>, Swarm)), "node"), ")"])} || Swarm <- Swarms],
    List = maps:get(swarms, S),
    case Rows =:= maps:get(swarm_rows, S) of
        true -> ok;
        false -> wxListBox:set(List, [Label || {_, Label} <- Rows])
    end,
    case [I || {I, {Key, _}} <- lists:zip(lists:seq(0, length(Rows)-1), Rows), Key =:= Id] of
        [Index] -> wxListBox:setSelection(List, Index);
        [] -> ok
    end,
    Current = parvi_windows_model:selected(Model),
    {Name, Members, Invitation, History} = case Current of
        undefined -> {<<"Choose a swarm">>, [], <<>>, []};
        _ -> {maps:get(<<"name">>, Current), maps:get(<<"members">>, Current),
              maps:get(<<"invitation">>, Current, null), maps:get(<<"messages">>, Current)}
    end,
    wxStaticText:setLabel(maps:get(heading, S), Name),
    wxStaticText:setLabel(maps:get(summary, S), case Active of
        true -> [count_label(length(Members), "node"), " in this swarm",
            case Native of
                true -> "\nNative OTP over WebRTC. Invitations grant whole-VM trust.";
                false -> case maps:get(<<"url">>, maps:get(<<"relay">>, Snapshot, #{}), null) of
                    null -> ""; _ -> "\nRelayed through the Reception desk; direct peer links are not shown."
                end
            end];
        false when Native -> "Create a native cluster or paste a native invitation. One cluster per session; restart to switch.";
        false -> "Create a swarm or add one with an invitation. This node is still running."
    end),
    change_text(maps:get(invitation, S), case Invitation of null -> <<>>; _ -> Invitation end),
    change_text(maps:get(incoming, S), maps:get(incoming, Model)),
    change_text(maps:get(desk, S), maps:get(desk, Model, "")),
    change_text(maps:get(draft, S), parvi_windows_model:draft(Model)),
    [wxWindow:show(maps:get(K, S), [{show, Active}]) || K <- [invitation, invitation_label, notebook, leave]],
    [wxWindow:show(maps:get(K, S), [{show, not Native}]) || K <- [desk_label, desk, configure]],
    Tab = maps:get(view, Model),
    wxNotebook:changeSelection(maps:get(notebook, S), Tab),
    parvi_graph_view:pause(maps:get(graph, S), not Active orelse Tab =/= 0),
    %% Reset positions when the selected swarm changes, even if memberships overlap.
    G0 = case Changed of true -> parvi_graph_view:update(#{nodes => [], edges => []}, maps:get(graph, S)); false -> maps:get(graph, S) end,
    Network = parvi_windows_model:network(Model),
    Graph = parvi_graph_view:update(Network, G0),
    WithNodes = update_node_rows(maps:get(nodes, Network), S#{graph := Graph, swarm_rows := Rows}),
    SelectedNode = maps:get(selected_node, WithNodes),
    HasNode = lists:member(SelectedNode, Members),
    wxStaticText:setLabel(maps:get(details, S), case HasNode of true -> SelectedNode; false -> "Select a node to see its identity." end),
    Busy = active_request(Model),
    enable(configure, not Native andalso not Busy, S),
    enable(create, not Busy andalso not (Native andalso Active), S),
    enable(join, not Busy andalso not (Native andalso Active) andalso string:trim(maps:get(incoming, Model)) =/= "", S),
    enable(leave, not Native andalso Active andalso not Busy, S),
    wxWindow:setToolTip(maps:get(leave, S), case Native of
        true -> "Native voluntary leave is not implemented. Quit to disconnect; membership is not revoked.";
        false -> "Leave this swarm. Other memberships stay intact."
    end),
    enable(remove, HasNode andalso SelectedNode =/= identity_name() andalso not Busy, S),
    enable(send, Active andalso not Busy andalso string:trim(parvi_windows_model:draft(Model)) =/= "", S),
    enable(draft, Active, S),
    wxStaticText:setLabel(maps:get(error, S), case maps:get(error, Model) of
        "" -> maps:get(notice, Model, ""); ErrorText -> ErrorText
    end),
    wxStaticText:wrap(maps:get(error, S), 600),
    Relay = maps:get(<<"relay">>, Snapshot, #{}),
    DeskStatus = case maps:get(<<"url">>, Relay, null) of
        null -> "Local distribution";
        _ -> case maps:get(<<"connected">>, Relay, false) of true -> "Reception desk connected"; false -> "Reception desk reconnecting" end
    end,
    wxStaticText:setLabel(maps:get(local, S), [DeskStatus, "\n", count_label(length(Swarms), "swarm")]),
    wxFrame:setStatusText(maps:get(frame, S), [atom_to_list(node()), " | ", maps:get(<<"runtime_info">>, Snapshot, <<>>)]),
    wxPanel:layout(maps:get(content, S)),
    case Changed orelse History =/= maps:get(history, WithNodes) of true -> render(History, WithNodes); false -> WithNodes end.

native(Model) -> maps:get(<<"native_cluster">>, maps:get(snapshot, Model), false).
identity_name() ->
    case application:get_env(parvi, runtime_profile, legacy_apps) of
        native_cluster -> atom_to_binary(node());
        legacy_apps -> case parvi_relay:id() of N when is_atom(N) -> atom_to_binary(N); N -> N end
    end.

count_label(N, Name) -> io_lib:format("~B ~s~s", [N, Name, case N of 1 -> ""; _ -> "s" end]).

enable(Key, Enabled, S) -> wxWindow:enable(maps:get(Key, S), [{enable, Enabled}]).
change_text(Ctrl, Text) ->
    case unicode:characters_to_binary(wxTextCtrl:getValue(Ctrl)) =:= unicode:characters_to_binary(Text) of
        true -> ok; false -> wxTextCtrl:changeValue(Ctrl, Text)
    end.

update_node_rows(Rows, S) ->
    List = maps:get(peers, S), Names = [N || {N, _, _} <- Rows],
    case Names =:= maps:get(node_names, S) of
        true -> ok;
        false ->
            wxListCtrl:deleteAllItems(List),
            [wxListCtrl:insertItem(List, I, "", 3) || I <- lists:seq(0, length(Rows)-1)]
    end,
    [begin
        {Image, Text} = case Status of
            running -> {0, "Running"}; unresponsive -> {1, "Not responding"};
            down -> {2, "Disconnected"}; checking -> {3, "Checking"}
        end,
        wxListCtrl:setItem(List, I, 0, Text), wxListCtrl:setItemImage(List, I, Image),
        Label = case Name =:= identity_name() of true -> <<Name/binary, " (this node)">>; false -> Name end,
        wxListCtrl:setItem(List, I, 1, Label)
    end || {I, {Name, Status, _}} <- lists:zip(lists:seq(0, length(Rows)-1), Rows)],
    S#{node_names := Names, node_rows := Rows}.

%% RabbitMQ Management v3.13.7's existing status palette (green/yellow/red/grey).
status_lights() ->
    Images = wxImageList:new(16, 16),
    [begin
        Bitmap = wxBitmap:new(16, 16), DC = wxMemoryDC:new(Bitmap),
        Background = wxBrush:new({255,255,255}),
        Brush = wxBrush:new(Colour), Pen = wxPen:new({100,100,100}),
        wxDC:setBackground(DC, Background), wxDC:clear(DC),
        wxDC:setBrush(DC, Brush), wxDC:setPen(DC, Pen), wxDC:drawCircle(DC, {8,8}, 5),
        wxMemoryDC:destroy(DC), wxImageList:add(Images, Bitmap),
        wxBitmap:destroy(Bitmap), wxBrush:destroy(Background), wxBrush:destroy(Brush), wxPen:destroy(Pen)
    end || Colour <- [{152,248,152}, {255,255,123}, {255,122,122}, {221,221,221}]],
    Images.

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
    Mine = Sender =:= identity_name(),
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
terminate(_, S) ->
    parvi_graph_view:stop(maps:get(graph, S)),
    wxFrame:destroy(maps:get(frame, S)), wx:destroy(), ok.
code_change(_, S, _) -> {ok, S}.
