import Foundation

// One row in the unified ports list: every active local forward on the machine,
// whether Portico manages it or it belongs to another tool (Warp, VS Code, …).
public struct ActivePort: Identifiable, Equatable, Sendable {
    public let localPort: Int
    public let owner: String        // host label, "Warp", or "ssh"
    public let pid: Int32
    public let managed: Bool        // Portico added it → removable, remote known
    public let remote: String?      // "host:port" when known (managed forwards)
    public let health: ForwardHealth
    public var id: Int { localPort }
    public var localURL: String { "http://localhost:\(localPort)" }
}

@MainActor
public final class PortsModel: ObservableObject {
    @Published public private(set) var activePorts: [ActivePort] = []
    @Published public var lastError: String?

    private let store: ForwardStore
    private let forwarder: PortForwarder
    private let forwardScanner: ForwardScanner
    private let processScanner: ProcessScanner
    private let probe: PortProbe
    private let catalogLoader: @Sendable () -> [HostEntry]
    private var timer: Timer?

    public init(store: ForwardStore,
                forwarder: PortForwarder,
                forwardScanner: ForwardScanner = ForwardScanner(),
                processScanner: ProcessScanner = ProcessScanner(),
                probe: PortProbe = PortProbe(),
                catalogLoader: @escaping @Sendable () -> [HostEntry] = { [] }) {
        self.store = store
        self.forwarder = forwarder
        self.forwardScanner = forwardScanner
        self.processScanner = processScanner
        self.probe = probe
        self.catalogLoader = catalogLoader
    }

    public func start(interval: TimeInterval = 4) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    public func add(host: String, remoteHost: String, remotePort: Int, localPort: Int?) -> Int? {
        let lp = localPort ?? FreePort.find() ?? remotePort
        let f = ManagedForward(host: host, localPort: lp, remoteHost: remoteHost, remotePort: remotePort)
        do {
            try forwarder.add(f)
            store.add(f)
            lastError = nil
            Task { await refresh() }
            return lp
        } catch {
            lastError = "Couldn’t forward \(remoteHost):\(remotePort) → localhost:\(lp): \(error)"
            return nil
        }
    }

    public func remove(_ port: ActivePort) {
        guard port.managed,
              let m = store.all().first(where: { $0.localPort == port.localPort }) else { return }
        try? forwarder.remove(m)
        store.remove(m)
        Task { await refresh() }
    }

    public func refresh() async {
        let fs = forwardScanner
        let ps = processScanner
        let loader = catalogLoader
        let detected = await Task.detached { fs.scan() }.value
        let sessions = await Task.detached { (try? ps.scan()) ?? [] }.value
        let catalog = await Task.detached { loader() }.value
        var hostByPID: [Int32: String] = [:]
        for s in sessions { hostByPID[s.pid] = s.host }
        // host alias -> (localBindPort -> "remoteHost:remotePort"), from ~/.ssh/config,
        // so external (config-driven) forwards can show their remote side too.
        var configRemote: [String: [Int: String]] = [:]
        for h in catalog {
            var byPort: [Int: String] = [:]
            for f in h.forwards where f.kind == .local {
                byPort[f.bindPort] = "\(f.targetHost ?? ""):\(f.targetPort ?? 0)"
            }
            configRemote[h.alias] = byPort
        }
        let managed = store.all()
        var managedByPort: [Int: ManagedForward] = [:]
        for m in managed { managedByPort[m.localPort] = m }

        var reachable: [Int: Bool] = [:]
        await withTaskGroup(of: (Int, Bool).self) { group in
            for d in detected {
                group.addTask { (d.localPort, await self.probe.tcpConnect(host: "127.0.0.1", port: d.localPort)) }
            }
            for await (port, ok) in group { reachable[port] = ok }
        }

        var rows: [ActivePort] = []
        for d in detected {
            let m = managedByPort[d.localPort]
            let owner: String
            if let host = hostByPID[d.pid] {
                owner = host == "placeholder" ? "Warp" : host
            } else {
                owner = m?.host ?? "ssh"
            }
            // Remote side: managed forwards know it directly; for external ones,
            // recover it from the owning host's ssh config when available.
            let remote = m.map { "\($0.remoteHost):\($0.remotePort)" }
                ?? configRemote[owner]?[d.localPort]
            rows.append(ActivePort(
                localPort: d.localPort, owner: owner, pid: d.pid,
                managed: m != nil,
                remote: remote,
                health: (reachable[d.localPort] ?? false) ? .reachable : .listenerOnly))
        }
        // Managed forwards whose listener isn't up (just added, or dropped).
        for m in managed where !detected.contains(where: { $0.localPort == m.localPort }) {
            rows.append(ActivePort(
                localPort: m.localPort, owner: m.host, pid: 0, managed: true,
                remote: "\(m.remoteHost):\(m.remotePort)", health: .down))
        }
        activePorts = rows.sorted { $0.localPort < $1.localPort }
    }
}
