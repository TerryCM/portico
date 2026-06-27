import Foundation
import ServiceManagement

public protocol LoginItemControlling: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ on: Bool) throws
}

public struct SMAppLoginItem: LoginItemControlling {
    public init() {}
    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    public func setEnabled(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
}

@MainActor
public final class Settings: ObservableObject {
    private let defaults: UserDefaults
    private let loginItem: LoginItemControlling
    private var loading = false

    @Published public var pollInterval: TimeInterval {
        didSet {
            guard !loading else { return }
            let clamped = Self.clampInterval(pollInterval)
            if clamped != pollInterval { pollInterval = clamped; return }
            defaults.set(clamped, forKey: "pollInterval")
        }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            guard !loading else { return }
            try? loginItem.setEnabled(launchAtLogin)
        }
    }

    public init(defaults: UserDefaults = .standard,
                loginItem: LoginItemControlling = SMAppLoginItem()) {
        self.defaults = defaults
        self.loginItem = loginItem
        self.loading = true
        let stored = defaults.object(forKey: "pollInterval") as? Double
        self.pollInterval = stored.map(Self.clampInterval) ?? 3
        self.launchAtLogin = loginItem.isEnabled
        self.loading = false
    }

    public nonisolated static func clampInterval(_ v: TimeInterval) -> TimeInterval {
        min(max(v, 1), 30)
    }
}
