public struct HostEntry: Equatable, Sendable, Identifiable {
    public let alias: String
    public let hostName: String?
    public let user: String?
    public let forwards: [Forward]

    public init(alias: String, hostName: String?, user: String?, forwards: [Forward]) {
        self.alias = alias
        self.hostName = hostName
        self.user = user
        self.forwards = forwards
    }

    public var id: String { alias }
}
