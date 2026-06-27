import Foundation

public struct TunnelController: Sendable {
    private let spawner: ProcessSpawner
    private let registry: LaunchRegistry
    private let sshPath: String
    private let killGrace: Double

    public init(spawner: ProcessSpawner = SystemProcessSpawner(),
                registry: LaunchRegistry,
                sshPath: String = "/usr/bin/ssh",
                killGrace: Double = 2.0) {
        self.spawner = spawner
        self.registry = registry
        self.sshPath = sshPath
        self.killGrace = killGrace
    }

    public static func forwardFlag(_ f: Forward) -> [String] {
        let flag: String
        switch f.kind {
        case .local: flag = "-L"
        case .remote: flag = "-R"
        case .dynamic: flag = "-D"
        }
        let bind = f.bindAddress.map { "\($0):" } ?? ""
        if f.kind == .dynamic {
            return [flag, "\(bind)\(f.bindPort)"]
        }
        let target = "\(f.targetHost ?? ""):\(f.targetPort ?? 0)"
        return [flag, "\(bind)\(f.bindPort):\(target)"]
    }

    public static func startArguments(host: HostEntry, forward: Forward?) -> [String] {
        // -N without -f: the spawned ssh IS the tunnel, so its pid is the one we
        // track for kill/restart. (-f would daemonize and the parent we spawn
        // would exit, leaving us holding a dead pid.) ExitOnForwardFailure=yes
        // makes a port collision fail fast instead of lingering with no forwards.
        var args = ["-N", "-o", "ExitOnForwardFailure=yes"]
        let forwards = forward.map { [$0] } ?? host.forwards
        for f in forwards { args.append(contentsOf: forwardFlag(f)) }
        args.append(host.alias)
        return args
    }

    public func isAlive(_ pid: Int32) -> Bool { spawner.isAlive(pid: pid) }

    @discardableResult
    public func start(host: HostEntry, forward: Forward?) throws -> Int32 {
        let args = Self.startArguments(host: host, forward: forward)
        let pid = try spawner.spawnDetached(sshPath, args)
        registry.record(LaunchedTunnel(pid: pid, executable: sshPath, arguments: args))
        return pid
    }

    public func kill(_ session: SSHSession) throws {
        try spawner.terminate(pid: session.pid, force: false)
        registry.remove(pid: session.pid)
        let spawner = self.spawner
        let pid = session.pid
        let grace = killGrace
        Task.detached {
            try? await Task.sleep(for: .seconds(grace))
            if spawner.isAlive(pid: pid) { try? spawner.terminate(pid: pid, force: true) }
        }
    }

    public func canRestart(_ session: SSHSession) -> Bool {
        if registry.argv(forPID: session.pid) != nil { return true }
        guard let program = session.rawArgs.first else { return false }
        let base = (program as NSString).lastPathComponent
        return base == "ssh" && session.rawArgs.count > 1
    }

    @discardableResult
    public func restart(_ session: SSHSession) throws -> Int32? {
        let executable: String
        let args: [String]
        if let known = registry.argv(forPID: session.pid) {
            executable = known.0
            args = known.1
        } else {
            guard let program = session.rawArgs.first,
                  (program as NSString).lastPathComponent == "ssh" else { return nil }
            let rest = Array(session.rawArgs.dropFirst())
            guard !rest.isEmpty else { return nil }
            executable = sshPath
            args = rest
        }
        try spawner.terminate(pid: session.pid, force: false)
        registry.remove(pid: session.pid)
        let pid = try spawner.spawnDetached(executable, args)
        registry.record(LaunchedTunnel(pid: pid, executable: executable, arguments: args))
        return pid
    }
}
