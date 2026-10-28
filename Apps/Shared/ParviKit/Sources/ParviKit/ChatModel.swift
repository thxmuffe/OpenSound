import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
public final class ChatModel: ObservableObject {
    @Published var swarms: [SwarmSnapshot] = []
    @Published var selectedSwarmID: String?
    @Published private var drafts: [String: String] = [:]
    @Published private var sendingSwarms: Set<String> = []
    @Published private var observedNetwork = NetworkSnapshot(nodes: [], edges: [])
    @Published var runtimeInfo = ""
    @Published var node = "Starting…"
    @Published var running = false
    @Published var error: String?
    @Published var incomingInvitation = "" { didSet { joinError = nil } }
    @Published var joining = false
    @Published var creating = false
    @Published var changingMembership = false
    @Published var joinError: String?
    @Published var joinNotice: String?
    @Published var copiedSwarmID: String?
    let runtime: any ChatRuntime
    private enum Operation {
        case send(String, String), join(String), create, leave(String), remove(String)
    }
    private var pending: [String: Operation] = [:]
    private var copyReset: Task<Void, Never>?
    var localDeviceName: String { runtime.localDeviceName }
    var selectedSwarm: SwarmSnapshot? { swarms.first { $0.id == selectedSwarmID } }
    var invitation: String { running ? selectedSwarm?.invitation ?? "" : "" }
    var copiedInvitation: Bool { copiedSwarmID != nil && copiedSwarmID == selectedSwarmID }
    var canInvite: Bool { running && runtime.canConnect && !invitation.isEmpty }
    var canJoin: Bool {
        running && runtime.canConnect && !joining &&
        !incomingInvitation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var sending: Bool { selectedSwarmID.map { sendingSwarms.contains($0) } ?? false }
    var canSend: Bool {
        running && selectedSwarm != nil && !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var memberCount: Int { selectedSwarm?.members.count ?? 0 }
    var messages: [ChatMessage] { selectedSwarm?.messages ?? [] }
    var peers: [String] { selectedSwarm?.members.filter { $0 != node } ?? [] }
    var draft: String {
        get { selectedSwarmID.flatMap { drafts[$0] } ?? "" }
        set { if let id = selectedSwarmID { drafts[id] = newValue } }
    }
    var network: NetworkSnapshot {
        let ids = Set(selectedSwarm?.members ?? [])
        let rows = ids.sorted().map { id in
            observedNetwork.nodes.first { $0.id == id } ?? NetworkNode(id: id, state: "checking", detail: "pending")
        }
        return NetworkSnapshot(nodes: rows, edges: observedNetwork.edges.filter {
            $0.count == 2 && ids.contains($0[0]) && ids.contains($0[1])
        })
    }

    public init(runtime: any ChatRuntime) { self.runtime = runtime; start() }

    func start() {
        error = nil
        runtime.start(onSnapshot: { [weak self] data in
            guard let self, let snapshot = try? JSONDecoder().decode(ChatSnapshot.self, from: data) else { return }
            self.running = true
            self.node = snapshot.node
            self.runtimeInfo = snapshot.runtime_info ?? ""
            self.observedNetwork = snapshot.network ?? NetworkSnapshot(nodes: [], edges: [])
            self.swarms = snapshot.swarms ?? []
            if !self.swarms.contains(where: { $0.id == self.selectedSwarmID }) {
                self.selectedSwarmID = self.swarms.first?.id
            }
            if let id = snapshot.request_id, let operation = self.pending.removeValue(forKey: id) {
                switch operation {
                case .send(let swarm, let text):
                    self.sendingSwarms.remove(swarm)
                    if let error = snapshot.error { self.error = error }
                    else if self.drafts[swarm] == text { self.drafts[swarm] = "" }
                case .join(let text):
                    self.joining = false
                    if let error = snapshot.error { self.joinError = error }
                    else {
                        self.joinNotice = "Swarm added."
                        if self.incomingInvitation == text { self.incomingInvitation = "" }
                        self.selectResult(snapshot)
                    }
                case .create:
                    self.creating = false
                    if let error = snapshot.error { self.joinError = error }
                    else { self.selectResult(snapshot) }
                case .leave, .remove:
                    self.changingMembership = false
                    if let error = snapshot.error { self.error = error }
                }
            } else if let error = snapshot.error { self.error = error }
        }, onFailure: { [weak self] error in
            guard let self else { return }
            self.running = false
            self.observedNetwork = NetworkSnapshot(nodes: [], edges: [])
            self.joining = false
            self.creating = false
            self.changingMembership = false
            self.sendingSwarms.removeAll()
            self.pending.removeAll()
            self.joinNotice = nil
            self.node = "Erlang unavailable"
            self.error = error
        })
    }

    private func selectResult(_ snapshot: ChatSnapshot) {
        if let id = snapshot.result?.swarm_id, swarms.contains(where: { $0.id == id }) { selectedSwarmID = id }
    }

    private func request(_ command: [String: String], operation: Operation) {
        let id = UUID().uuidString
        pending[id] = operation
        runtime.request(command.merging(["request_id": id]) { _, new in new })
    }

    func send() {
        guard canSend, let id = selectedSwarmID else { return }
        guard draft.utf8.count <= 4096 else { error = "Messages must be at most 4096 UTF-8 bytes."; return }
        error = nil
        sendingSwarms.insert(id)
        request(["method": "send_swarm", "swarm_id": id, "text": draft], operation: .send(id, draft))
    }

    func join() {
        guard canJoin else { return }
        joinError = nil; joinNotice = nil; joining = true
        request(["method": "join_swarm", "invitation": incomingInvitation.trimmingCharacters(in: .whitespacesAndNewlines)],
                operation: .join(incomingInvitation))
    }

    func createSwarm() {
        guard running && !creating else { return }
        creating = true; joinError = nil; joinNotice = nil
        request(["method": "create_swarm"], operation: .create)
    }

    func leaveSwarm(_ id: String) {
        guard running && !changingMembership else { return }
        changingMembership = true
        request(["method": "leave_swarm", "swarm_id": id], operation: .leave(id))
    }

    func removeBoth(swarmID: String, target: String) {
        guard running && !changingMembership else { return }
        changingMembership = true
        request(["method": "remove_both", "swarm_id": swarmID, "target": target], operation: .remove(swarmID))
    }

    func copyInvitation(_ text: String? = nil) {
        let text = text ?? invitation
        #if os(macOS)
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            error = "Could not copy the invitation. Select the link and copy it manually."
            return
        }
        #else
        UIPasteboard.general.string = text
        #endif
        copiedSwarmID = selectedSwarmID
        copyReset?.cancel()
        copyReset = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.copiedSwarmID = nil
        }
    }

    func displayName(_ id: String) -> String {
        if id == node { return localDeviceName }
        let name = id.components(separatedBy: "@").first ?? id
        if name.hasPrefix("parvi_mac_") { return "Mac · " + name.dropFirst("parvi_mac_".count).suffix(6) }
        if name.hasPrefix("parvi_windows_") { return "Windows · " + name.dropFirst("parvi_windows_".count) }
        return name
    }
    public func stop() { runtime.stop() }
}
