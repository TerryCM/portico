import Foundation
import Combine

public enum AggregateHealth: Sendable {
    case empty, green, yellow, red
}

@MainActor
public final class MonitorStore: ObservableObject {
    @Published public private(set) var sessions: [SSHSession] = []
    @Published public private(set) var catalog: [HostEntry] = []
    @Published public private(set) var forwardHealth: [String: ForwardHealth] = [:]
    @Published public private(set) var lastError: String?
    // Result of the last kill/restart/start. Lives here (not in the view) so it
    // survives the menu-bar panel closing when an action is picked from a submenu.
    @Published public private(set) var actionMessage: String?

    private let scanner: ProcessScanner
    private let probe: PortProbe
    private let catalogLoader: @Sendable () -> [HostEntry]
    private let settings: Settings
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    public init(scanner: ProcessScanner,
                probe: PortProbe,
                catalogLoader: @escaping @Sendable () -> [HostEntry],
                settings: Settings) {
        self.scanner = scanner
        self.probe = probe
        self.catalogLoader = catalogLoader
        self.settings = settings
        settings.$pollInterval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.rescheduleIfRunning() }
            }
            .store(in: &cancellables)
    }

    public func report(_ message: String?) { actionMessage = message }

    public var aggregate: AggregateHealth {
        Self.aggregate(sessions: sessions, forwardHealth: forwardHealth)
    }

    public func refresh() async {
        let scanner = self.scanner
        let probe = self.probe
        let loader = self.catalogLoader
        do {
            let scanned = try await Task.detached { try scanner.scan() }.value
            let allForwards = scanned.flatMap { $0.forwards }
            let health = await probe.probe(allForwards)
            let hosts = await Task.detached { loader() }.value
            self.sessions = scanned
            self.forwardHealth = health
            self.catalog = hosts
            self.lastError = nil
        } catch {
            self.lastError = String(describing: error)
        }
    }

    @MainActor private func rescheduleIfRunning() {
        if timer != nil { start() }
    }

    public func start() {
        stop()
        let t = Timer.scheduledTimer(withTimeInterval: settings.pollInterval,
                                     repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
        self.timer = t
        Task { await refresh() }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public nonisolated static func aggregate(sessions: [SSHSession],
                                             forwardHealth: [String: ForwardHealth]) -> AggregateHealth {
        if sessions.isEmpty { return .empty }
        var sawYellow = false
        for session in sessions {
            for f in session.forwards {
                switch forwardHealth[f.id] ?? .unknown {
                case .down: return .red
                case .listenerOnly where f.kind == .local: sawYellow = true
                default: break
                }
            }
        }
        return sawYellow ? .yellow : .green
    }
}
