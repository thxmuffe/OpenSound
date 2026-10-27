import Foundation
import ParviKit

@MainActor
final class MacErlangRuntime: ChatRuntime {
    private(set) var cookie = ""
    let localDeviceName = "This Mac"
    let connectionDescription = "Local prototype · swarm invitations currently work between Parvi instances on this Mac."
    let connectionHelp = "Invitations contain private Erlang credentials. Membership, leave and mutual removal are scoped to each swarm. This is trusted local transport, not hardened internet authorization; LAN and internet connections are not enabled."
    let canConnect = true
    private var process: Process?
    private var input: FileHandle?
    private var timer: Timer?
    private var pending = 0
    private var onSnapshot: ((Data) -> Void)?
    private var onFailure: ((String) -> Void)?

    func start(onSnapshot: @escaping (Data) -> Void, onFailure: @escaping (String) -> Void) {
        self.onSnapshot = onSnapshot
        self.onFailure = onFailure
        guard process == nil else { return }
        cookie = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let runtime = Bundle.main.resourceURL!.appendingPathComponent("runtime")
        do {
            let folders = try FileManager.default.contentsOfDirectory(atPath: runtime.path)
            guard let erts = folders.first(where: { $0.hasPrefix("erts-") }) else {
                throw NSError(domain: "Parvi", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "The bundled Erlang runtime is missing."])
            }
            let task = Process()
            task.executableURL = runtime.appendingPathComponent("\(erts)/bin/erlexec")
            let name = "parvi_mac_\(ProcessInfo.processInfo.processIdentifier)\(Int.random(in: 100000...999999))@127.0.0.1"
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
                    self.timer?.invalidate()
                    self.timer = nil
                    self.process = nil
                    self.input = nil
                    self.pending = 0
                    self.onFailure?("Erlang stopped (status \(task.terminationStatus)). Restart to begin a new session.")
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
                        DispatchQueue.main.async {
                            if let self = self, (try? JSONDecoder().decode(ChatSnapshot.self, from: line)) != nil {
                                self.pending = max(0, self.pending - 1)
                                self.onSnapshot?(line)
                            }
                        }
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
            onFailure("Could not start Erlang: \(error.localizedDescription)")
        }
    }

    func request(_ payload: [String: String]) {
        guard let input = input, let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        do {
            try input.write(contentsOf: data + Data([10]))
            pending += 1
        } catch { onFailure?("The connection to Erlang closed. Restart the session.") }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
    }
}
