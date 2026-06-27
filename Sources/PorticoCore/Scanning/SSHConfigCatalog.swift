import Foundation

public struct SSHConfigCatalog: Sendable {
    public init() {}

    public func load(path: String) -> [HostEntry] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        return Self.parse(configText: text)
    }

    private struct Builder {
        var aliases: [String]
        var hostName: String?
        var user: String?
        var forwards: [Forward] = []
    }

    public static func parse(configText: String) -> [HostEntry] {
        var entries: [HostEntry] = []
        var current: Builder?

        func flush() {
            guard let b = current else { return }
            for alias in b.aliases where alias != "*" && !alias.contains("*") {
                entries.append(HostEntry(alias: alias, hostName: b.hostName,
                                         user: b.user, forwards: b.forwards))
            }
        }

        for rawLine in configText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let keyword = parts.first else { continue }
            let args = Array(parts.dropFirst())

            switch keyword.lowercased() {
            case "host":
                flush()
                current = Builder(aliases: args)
            case "hostname":
                current?.hostName = args.first
            case "user":
                current?.user = args.first
            case "localforward":
                if let f = forward(kind: "-L", args: args) { current?.forwards.append(f) }
            case "remoteforward":
                if let f = forward(kind: "-R", args: args) { current?.forwards.append(f) }
            case "dynamicforward":
                if let f = forward(kind: "-D", args: args) { current?.forwards.append(f) }
            default:
                break
            }
        }
        flush()
        return entries
    }

    // ssh_config forward syntax: "LocalForward 5501 localhost:5501" or
    // "LocalForward 127.0.0.1:5501 localhost:5501"; "DynamicForward 1080".
    private static func forward(kind: String, args: [String]) -> Forward? {
        if kind == "-D" {
            guard let bind = args.first else { return nil }
            return Forward.parse(flag: "-D", value: bind)
        }
        guard args.count >= 2 else { return nil }
        return Forward.parse(flag: kind, value: "\(args[0]):\(args[1])")
    }
}
