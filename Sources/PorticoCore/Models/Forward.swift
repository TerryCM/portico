public enum ForwardKind: String, Sendable, Codable {
    case local, remote, dynamic
}

public enum ForwardHealth: String, Sendable {
    case reachable, listenerOnly, down, unknown
}

public struct Forward: Equatable, Sendable, Codable, Identifiable {
    public let kind: ForwardKind
    public let bindAddress: String?
    public let bindPort: Int
    public let targetHost: String?
    public let targetPort: Int?

    public init(kind: ForwardKind, bindAddress: String?, bindPort: Int,
                targetHost: String?, targetPort: Int?) {
        self.kind = kind
        self.bindAddress = bindAddress
        self.bindPort = bindPort
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    public var id: String {
        "\(kind.rawValue):\(bindAddress ?? ""):\(bindPort):\(targetHost ?? ""):\(targetPort.map(String.init) ?? "")"
    }

    // flag is "-L" / "-R" / "-D"; value is the spec after the flag.
    // -L/-R: [bind:]port:host:hostport   -D: [bind:]port
    public static func parse(flag: String, value: String) -> Forward? {
        let kind: ForwardKind
        switch flag {
        case "-L": kind = .local
        case "-R": kind = .remote
        case "-D": kind = .dynamic
        default: return nil
        }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)

        if kind == .dynamic {
            switch parts.count {
            case 1: guard let p = Int(parts[0]) else { return nil }
                return Forward(kind: kind, bindAddress: nil, bindPort: p, targetHost: nil, targetPort: nil)
            case 2: guard let p = Int(parts[1]) else { return nil }
                return Forward(kind: kind, bindAddress: parts[0], bindPort: p, targetHost: nil, targetPort: nil)
            default: return nil
            }
        }

        switch parts.count {
        case 3:
            guard let bp = Int(parts[0]), let tp = Int(parts[2]) else { return nil }
            return Forward(kind: kind, bindAddress: nil, bindPort: bp,
                           targetHost: parts[1], targetPort: tp)
        case 4:
            guard let bp = Int(parts[1]), let tp = Int(parts[3]) else { return nil }
            return Forward(kind: kind, bindAddress: parts[0], bindPort: bp,
                           targetHost: parts[2], targetPort: tp)
        default:
            return nil
        }
    }
}
