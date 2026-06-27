import Foundation

public struct ProcessScanner: Sendable {
    private let runner: CommandRunner

    public init(runner: CommandRunner = SystemCommandRunner()) {
        self.runner = runner
    }

    public func scan() throws -> [SSHSession] {
        let result = try runner.run("/bin/ps", ["-axww", "-o", "pid=,ppid=,etime=,command="])
        return Self.parse(psOutput: result.stdout)
    }

    // ssh options that take an argument (so the following token is consumed, not the host).
    private static let argTakingFlags: Set<Character> = [
        "B","b","c","D","E","e","F","I","i","J","L","l","m","O","o","P","p","Q","R","S","W","w"
    ]

    public static func parse(psOutput: String) -> [SSHSession] {
        psOutput.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            parseLine(String(line))
        }
    }

    private static func parseLine(_ line: String) -> SSHSession? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // pid ppid etime command...
        let head = trimmed.split(separator: " ", maxSplits: 3,
                                 omittingEmptySubsequences: true).map(String.init)
        guard head.count == 4,
              let pid = Int32(head[0]),
              let ppid = Int32(head[1]) else { return nil }
        let elapsed = head[2]
        let command = head[3]
        let tokens = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let program = tokens.first else { return nil }
        let base = (program as NSString).lastPathComponent
        guard base == "ssh" || base == "autossh" else { return nil }

        var forwards: [Forward] = []
        var user: String? = nil
        var identityFile: String? = nil
        var controlPath: String? = nil
        var host: String? = nil

        var i = 1
        while i < tokens.count {
            let tok = tokens[i]
            if tok.hasPrefix("-") && tok.count >= 2 {
                let flagChar = tok[tokens[i].index(tok.startIndex, offsetBy: 1)]
                let inlineValue = String(tok.dropFirst(2))
                func nextValue() -> String? {
                    if !inlineValue.isEmpty { return inlineValue }
                    if i + 1 < tokens.count { i += 1; return tokens[i] }
                    return nil
                }
                switch flagChar {
                case "L", "R", "D":
                    if let v = nextValue(), let f = Forward.parse(flag: "-\(flagChar)", value: v) {
                        forwards.append(f)
                    }
                case "i":
                    identityFile = nextValue()
                case "l":
                    user = nextValue()
                case "o":
                    if let v = nextValue(), v.hasPrefix("ControlPath=") {
                        controlPath = String(v.dropFirst("ControlPath=".count))
                    }
                default:
                    // ssh's -M is no-arg master mode; only autossh's -M takes a monitor port.
                    if argTakingFlags.contains(flagChar) || (flagChar == "M" && base == "autossh") {
                        _ = nextValue()
                    }
                }
            } else if host == nil {
                // first bare token is [user@]destination
                if let at = tok.lastIndex(of: "@") {
                    if user == nil { user = String(tok[tok.startIndex..<at]) }
                    host = String(tok[tok.index(after: at)...])
                } else {
                    host = tok
                }
            }
            i += 1
        }

        guard let resolvedHost = host else { return nil }
        // Warp's internal SSH proxy helpers connect to the literal
        // "placeholder@placeholder" over an existing master — noise, not a session.
        if resolvedHost == "placeholder" { return nil }
        return SSHSession(pid: pid, ppid: ppid, user: user, host: resolvedHost,
                          identityFile: identityFile, forwards: forwards,
                          controlPath: controlPath, elapsed: elapsed, rawArgs: tokens)
    }
}
