import Foundation

// Manages a Portico-owned SSH ControlMaster per host so individual forwards can
// be added/removed on a live connection. The master is established with
// ClearAllForwardings so it never re-applies the host's config forwards (which
// would collide with forwards owned by other sessions).
public struct ControlMasterManager: Sendable {
    private let runner: CommandRunner
    private let sshPath: String
    private let controlDir: URL

    public init(runner: CommandRunner = SystemCommandRunner(),
                sshPath: String = "/usr/bin/ssh",
                controlDir: URL) {
        self.runner = runner
        self.sshPath = sshPath
        self.controlDir = controlDir
    }

    public func socketPath(for host: String) -> String {
        let safe = host.replacingOccurrences(of: "/", with: "_")
        return controlDir.appendingPathComponent("\(safe).sock").path
    }

    public static func connectArgs(socket: String, host: String) -> [String] {
        ["-M", "-S", socket, "-fN",
         "-o", "ControlMaster=yes",
         "-o", "ClearAllForwardings=yes",
         host]
    }

    public static func checkArgs(socket: String, host: String) -> [String] {
        ["-O", "check", "-S", socket, host]
    }

    public static func exitArgs(socket: String, host: String) -> [String] {
        ["-O", "exit", "-S", socket, host]
    }

    public func isConnected(_ host: String) -> Bool {
        guard let r = try? runner.run(sshPath, Self.checkArgs(socket: socketPath(for: host), host: host))
        else { return false }
        return r.exitCode == 0
    }

    public func ensureConnected(_ host: String) throws {
        if isConnected(host) { return }
        try FileManager.default.createDirectory(at: controlDir, withIntermediateDirectories: true)
        let r = try runner.run(sshPath, Self.connectArgs(socket: socketPath(for: host), host: host))
        if r.exitCode != 0 {
            throw ControlMasterError.connectFailed(host: host, detail: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func disconnect(_ host: String) throws {
        _ = try runner.run(sshPath, Self.exitArgs(socket: socketPath(for: host), host: host))
    }
}

public enum ControlMasterError: Error, CustomStringConvertible {
    case connectFailed(host: String, detail: String)
    public var description: String {
        switch self {
        case .connectFailed(let host, let detail):
            return "couldn't connect to \(host)\(detail.isEmpty ? "" : ": \(detail)")"
        }
    }
}
