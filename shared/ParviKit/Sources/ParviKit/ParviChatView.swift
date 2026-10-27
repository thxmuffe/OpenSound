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
    @FocusState private var composerFocused: Bool

    public init(model: ChatModel) { self.model = model }

    public var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900
            HStack(spacing: 0) {
                if wide { swarmList.frame(width: 280); Divider() }
                if !wide && showingList {
                    swarmList.frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 0) {
                        if let swarm = model.selectedSwarm {
                            swarmHeader(swarm, wide: wide)
                            invitationCard.padding(.horizontal, 20).padding(.bottom, 16)
                            Picker("Swarm view", selection: $destination) {
                                ForEach(Destination.allCases, id: \.self) { tab in
                                    Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
                                }
                            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 20).padding(.bottom, 14)
                            Divider()
                            swarmPages.id(swarm.id).frame(maxWidth: .infinity, maxHeight: .infinity)
                            if destination == .chat { Divider(); composer }
                        } else {
                            if !wide {
                                HStack { Button("Swarms", systemImage: "chevron.left") { showingList = true }; Spacer() }.padding(20)
                            }
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
            }.tint(.teal)
            .onChange(of: model.selectedSwarmID) { _, id in
                destination = .chat
                if id != nil { showingList = false }
            }
        }
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
            if !wide {
                Button { showingList = true } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).accessibilityLabel("Show swarm list")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(swarm.name).font(.title2.bold()).lineLimit(1)
                Text("\(swarm.members.count) device\(swarm.members.count == 1 ? "" : "s") · \(model.localDeviceName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Leave swarm", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                model.leaveSwarm(swarm.id)
            }.disabled(!model.running || model.changingMembership)
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
            }.padding(.horizontal, 20).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.swarms) { swarm in
                        Button {
                            model.selectedSwarmID = swarm.id
                            showingList = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "circle.hexagongrid").foregroundStyle(.teal)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(swarm.name).font(.callout.weight(.semibold)).lineLimit(1)
                                    Text("\(swarm.members.count) device\(swarm.members.count == 1 ? "" : "s")")
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
                        }.buttonStyle(.plain).accessibilityLabel("Select \(swarm.name), \(swarm.members.count) devices")
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
                Text("Paste an invitation from any member.").font(.caption).foregroundStyle(.secondary)
                TextField("Paste invitation…", text: $model.incomingInvitation)
                    .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                    .accessibilityLabel("Swarm invitation to add").onSubmit { model.join() }
                    .disabled(!model.running || model.joining || !model.runtime.canConnect)
                Button(action: model.join) {
                    HStack(spacing: 6) {
                        if model.joining { ProgressView().controlSize(.small) }
                        Text(model.joining ? "Adding…" : "Add swarm")
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(!model.canJoin)
                if let error = model.joinError {
                    Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                } else if let notice = model.joinNotice {
                    Text(notice).font(.caption).foregroundStyle(.teal)
                }
            }.padding(16)
            if let error = model.error, !model.running { errorBanner(error) }
            Divider()
            HStack(spacing: 6) {
                Circle().fill(model.running ? Color.teal : Color.orange).frame(width: 6, height: 6)
                Text(model.running ? "This node · \(model.swarms.count) swarm\(model.swarms.count == 1 ? "" : "s")" : "Node offline")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(16)
        }.background(Color.parviSidebar)
    }

    private var invitationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invitation to this swarm").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                InvitationLinkField(value: model.invitation).frame(height: 28)
                    .accessibilityLabel("Selected swarm invitation").accessibilityValue(model.invitation)
                Button(action: model.copyInvitation) {
                    Label(model.copiedInvitation ? "Copied" : "Copy", systemImage: model.copiedInvitation ? "checkmark" : "doc.on.doc")
                }.disabled(!model.canInvite).accessibilityLabel("Copy swarm invitation")
            }
        }.padding(12).background(Color.parviCard, in: RoundedRectangle(cornerRadius: 12))
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
                .accessibilityLabel("Message the swarm")
            Button { model.send(); composerFocused = true } label: {
                Image(systemName: "arrow.up").font(.headline).frame(width: 22, height: 24)
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

    private var footer: some View {
        HStack {
            Text("Chat prototype · history lasts this session").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Button { showingDiagnostics.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Runtime details")
                .popover(isPresented: $showingDiagnostics) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This node").font(.headline)
                        Text(model.node).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Text(model.runtimeInfo).font(.caption).textSelection(.enabled)
                        Text(model.runtime.connectionHelp).font(.caption).foregroundStyle(.secondary)
                    }.padding(20).frame(idealWidth: 330)
                }
        }.padding(.horizontal, 16).padding(.vertical, 9)
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
#else
private struct InvitationLinkField: View {
    let value: String
    var body: some View {
        ScrollView(.horizontal) {
            Text(value.isEmpty ? "Invitation unavailable" : value)
                .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                .padding(.horizontal, 8).padding(.vertical, 7)
        }
        .background(Color.parviBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.2)))
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
