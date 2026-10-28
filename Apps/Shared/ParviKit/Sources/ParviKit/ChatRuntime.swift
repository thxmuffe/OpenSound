import Foundation

public struct ChatMessage: Identifiable, Decodable {
    public let id: String
    public let text: String
    public let sender: String
    public let time: Double
}

public struct NetworkNode: Identifiable, Decodable {
    public let id: String
    public let state: String
    public let detail: String

    var statusLabel: String {
        switch state {
        case "running": return "Running"
        case "unresponsive": return "Not responding"
        case "down": return "Disconnected"
        default: return detail == "reported_by_peer" ? "Reported by peer" : "Checking"
        }
    }
}

public struct NetworkSnapshot: Decodable {
    public let nodes: [NetworkNode]
    public let edges: [[String]]
}

public struct SwarmSnapshot: Identifiable, Decodable {
    public let id: String
    public let name: String
    public let invitation: String?
    public let members: [String]
    public let messages: [ChatMessage]
}

public struct CommandResult: Decodable {
    public let swarm_id: String?
}

public struct RelaySnapshot: Decodable {
    public let url: String?
    public let connected: Bool
    public let error: String?
}

public struct ChatSnapshot: Decodable {
    public let swarms: [SwarmSnapshot]?
    public let result: CommandResult?
    public let known_nodes: [String]?
    public let runtime_info: String?
    public let node: String
    public let peers: [String]
    public let messages: [ChatMessage]
    public let error: String?
    public let request_id: String?
    public let connection_string: String?
    public let network: NetworkSnapshot?
    public let relay: RelaySnapshot?
}

/// The only boundary between shared app code and a platform's Erlang host.
@MainActor
public protocol ChatRuntime: AnyObject {
    var cookie: String { get }
    var localDeviceName: String { get }
    var connectionDescription: String { get }
    var connectionHelp: String { get }
    var canConnect: Bool { get }
    func start(onSnapshot: @escaping (Data) -> Void, onFailure: @escaping (String) -> Void)
    func request(_ payload: [String: String])
    func stop()
}
