import Foundation

@MainActor
public final class PortsModel: ObservableObject {
    @Published public private(set) var forwards: [ManagedForward] = []
    @Published public private(set) var health: [String: ForwardHealth] = [:]
    @Published public var lastError: String?

    private let store: ForwardStore
    private let forwarder: PortForwarder
    private let probe: PortProbe

    public init(store: ForwardStore, forwarder: PortForwarder, probe: PortProbe = PortProbe()) {
        self.store = store
        self.forwarder = forwarder
        self.probe = probe
        self.forwards = store.all()
    }

    // Add a forward. A nil localPort means "pick a free one" (VS Code behavior).
    // Returns the chosen local port on success.
    @discardableResult
    public func add(host: String, remoteHost: String, remotePort: Int, localPort: Int?) -> Int? {
        let lp = localPort ?? FreePort.find() ?? remotePort
        let f = ManagedForward(host: host, localPort: lp, remoteHost: remoteHost, remotePort: remotePort)
        do {
            try forwarder.add(f)
            store.add(f)
            forwards = store.all()
            lastError = nil
            Task { await refresh() }
            return lp
        } catch {
            lastError = "Couldn’t forward \(remoteHost):\(remotePort) → localhost:\(lp): \(error)"
            return nil
        }
    }

    public func remove(_ f: ManagedForward) {
        try? forwarder.remove(f)
        store.remove(f)
        forwards = store.all()
        health[f.id] = nil
        Task { await refresh() }
    }

    public func refresh() async {
        let current = forwards
        let probes = current.map {
            Forward(kind: .local, bindAddress: nil, bindPort: $0.localPort,
                    targetHost: $0.remoteHost, targetPort: $0.remotePort)
        }
        let byForwardID = await probe.probe(probes)
        var result: [String: ForwardHealth] = [:]
        for f in current {
            let key = Forward(kind: .local, bindAddress: nil, bindPort: f.localPort,
                              targetHost: f.remoteHost, targetPort: f.remotePort).id
            result[f.id] = byForwardID[key] ?? .unknown
        }
        health = result
    }
}
