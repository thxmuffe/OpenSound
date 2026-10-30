import Foundation
import ParviKit

@MainActor
final class MacErlangRuntime: ChatRuntime {
    private(set) var cookie = ""
    let localDeviceName = "This Mac"
    let connectionDescription = "Create a native cluster or join one through the global Reception Desk."
    let connectionHelp = "Native invitations grant whole-VM trust. This increment supports one cluster per session. Restart to switch clusters; voluntary leave is not implemented yet. iPhone and Windows currently use the earlier transport."
    let canConnect = true
    private var process: Process?
    private var input: FileHandle?
    private var timer: Timer?
    private var reader: Task<Void, Never>?
    private var pending = 0
    private var onSnapshot: ((ChatSnapshot) -> Void)?
    private var onFailure: ((String) -> Void)?

    func start(onSnapshot: @escaping (ChatSnapshot) -> Void, onFailure: @escaping (String) -> Void) {
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
                              "-start_epmd", "false", "-proto_dist", "parvi_webrtc",
                              "-kernel", "connect_all", "false", "dist_auto_connect", "never",
                              "-parvi", "runtime_profile", "native_cluster", "native_desk", "true",
                              "-s", "parvi_bridge", "main"]
            let libraries = runtime.appendingPathComponent("native_lib")
            let dependencies = try FileManager.default.contentsOfDirectory(at: libraries, includingPropertiesForKeys: nil)
            task.arguments! += ["-pa"] + dependencies.map { $0.appendingPathComponent("ebin").path }
            var env = ProcessInfo.processInfo.environment
            env["ROOTDIR"] = runtime.path
            env["BINDIR"] = runtime.appendingPathComponent("\(erts)/bin").path
            env["EMU"] = "beam"
            env["PROGNAME"] = "erl"
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
                    self.reader?.cancel()
                    self.reader = nil
                    self.process = nil
                    self.input = nil
                    self.pending = 0
                    self.onFailure?("Erlang stopped (status \(task.terminationStatus)). Restart to begin a new session.")
                }
            }
            try task.run()
            process = task
            input = stdin.fileHandleForWriting
            reader = Task { [weak self] in
                let handle = stdout.fileHandleForReading
                defer {
                    try? handle.close()
                    stderr.fileHandleForReading.readabilityHandler = nil
                }
                do {
                    try await ChatSnapshot.read(from: handle) { [weak self] snapshot in
                        guard let self else { return }
                        self.pending = max(0, self.pending - 1)
                        self.onSnapshot?(snapshot)
                    }
                } catch {
                    if !Task.isCancelled { self?.onFailure?("Could not read from Erlang: \(error.localizedDescription)") }
                }
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
        reader?.cancel()
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
    }
}
