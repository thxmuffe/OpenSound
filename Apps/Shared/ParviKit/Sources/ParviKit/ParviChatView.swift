import SwiftUI
#if os(macOS)
import AppKit
#endif

// Explicit wrapper alias avoids the newer State macro in command-line SDKs.
typealias ViewState<Value> = SwiftUI.State<Value>

private enum Destination: String, CaseIterable {
    case chat = "Chat", graph = "Graph"
    var symbol: String { self == .chat ? "bubble.left.and.bubble.right" : "point.3.connected.trianglepath.dotted" }
}

public struct ParviChatView: View {
    @ObservedObject private var model: ChatModel
    @ViewState<Destination> private var destination = .chat
    @ViewState<Bool> private var showingDiagnostics = false
    @ViewState<Bool> private var showingList = true
    @ViewState<Bool> private var confirmingDesk = false
    #if os(iOS)
    @ViewState<[String]> private var phonePath = []
    @ViewState<String> private var invitationFieldText = ""
    #endif
    @FocusState private var composerFocused: Bool

    public init(model: ChatModel) { self.model = model }

    public var body: some View {
        #if os(iOS)
        phoneNavigation
        #else
        desktopNavigation
        #endif
    }

    private var desktopNavigation: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900
            HStack(spacing: 0) {
                if wide { swarmList.frame(width: 280); Divider() }
                if !wide && showingList { swarmList.frame(maxWidth: .infinity) }
                else { swarmDetail(wide: wide) }
            }.tint(.teal)
            .onChange(of: model.selectedSwarmID) { _, id in
                destination = .chat
                if id != nil { showingList = false }
            }
        }
    }

    #if os(iOS)
    private var phoneNavigation: some View {
        NavigationStack(path: $phonePath) {
            swarmList
                .navigationTitle("Swarms")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { _ in
                    swarmDetail(wide: false)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar(.visible, for: .navigationBar)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Label("Parvi", systemImage: "waveform.path")
                                    .font(.headline).foregroundStyle(.teal)
                            }
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { composerFocused = false }
                            }
                        }
                }
        }
        .tint(.teal)
        .onChange(of: model.creating) { wasCreating, creating in
            if wasCreating && !creating && model.joinError == nil { openSelectedSwarm() }
        }
        .onChange(of: model.joining) { wasJoining, joining in
            if wasJoining && !joining && model.joinError == nil { openSelectedSwarm() }
        }
        .onChange(of: model.swarms.map(\.id)) { _, ids in
            if let current = phonePath.last, !ids.contains(current) {
                composerFocused = false
                phonePath = []
            }
        }
        .onChange(of: destination) { _, tab in
            if tab != .chat { composerFocused = false }
        }
        .sheet(isPresented: $showingDiagnostics) {
            NavigationStack {
                runtimeDetails.padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .navigationTitle("This node")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingDiagnostics = false }
                    } }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func openSelectedSwarm() {
        if let id = model.selectedSwarmID { openSwarm(id) }
    }
    #endif

    private func openSwarm(_ id: String) {
        composerFocused = false
        model.selectedSwarmID = id
        destination = .chat
        #if os(iOS)
        phonePath = [id]
        #else
        showingList = false
        #endif
    }

    private func swarmDetail(wide: Bool) -> some View {
        VStack(spacing: 0) {
            if let swarm = model.selectedSwarm {
                swarmHeader(swarm, wide: wide)
                if showInvitation {
                    invitationCard.padding(.horizontal, 20).padding(.bottom, 16)
                }
                Picker("Swarm view", selection: $destination) {
                    ForEach(Destination.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
                    }
                }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 20).padding(.bottom, 14)
                Divider()
                swarmPages.id(swarm.id).frame(maxWidth: .infinity, maxHeight: .infinity)
                if destination == .chat { Divider(); composer }
            } else {
                Spacer()
                Image(systemName: "circle.hexagongrid").font(.system(size: 40, weight: .light)).foregroundStyle(.teal)
                Text("Choose a swarm").font(.title3.weight(.semibold)).padding(.top, 12)
                Text("Create one, or add one with an invitation.").foregroundStyle(.secondary).font(.callout).padding(.top, 4)
                Button("New swarm", action: model.createSwarm).buttonStyle(.borderedProminent).padding(.top, 16)
                    .disabled(!model.running || model.creating)
                Spacer()
            }
            if let error = model.error { errorBanner(error) }
            footer
        }.background(Color.parviBackground)
    }

    private var showInvitation: Bool {
        #if os(iOS)
        !composerFocused
        #else
        true
        #endif
    }

    @ViewBuilder private var swarmPages: some View {
        #if os(iOS)
        TabView(selection: $destination) {
            conversation.tag(Destination.chat)
            ParviNetworkView(model: model).tag(Destination.graph)
        }.tabViewStyle(.page(indexDisplayMode: .never))
        #else
        switch destination {
        case .chat: conversation
        case .graph: ParviNetworkView(model: model)
        }
        #endif
    }

    private func swarmHeader(_ swarm: SwarmSnapshot, wide: Bool) -> some View {
        HStack(spacing: 12) {
            #if os(macOS)
            if !wide {
                Button { showingList = true } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).accessibilityLabel("Show swarm list")
            }
            #endif
            VStack(alignment: .leading, spacing: 4) {
                Text(swarm.name).font(.title2.bold()).lineLimit(1)
                Text("\(swarm.members.count) node\(swarm.members.count == 1 ? "" : "s") · \(model.localDeviceName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Leave swarm", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                model.leaveSwarm(swarm.id)
            }.disabled(!model.running || model.changingMembership)
            #if os(iOS)
            .buttonStyle(.bordered).controlSize(.large)
            #endif
        }.padding(20)
    }

    private var swarmList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.title2).foregroundStyle(.teal)
                Text("Parvi").font(.title2.bold())
                Spacer()
            }.padding(20)
            HStack {
                Text("Swarms").font(.headline)
                Spacer()
                Button(action: model.createSwarm) { Image(systemName: "plus") }
                    .buttonStyle(.borderless).accessibilityLabel("New swarm").help("Create a new swarm")
                    .disabled(!model.running || model.creating)
                    #if os(iOS)
                    .frame(minWidth: 44, minHeight: 44)
                    #endif
            }.padding(.horizontal, 20).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.swarms) { swarm in
                        Button {
                            openSwarm(swarm.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "circle.hexagongrid").foregroundStyle(.teal)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(swarm.name).font(.callout.weight(.semibold)).lineLimit(1)
                                    Text("\(swarm.members.count) node\(swarm.members.count == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if model.selectedSwarmID == swarm.id {
                                    Image(systemName: "checkmark").font(.caption).foregroundStyle(.teal)
                                }
                            }.padding(12)
                            .background(model.selectedSwarmID == swarm.id ? Color.teal.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Select \(swarm.name), \(swarm.members.count) nodes")
                    }
                }.padding(.horizontal, 10)
                if model.swarms.isEmpty {
                    Text(model.running ? "You are not in any swarms." : "Starting your node…")
                        .font(.callout).foregroundStyle(.secondary).padding(20)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Add a swarm").font(.headline)
                Text("Paste an invitation from any node in that swarm.").font(.caption).foregroundStyle(.secondary)
                TextField("Paste invitation…", text: $model.incomingInvitation)
                    .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                    .accessibilityLabel("Swarm invitation to add").onSubmit { model.join() }
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).submitLabel(.join)
                    #endif
                Button(action: model.join) {
                    HStack(spacing: 6) {
                        if model.joining { ProgressView().controlSize(.small) }
                        Text(model.joining ? "Adding…" : "Add swarm")
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(!model.canJoin)
                #if os(iOS)
                .controlSize(.large)
                #endif
                if !model.runtime.canConnect {
                    Text(model.runtime.connectionDescription)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = model.joinError {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                } else if let notice = model.joinNotice {
                    Text(notice).font(.caption).foregroundStyle(.teal)
                }
            }.padding(16)
            VStack(alignment: .leading, spacing: 8) {
                Text("Reception desk URL").font(.caption).foregroundStyle(.secondary)
                TextField("wss://your-desk/relay/v1", text: $model.deskURL)
                    .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    #endif
                Button("Use desk (new session)") { confirmingDesk = true }
                    .disabled(!model.canConfigure)
                    .alert("Use this Reception desk?", isPresented: $confirmingDesk) {
                        Button("Start new session", role: .destructive) { model.configureDesk() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Current transient swarm memberships and chats will be discarded. The new node session connects through this desk.")
                    }
                if model.relayConnected { Text("Reception desk connected").font(.caption).foregroundStyle(.teal) }
                else if let error = model.relayError { Text(error).font(.caption).foregroundStyle(.orange) }
                else { Text("Connecting to Reception desk…").font(.caption).foregroundStyle(.secondary) }
            }.padding(.horizontal, 16).padding(.bottom, 12)
            if let error = model.error, !model.running { errorBanner(error) }
            Divider()
            HStack(spacing: 6) {
                Circle().fill(model.running ? Color.teal : Color.orange).frame(width: 6, height: 6)
                Text(model.running ? "This node · \(model.swarms.count) swarm\(model.swarms.count == 1 ? "" : "s")" : "Node offline")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                diagnosticsButton
            }.padding(16)
        }.background(Color.parviSidebar)
    }

    private var invitationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invitation to this swarm").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                #if os(iOS)
                TextField("Invitation unavailable", text: $invitationFieldText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityLabel("Selected swarm invitation")
                    .onChange(of: model.invitation, initial: true) { _, value in invitationFieldText = value }
                    .onChange(of: model.selectedSwarmID) { _, _ in invitationFieldText = model.invitation }
                #else
                InvitationLinkField(value: model.invitation).frame(height: invitationFieldHeight)
                    .accessibilityLabel("Selected swarm invitation").accessibilityValue(model.invitation)
                #endif
                Button {
                    #if os(iOS)
                    model.copyInvitation(invitationFieldText)
                    #else
                    model.copyInvitation()
                    #endif
                } label: {
                    Label(model.copiedInvitation ? "Copied" : "Copy", systemImage: model.copiedInvitation ? "checkmark" : "doc.on.doc")
                }.accessibilityLabel("Copy swarm invitation")
                #if os(iOS)
                .buttonStyle(.bordered).controlSize(.large)
                #endif
            }
            if !model.runtime.canConnect {
                Text("Invitations become available when this node supports network connections.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(12).background(Color.parviCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private var invitationFieldHeight: CGFloat {
        #if os(iOS)
        36
        #else
        28
        #endif
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.messages.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 32, weight: .light)).foregroundStyle(.teal)
                            .padding(20).background(.teal.opacity(0.07), in: Circle())
                        Text("It starts with a hello.").font(.title3.weight(.semibold))
                        Text(model.running ? "Invite another node, or send the first message." : "Waiting for your local node to start.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.top, 40).padding(.horizontal, 20)
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(model.messages) { message in
                            let mine = message.sender == model.node
                            HStack(alignment: .bottom) {
                                if mine { Spacer(minLength: 32) }
                                VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                                    Text(model.displayName(message.sender)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    Text(message.text).textSelection(.enabled)
                                        .padding(.horizontal, 14).padding(.vertical, 11)
                                        .background(mine ? Color.teal.opacity(0.12) : Color.parviCard,
                                                    in: RoundedRectangle(cornerRadius: 14))
                                    Text(Date(timeIntervalSince1970: message.time / 1000), style: .time)
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                if !mine { Spacer(minLength: 32) }
                            }.id(message.id)
                        }
                    }.frame(maxWidth: 900).padding(24).frame(maxWidth: .infinity)
                }
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .onChange(of: model.messages.last?.id) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Message the swarm…", text: $model.draft, axis: .vertical)
                .lineLimit(1...4).textFieldStyle(.plain).focused($composerFocused)
                .onSubmit { model.send() }
                #if os(iOS)
                .submitLabel(.send)
                #endif
                .accessibilityLabel("Message the swarm")
            Button { model.send(); composerFocused = true } label: {
                Image(systemName: "arrow.up").font(.headline).frame(width: sendButtonSize.width, height: sendButtonSize.height)
            }
            .buttonStyle(.borderedProminent).disabled(!model.canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("Send message").help("Send message (⌘ Return)")
        }.padding(16).background(Color.parviBackground)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(error).textSelection(.enabled)
            Spacer()
            if !model.running {
                #if os(macOS)
                Button("Restart") { model.start() }
                #endif
            }
            Button { model.error = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss error")
        }.font(.caption).padding(12).background(.orange.opacity(0.1))
    }

    private var sendButtonSize: CGSize {
        #if os(iOS)
        CGSize(width: 28, height: 32)
        #else
        CGSize(width: 22, height: 24)
        #endif
    }

    private var footer: some View {
        HStack {
            Text("Chat prototype · history lasts this session").font(.caption2).foregroundStyle(.secondary)
            Spacer()
            diagnosticsButton
        }.padding(.horizontal, 16).padding(.vertical, 9)
    }

    private var diagnosticsButton: some View {
        Button { showingDiagnostics.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Runtime details")
            #if os(iOS)
            .frame(minWidth: 44, minHeight: 44)
            #else
            .popover(isPresented: $showingDiagnostics) { runtimeDetails.padding(20).frame(idealWidth: 330) }
            #endif
    }

    private var runtimeDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(model.running ? "Node running" : "Node unavailable",
                  systemImage: model.running ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.headline).foregroundStyle(model.running ? .teal : .orange)
            Text(model.localDeviceName).font(.subheadline.weight(.medium))
            Text(model.node).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Text(model.runtimeInfo).font(.caption).textSelection(.enabled)
            Text(model.relayConnected ? "Reception desk connected" : model.relayError ?? "Reception desk not connected")
                .font(.caption).foregroundStyle(.secondary)
            Text(model.runtime.connectionHelp).font(.callout).foregroundStyle(.secondary)
        }
    }

}

#if os(macOS)
private struct InvitationLinkField: NSViewRepresentable {
    let value: String
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: value)
        field.isEditable = false
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.usesSingleLineMode = true
        field.placeholderString = "Invitation available when networking is ready"
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("This swarm’s invitation link")
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != value { field.stringValue = value }
    }
}
#endif

extension Color {
    static var parviBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    static var parviSidebar: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
    static var parviCard: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

extension NetworkNode {
    var statusColor: Color {
        switch state {
        case "running": return .green
        case "unresponsive": return .yellow
        case "down": return .red
        default: return .gray
        }
    }
}
