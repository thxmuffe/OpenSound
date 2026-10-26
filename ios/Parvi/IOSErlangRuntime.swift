import Foundation
import ParviKit

/// Integration boundary for an in-process, arm64 iOS BEAM runtime.
/// Deliberately unavailable until real Erlang can execute on the device.
/// No fake history, Swift chat implementation, or remote Mac proxy.
@MainActor
final class IOSErlangRuntime: ChatRuntime {
    let cookie = ""
    let localDeviceName = "This iPhone"
    let connectionDescription = "The embedded Erlang runtime must start before joining a swarm."
    let connectionHelp = "Device networking will be enabled after on-device Erlang execution is verified."
    let canConnect = false

    func start(onSnapshot: @escaping (Data) -> Void, onFailure: @escaping (String) -> Void) {
        onFailure("The iPhone project is ready, but its embedded Erlang runtime is not linked yet. Chat is unavailable until that integration is complete.")
    }

    func request(_ payload: [String: String]) {}
    func stop() {}
}
