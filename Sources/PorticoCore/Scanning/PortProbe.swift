import Foundation
import Network

public struct PortProbe: Sendable {
    private let runner: CommandRunner
    private let connectTimeout: TimeInterval

    public init(runner: CommandRunner = SystemCommandRunner(), connectTimeout: TimeInterval = 0.5) {
        self.runner = runner
        self.connectTimeout = connectTimeout
    }

    public static func health(kind: ForwardKind, listenerPresent: Bool, tcpReachable: Bool) -> ForwardHealth {
        switch kind {
        case .local:
            if tcpReachable { return .reachable }
            return listenerPresent ? .listenerOnly : .down
        case .remote, .dynamic:
            return listenerPresent ? .listenerOnly : .down
        }
    }

    public static func parseListeners(lsofOutput: String) -> Set<Int> {
        var ports: Set<Int> = []
        for line in lsofOutput.split(separator: "\n") {
            guard line.contains("(LISTEN)") else { continue }
            // find the TCP token "addr:port" before "(LISTEN)"
            for token in line.split(separator: " ") {
                if let colon = token.lastIndex(of: ":"),
                   let port = Int(token[token.index(after: colon)...]) {
                    ports.insert(port)
                }
            }
        }
        return ports
    }

    public func probe(_ forwards: [Forward]) async -> [String: ForwardHealth] {
        let listeners = listeningPorts()
        var result: [String: ForwardHealth] = [:]
        await withTaskGroup(of: (String, ForwardHealth).self) { group in
            for f in forwards {
                let present = listeners.contains(f.bindPort)
                group.addTask {
                    var reachable = false
                    if f.kind == .local && present {
                        reachable = await tcpConnect(host: f.bindAddress ?? "127.0.0.1",
                                                     port: f.bindPort)
                    }
                    return (f.id, Self.health(kind: f.kind, listenerPresent: present,
                                              tcpReachable: reachable))
                }
            }
            for await pair in group { result[pair.0] = pair.1 }
        }
        return result
    }

    private func listeningPorts() -> Set<Int> {
        guard let out = try? runner.run("/usr/sbin/lsof",
                                        ["-nP", "-iTCP", "-sTCP:LISTEN"]) else { return [] }
        return Self.parseListeners(lsofOutput: out.stdout)
    }

    public func tcpConnect(host: String, port: Int) async -> Bool {
        guard let raw = UInt16(exactly: port), let nwPort = NWEndpoint.Port(rawValue: raw) else { return false }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let conn = NWConnection(to: endpoint, using: .tcp)
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let resumed = LockedFlag()
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.setTrue() { conn.cancel(); cont.resume(returning: true) }
                case .failed, .cancelled:
                    if resumed.setTrue() { conn.cancel(); cont.resume(returning: false) }
                default:
                    break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + connectTimeout) {
                if resumed.setTrue() { conn.cancel(); cont.resume(returning: false) }
            }
        }
    }
}

// Ensures the continuation resumes exactly once across racing callbacks.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func setTrue() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
