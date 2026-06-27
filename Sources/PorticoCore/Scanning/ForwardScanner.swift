import Foundation

// A local port forward discovered from the system, regardless of who created it
// (Portico, Warp, VS Code, a manual `ssh -L`, or a config-driven forward). These
// are found via lsof, so forwards that never appear on an ssh command line still
// show up.
public struct DetectedForward: Equatable, Sendable {
    public let localPort: Int
    public let pid: Int32
    public let bindAddress: String
    public init(localPort: Int, pid: Int32, bindAddress: String) {
        self.localPort = localPort
        self.pid = pid
        self.bindAddress = bindAddress
    }
}

public struct ForwardScanner: Sendable {
    private let runner: CommandRunner

    public init(runner: CommandRunner = SystemCommandRunner()) {
        self.runner = runner
    }

    public func scan() -> [DetectedForward] {
        guard let r = try? runner.run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"])
        else { return [] }
        return Self.parse(lsofOutput: r.stdout)
    }

    // Keep one entry per local port (a forward usually binds both IPv4 and IPv6).
    public static func parse(lsofOutput: String) -> [DetectedForward] {
        var seen = Set<Int>()
        var result: [DetectedForward] = []
        for raw in lsofOutput.split(separator: "\n") {
            let fields = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.first == "ssh",
                  fields.count >= 2, let pid = Int32(fields[1]),
                  let listenIdx = fields.firstIndex(of: "(LISTEN)"), listenIdx >= 1
            else { continue }
            let addrPort = fields[listenIdx - 1] // e.g. 127.0.0.1:8100, [::1]:8100, *:8100
            guard let colon = addrPort.lastIndex(of: ":"),
                  let port = Int(addrPort[addrPort.index(after: colon)...])
            else { continue }
            if seen.insert(port).inserted {
                result.append(DetectedForward(
                    localPort: port, pid: pid,
                    bindAddress: String(addrPort[..<colon])))
            }
        }
        return result
    }
}
