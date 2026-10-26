import Foundation

public struct ChatMessage: Identifiable, Decodable {
    public let id: String
    public let text: String
    public let sender: String
    public let time: Double
}

public struct ChatSnapshot: Decodable {
    public let node: String
    public let peers: [String]
    public let messages: [ChatMessage]
    public let error: String?
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
