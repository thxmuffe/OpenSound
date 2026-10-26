import SwiftUI

public struct ParviChatView: View {
    @ObservedObject private var model: ChatModel
    public init(model: ChatModel) { self.model = model }

    public var body: some View {
        Group {
            HStack(spacing: 0) {
                #if os(macOS)
                sidebar
                Divider()
                #endif
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Swarm chat").font(.title2.bold())
                            Text("\(model.peers.count + (model.running ? 1 : 0)) device\(model.peers.isEmpty ? "" : "s") · \(model.localDeviceName)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            #if os(iOS)
                            Label(model.running ? "Erlang running" : "Erlang unavailable",
                                  systemImage: model.running ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .font(.caption).foregroundStyle(model.running ? .green : .orange)
                            if !model.runtimeInfo.isEmpty {
                                Text(model.runtimeInfo).font(.caption2).foregroundStyle(.secondary)
                            }
                            #endif
                        }
                        Spacer()
                        Button { model.showingConnection = true } label: {
                            Label("Connect", systemImage: "plus")
                        }.disabled(!model.running || !model.runtime.canConnect)
                    }.padding(24)
                    Divider()
                    conversation
                    if let error = model.error {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(error).textSelection(.enabled)
                            Spacer()
                            Button { model.error = nil } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain)
                        }.font(.callout).padding(12).background(.orange.opacity(0.12))
                    }
                    Divider()
                    HStack(alignment: .bottom, spacing: 12) {
                        TextField("Message the swarm…", text: $model.draft, axis: .vertical)
                            .lineLimit(1...5).textFieldStyle(.plain)
                            .onSubmit { model.send() }
                        Button(action: model.send) { Image(systemName: "arrow.up").font(.headline).padding(4) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.running || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .keyboardShortcut(.return, modifiers: .command)
                            .help("Send message (⌘ Return)")
                    }.padding(20)
                }
                .background(Color.parviChatBackground)
            }
            .sheet(isPresented: $model.showingConnection) { connection }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.title).foregroundStyle(.teal)
                Text("Parvi").font(.title.bold())
            }
            HStack(spacing: 6) {
                Circle().fill(model.running ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(model.running ? "Erlang running" : "Erlang offline").font(.callout)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("DEVICES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Label(model.localDeviceName, systemImage: "laptopcomputer")
                ForEach(model.peers, id: \.self) { peer in
                    Label(peer.components(separatedBy: "@").first ?? peer, systemImage: "desktopcomputer")
                        .font(.callout).lineLimit(1).help(peer)
                }
            }
            Spacer()
            if !model.running { Button("Restart Erlang") { model.start() } }
            VStack(alignment: .leading, spacing: 6) {
                Text("PARVI PROTOTYPE").font(.caption2.weight(.bold))
                Text("Chat runs in Erlang/OTP.\nHistory lasts for this session.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(24).frame(width: 190).frame(maxHeight: .infinity)
            .background(Color.parviSidebarBackground)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.messages.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 40)).foregroundStyle(.teal)
                        Text("A small start for the swarm").font(.title3.bold())
                        Text(model.running ? "Send your first message to the swarm." : "Erlang is not running on this device.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.top, 110)
                } else {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(model.messages) { message in
                            let mine = message.sender == model.node
                            HStack {
                                if mine { Spacer(minLength: 60) }
                                VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                                    Text(mine ? model.localDeviceName : message.sender.components(separatedBy: "@").first ?? message.sender)
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(message.text).textSelection(.enabled)
                                        .padding(.horizontal, 14).padding(.vertical, 10)
                                        .background(mine ? Color.teal.opacity(0.14) : Color.secondary.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                    Text(Date(timeIntervalSince1970: message.time / 1000), style: .time)
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                if !mine { Spacer(minLength: 60) }
                            }.id(message.id)
                        }
                    }.padding(24)
                }
            }.onChange(of: model.messages.last?.id) { _, id in
                if let id = id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect a Parvi instance").font(.title2.bold())
            Text(model.runtime.connectionDescription)
                .foregroundStyle(.secondary)
            HStack {
                Text(model.node).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button("Copy node") { model.copy(model.node) }
            }
            HStack {
                Text("Session cookie").foregroundStyle(.secondary)
                Spacer()
                Button("Copy cookie") { model.copy(model.cookie) }
            }
            Divider()
            Text("Reception desk").font(.headline)
            HStack {
                TextField("http://127.0.0.1:8765", text: $model.brokerURL)
                Button("Register / Find nodes") { model.discover() }
            }
            if !model.knownNodes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.knownNodes, id: \.self) { node in
                            Button(node) { model.peerName = node }
                                .font(.system(.caption, design: .monospaced))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 90)
            }
            Text("Register this app and fetch known names. Select a returned name, then supply its cookie separately. Discovery does not establish a connection.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Divider()
            TextField("Other instance’s node name", text: $model.peerName)
            SecureField("Other instance’s cookie", text: $model.peerCookie)
            Text(model.runtime.connectionHelp)
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { model.showingConnection = false }.keyboardShortcut(.cancelAction)
                Button("Connect") { model.connect(); model.showingConnection = false }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.peerName.isEmpty || model.peerCookie.isEmpty)
            }
        }.textFieldStyle(.roundedBorder).padding(28).frame(maxWidth: 510)
    }
}

private extension Color {
    static var parviChatBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    static var parviSidebarBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
