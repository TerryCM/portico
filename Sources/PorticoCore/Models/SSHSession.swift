public struct SSHSession: Equatable, Sendable, Identifiable {
    public let pid: Int32
    public let ppid: Int32
    public let user: String?
    public let host: String
    public let identityFile: String?
    public let forwards: [Forward]
    public let controlPath: String?
    public let elapsed: String?
    public let rawArgs: [String]

    public init(pid: Int32, ppid: Int32, user: String?, host: String,
                identityFile: String?, forwards: [Forward], controlPath: String?,
                elapsed: String?, rawArgs: [String]) {
        self.pid = pid
        self.ppid = ppid
        self.user = user
        self.host = host
        self.identityFile = identityFile
        self.forwards = forwards
        self.controlPath = controlPath
        self.elapsed = elapsed
        self.rawArgs = rawArgs
    }

    public var id: Int32 { pid }
}
