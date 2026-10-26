import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
public final class ChatModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var peers: [String] = []
    @Published var knownNodes: [String] = []
    @Published var runtimeInfo = ""
    @Published var brokerURL = "http://127.0.0.1:8765"
    @Published var node = "Starting Erlang…"
    @Published var running = false
    @Published var error: String?
    @Published var draft = ""
    @Published var peerName = ""
    @Published var peerCookie = ""
    @Published var showingConnection = false
    let runtime: any ChatRuntime
    var cookie: String { runtime.cookie }
    var localDeviceName: String { runtime.localDeviceName }

    public init(runtime: any ChatRuntime) {
        self.runtime = runtime
        start()
    }

    func start() {
        error = nil
        runtime.start(onSnapshot: { [weak self] data in
            guard let self = self,
                  let snapshot = try? JSONDecoder().decode(ChatSnapshot.self, from: data) else { return }
            self.running = true
            self.node = snapshot.node
            self.messages = snapshot.messages
            self.peers = snapshot.peers
            self.knownNodes = snapshot.known_nodes ?? []
            self.runtimeInfo = snapshot.runtime_info ?? ""
            if let error = snapshot.error { self.error = error }
        }, onFailure: { [weak self] error in
            self?.running = false
            self?.peers = []
            self?.node = "Erlang unavailable"
            self?.error = error
        })
    }

    func send() {
        guard running, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard draft.utf8.count <= 4096 else { error = "Messages must be at most 4096 UTF-8 bytes."; return }
        error = nil
        runtime.request(["method": "send", "text": draft])
        draft = ""
    }

    func connect() {
        error = nil
        runtime.request(["method": "connect", "node": peerName.trimmingCharacters(in: .whitespacesAndNewlines),
                         "cookie": peerCookie.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    func discover() {
        error = nil
        runtime.request(["method": "discover", "url": brokerURL.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }

    public func stop() { runtime.stop() }
}
