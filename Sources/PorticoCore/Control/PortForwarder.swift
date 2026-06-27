import Foundation

// Adds and removes individual forwards on a host's live ControlMaster, the way
// VS Code's Ports panel does. `-F /dev/null` keeps each request to exactly the
// one forward we name (without it, ssh re-applies the config's forwards and the
// request fails noisily).
public struct PortForwarder: Sendable {
    private let runner: CommandRunner
    private let master: ControlMasterManager
    private let sshPath: String

    public init(runner: CommandRunner = SystemCommandRunner(),
                master: ControlMasterManager,
                sshPath: String = "/usr/bin/ssh") {
        self.runner = runner
        self.master = master
        self.sshPath = sshPath
    }

    public static func forwardArgs(socket: String, _ f: ManagedForward) -> [String] {
        ["-O", "forward", "-F", "/dev/null",
         "-L", "\(f.localPort):\(f.remoteHost):\(f.remotePort)",
         "-S", socket, f.host]
    }

    public static func cancelArgs(socket: String, _ f: ManagedForward) -> [String] {
        ["-O", "cancel", "-F", "/dev/null",
         "-L", "\(f.localPort):\(f.remoteHost):\(f.remotePort)",
         "-S", socket, f.host]
    }

    public func add(_ f: ManagedForward) throws {
        try master.ensureConnected(f.host)
        let socket = master.socketPath(for: f.host)
        let r = try runner.run(sshPath, Self.forwardArgs(socket: socket, f))
        if r.exitCode != 0 {
            throw PortForwarderError.addFailed(detail: r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func remove(_ f: ManagedForward) throws {
        let socket = master.socketPath(for: f.host)
        _ = try runner.run(sshPath, Self.cancelArgs(socket: socket, f))
    }
}

public enum PortForwarderError: Error, CustomStringConvertible {
    case addFailed(detail: String)
    public var description: String {
        switch self {
        case .addFailed(let detail):
            return detail.isEmpty ? "port forwarding failed (is the local port already in use?)" : detail
        }
    }
}
