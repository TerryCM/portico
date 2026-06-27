import SwiftUI
import AppKit
import PorticoCore

@main
struct PorticoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: MonitorStore
    // Disambiguate: SwiftUI also exports a `Settings` scene type.
    @StateObject private var settings: PorticoCore.Settings
    private let controller: TunnelController

    init() {
        let settings = PorticoCore.Settings()
        let scanner = ProcessScanner()
        let probe = PortProbe()
        let catalog = SSHConfigCatalog()
        let configPath = NSHomeDirectory() + "/.ssh/config"

        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Portico", isDirectory: true)
        let registry = LaunchRegistry(fileURL: appSupport.appendingPathComponent("registry.json"))
        self.controller = TunnelController(registry: registry)

        let store = MonitorStore(
            scanner: scanner,
            probe: probe,
            catalogLoader: { catalog.load(path: configPath) },
            settings: settings
        )
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: store)

        // Start polling at launch so the menu-bar icon reflects health before the
        // dropdown is first opened; MenuBarView's .task re-call is a no-op (start
        // calls stop first).
        Task { @MainActor in store.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: controller)
                .environmentObject(store)
                .environmentObject(settings)
        } label: {
            Image(systemName: menuBarSymbol(store.aggregate))
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings {
            SettingsView().environmentObject(settings)
        }
    }

    private func menuBarSymbol(_ health: AggregateHealth) -> String {
        switch health {
        case .empty: return "point.3.connected.trianglepath.dotted"
        case .green: return "point.3.filled.connected.trianglepath.dotted"
        case .yellow: return "exclamationmark.triangle"
        case .red: return "exclamationmark.octagon"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar only, no Dock icon
    }
}
