import Foundation
import Darwin
import ParviKit

/// In-process BEAM. The loopback socket stays inside this app/device;
/// no request is sent to Erlang on the Mac.
@MainActor
final class IOSErlangRuntime: ChatRuntime {
    let cookie = ""
    let localDeviceName = "This iPhone"
    #if PARVI_NATIVE_TRANSPORT
    let connectionDescription = "Create a native cluster or join one through the global Reception Desk."
    let connectionHelp = "Native invitations grant whole-VM trust. This increment supports one cluster per session. Force-quit and reopen to retry or switch clusters. Voluntary leave and background recovery are not implemented."
    #else
    let connectionDescription = "The default Reception desk connects automatically. Share a swarm invitation to add another node."
    let connectionHelp = "The iPhone opens an outbound encrypted connection to the Reception desk. Invitations are scoped to a swarm; background operation remains outside this prototype."
    #endif
    let canConnect = true
    private var started = false
    private var input: FileHandle?
    private var timer: Timer?
    private var reader: Task<Void, Never>?
    private var pending = 0
    private var didReceiveSnapshot = false
    private var lastConnectionStatus: Data?
    private var onSnapshot: ((ChatSnapshot) -> Void)?
    private var onFailure: ((String) -> Void)?

    func start(onSnapshot: @escaping (ChatSnapshot) -> Void, onFailure: @escaping (String) -> Void) {
        guard !started else {
            onFailure("BEAM starts once per app process. Quit and reopen Parvi to retry.")
            return
        }
        self.onSnapshot = onSnapshot
        self.onFailure = onFailure
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("runtime"),
              FileManager.default.fileExists(atPath: root.appendingPathComponent("start_clean.boot").path) else {
            onFailure("Bundled OTP files are missing. Run Apps/iOS/prepare-runtime.py before building.")
            return
        }
        var port: UInt16 = 0
        let listener = parvi_bridge_listen(&port)
        guard listener >= 0 else { onFailure("Could not create the in-app Erlang bridge."); return }
        started = true
        let bridgePort = port
        let rootPath = root.path
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        DispatchQueue.global(qos: .userInitiated).async {
            rootPath.withCString { root in
                directory.withCString { data in parvi_beam_start(root, data, bridgePort) }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fd = parvi_bridge_accept(listener)
            close(listener)
            guard fd >= 0 else {
                DispatchQueue.main.async { self?.onFailure?("Erlang bridge accept failed.") }
                return
            }
            var noSignal: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.input = handle
                self.reader = Task { [weak self] in
                    defer { try? handle.close() }
                    do {
                        try await ChatSnapshot.read(from: handle) { [weak self] snapshot in
                            guard let self else { return }
                            self.pending = max(0, self.pending - 1)
                            self.didReceiveSnapshot = true
                            self.recordConnectionStatus(snapshot)
                            self.onSnapshot?(snapshot)
                        }
                    } catch { /* EOF and read errors share the bridge-closed message below. */ }
                    guard !Task.isCancelled else { return }
                    self?.timer?.invalidate()
                    self?.input = nil
                    self?.onFailure?("The in-app BEAM connection closed. Relaunch Parvi and inspect the Xcode console.")
                }
                self.request(["method": "snapshot"])
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self = self, self.pending == 0 else { return }
                        self.request(["method": "snapshot"])
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, !self.didReceiveSnapshot else { return }
            self.onFailure?("BEAM has not responded. Check Xcode's console and Documents/parvi_erl_crash.dump.")
        }
    }

    func request(_ payload: [String: String]) {
        guard let input = input, let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        do {
            try input.write(contentsOf: data + Data([10]))
            pending += 1
        } catch { onFailure?("Could not send the request to the on-device Erlang VM.") }
    }

    // A small support receipt for physical-device diagnostics; no invitations,
    // mailbox capabilities, private keys or chat contents are written here.
    private func recordConnectionStatus(_ snapshot: ChatSnapshot) {
        guard let relay = snapshot.relay else { return }
        let status: [String: Any] = ["node": snapshot.node,
            "native_cluster": snapshot.native_cluster ?? false,
            "os_pid": String(ProcessInfo.processInfo.processIdentifier),
            "direct_peers": snapshot.direct?.peers ?? [],
            "url": relay.url as Any? ?? NSNull(), "connected": relay.connected,
            "error": relay.error as Any? ?? NSNull()]
        guard let data = try? JSONSerialization.data(withJSONObject: status, options: [.sortedKeys]),
              data != lastConnectionStatus else { return }
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("parvi_connection_status.json")
        do { try data.write(to: file, options: .atomic); lastConnectionStatus = data }
        catch { /* Connection behavior does not depend on writing diagnostics. */ }
    }

    func stop() {
        timer?.invalidate()
        reader?.cancel()
        if let input {
            shutdown(input.fileDescriptor, SHUT_RDWR)
            try? input.close()
        }
        input = nil
        // BEAM shares the app process. iOS suspends/terminates the whole app;
        // never halt the VM or attempt to restart it in the same process.
    }
}
