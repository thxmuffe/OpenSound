import SwiftUI
import AppKit

struct ChatMessage: Identifiable, Decodable {
    let id: String
    let text: String
    let sender: String
    let time: Double
}

struct Snapshot: Decodable {
    let node: String
    let peers: [String]
    let messages: [ChatMessage]
    let error: String?
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var peers: [String] = []
    @Published var node = "Starting Erlang…"
    @Published var running = false
    @Published var error: String?
    @Published var draft = ""
    @Published var peerName = ""
    @Published var peerCookie = ""
    @Published var showingConnection = false
    let cookie = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var process: Process?
    private var input: FileHandle?
    private var timer: Timer?
    private var pending = 0

    init() { start() }

    func start() {
        guard process == nil else { return }
        error = nil
        let runtime = Bundle.main.resourceURL!.appendingPathComponent("runtime")
        do {
            let folders = try FileManager.default.contentsOfDirectory(atPath: runtime.path)
            guard let erts = folders.first(where: { $0.hasPrefix("erts-") }) else {
                throw NSError(domain: "Parvi", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "The bundled Erlang runtime is missing."])
            }
            let task = Process()
            task.executableURL = runtime.appendingPathComponent("\(erts)/bin/erlexec")
            let name = "parvi_mac_\(ProcessInfo.processInfo.processIdentifier)@127.0.0.1"
            task.arguments = ["-boot", runtime.appendingPathComponent("releases/0.1.0/start").path,
                              "-noshell", "-name", name, "-setcookie", cookie,
                              "-kernel", "inet_dist_use_interface", "{127,0,0,1}",
                              "-s", "parvi_bridge", "main"]
            var env = ProcessInfo.processInfo.environment
            env["ROOTDIR"] = runtime.path
            env["BINDIR"] = runtime.appendingPathComponent("\(erts)/bin").path
            env["EMU"] = "beam"
            env["PROGNAME"] = "erl"
            env["ERL_EPMD_ADDRESS"] = "127.0.0.1"
            task.environment = env
            task.currentDirectoryURL = FileManager.default.temporaryDirectory
            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            task.standardInput = stdin
            task.standardOutput = stdout
            task.standardError = stderr
            // Drain logs separately so they cannot corrupt the JSON channel or block BEAM.
            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { FileHandle.standardError.write(data) }
            }
            task.terminationHandler = { [weak self] task in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.running = false
                    self.timer?.invalidate()
                    self.timer = nil
                    self.process = nil
                    self.input = nil
                    self.pending = 0
                    self.peers = []
                    self.error = "Erlang stopped (status \(task.terminationStatus)). Restart to begin a new session."
                }
            }
            try task.run()
            process = task
            input = stdin.fileHandleForWriting
            // Read on a dedicated queue; all observable state stays on the main thread.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var buffer = Data()
                let handle = stdout.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = Data(buffer[..<newline])
                        buffer.removeSubrange(...newline)
                        DispatchQueue.main.async { self?.receive(line) }
                    }
                }
                stderr.fileHandleForReading.readabilityHandler = nil
            }
            request(["method": "snapshot"])
            timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, self.pending == 0 else { return }
                    self.request(["method": "snapshot"])
                }
            }
        } catch {
            self.error = "Could not start Erlang: \(error.localizedDescription)"
        }
    }

    private func receive(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        pending = max(0, pending - 1)
        running = true
        node = snapshot.node
        messages = snapshot.messages
        peers = snapshot.peers
        // Polls do not erase actionable errors from a previous user command.
        if let issue = snapshot.error { error = issue }
    }

    private func request(_ payload: [String: String]) {
        guard let input = input, let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        do {
            try input.write(contentsOf: data + Data([10]))
            pending += 1
        } catch { self.error = "The connection to Erlang closed. Restart the session." }
    }

    func send() {
        guard running, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard draft.utf8.count <= 4096 else { error = "Messages must be at most 4096 UTF-8 bytes."; return }
        error = nil
        request(["method": "send", "text": draft])
        draft = ""
    }

    func connect() {
        error = nil
        request(["method": "connect", "node": peerName.trimmingCharacters(in: .whitespacesAndNewlines),
                 "cookie": peerCookie.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
    }
}

@main
struct ParviApp: App {
    @StateObject private var model = ChatModel()

    var body: some Scene {
        WindowGroup("Parvi") {
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Swarm chat").font(.title2.bold())
                            Text("\(model.peers.count + (model.running ? 1 : 0)) device\(model.peers.isEmpty ? "" : "s") · This Mac")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { model.showingConnection = true } label: {
                            Label("Connect", systemImage: "plus")
                        }.disabled(!model.running)
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
                .background(Color(nsColor: .textBackgroundColor))
            }
            .frame(minWidth: 760, minHeight: 520)
            .sheet(isPresented: $model.showingConnection) { connection }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.stop() }
        }
        .defaultSize(width: 960, height: 680)
        .commands { CommandGroup(replacing: .newItem) {} }
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
                Label("This Mac", systemImage: "laptopcomputer")
                ForEach(model.peers, id: \.self) { peer in
                    Label(peer.components(separatedBy: "@").first ?? peer, systemImage: "desktopcomputer")
                        .font(.callout).lineLimit(1).help(peer)
                }
            }
            Spacer()
            if !model.running { Button("Restart Erlang") { model.start() } }
            VStack(alignment: .leading, spacing: 6) {
                Text("MAC PROTOTYPE").font(.caption2.weight(.bold))
                Text("Chat runs in Erlang/OTP.\nHistory lasts for this session.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(24).frame(width: 190).frame(maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.messages.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 40)).foregroundStyle(.teal)
                        Text("A small start for the swarm").font(.title3.bold())
                        Text("Send your first message, or connect another\nParvi instance running on this Mac.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.top, 110)
                } else {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(model.messages) { message in
                            let mine = message.sender == model.node
                            HStack {
                                if mine { Spacer(minLength: 60) }
                                VStack(alignment: mine ? .trailing : .leading, spacing: 5) {
                                    Text(mine ? "This Mac" : message.sender.components(separatedBy: "@").first ?? message.sender)
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
            Text("This first build connects app instances on the same Mac. Share your node name and cookie with the other instance.")
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
            TextField("Other instance’s node name", text: $model.peerName)
            SecureField("Other instance’s cookie", text: $model.peerCookie)
            Text("Cookies allow trusted Erlang connections. Keep them private. This build does not connect to phones or other computers yet.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { model.showingConnection = false }.keyboardShortcut(.cancelAction)
                Button("Connect") { model.connect(); model.showingConnection = false }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.peerName.isEmpty || model.peerCookie.isEmpty)
            }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 510)
    }
}
