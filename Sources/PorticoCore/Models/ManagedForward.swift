// A single port forward that Portico actively manages on a host's ControlMaster
// connection (added/removed via `ssh -O forward`/`-O cancel`). Distinct from the
// read-only `Forward` parsed from a session's argv.
public struct ManagedForward: Codable, Equatable, Sendable, Identifiable {
    public let host: String        // ssh alias the forward lives on
    public let localPort: Int
    public let remoteHost: String  // as seen from the remote (usually "localhost")
    public let remotePort: Int

    public init(host: String, localPort: Int, remoteHost: String, remotePort: Int) {
        self.host = host
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }

    // Unique per (host, localPort): you can't bind the same local port twice.
    public var id: String { "\(host):\(localPort)" }

    public var localURL: String { "http://localhost:\(localPort)" }
}
