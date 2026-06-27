import SwiftUI
import AppKit
import PorticoCore

struct MenuBarView: View {
    @EnvironmentObject var store: MonitorStore
    // SwiftUI also exports a `Settings` scene type; bind the model explicitly.
    @EnvironmentObject var settings: PorticoCore.Settings
    let controller: TunnelController
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Portico").font(.headline)
                Spacer()
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }

            if store.sessions.isEmpty {
                Text("No active SSH sessions").foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.sessions) { session in
                            SessionRow(
                                session: session,
                                health: store.forwardHealth,
                                canRestart: controller.canRestart(session),
                                onKill: { perform { try controller.kill(session) } },
                                onRestart: { perform { _ = try controller.restart(session) } }
                            )
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 360)
            }

            if let actionError {
                Text(actionError).font(.caption).foregroundStyle(.red)
            }
            if let scanError = store.lastError {
                Text("Scan failed: \(scanError)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()
            StartTunnelMenu(catalog: store.catalog) { host in startTunnel(host) }
            HStack {
                Button("Refresh") { actionError = nil; Task { await store.refresh() } }
                Spacer()
                settingsButton
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 340)
        .task { store.start() }
    }

    // SettingsLink is macOS 14+, but the app targets macOS 13; fall back to the
    // AppKit selector that opens the Settings scene on older systems.
    @ViewBuilder private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink { Text("Settings") }
        } else {
            Button("Settings") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }

    private var statusText: String {
        switch store.aggregate {
        case .empty: return "idle"
        case .green: return "all healthy"
        case .yellow: return "degraded"
        case .red: return "issues"
        }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action(); actionError = nil; Task { await store.refresh() } }
        catch { actionError = String(describing: error) }
    }

    // Start, then check shortly after whether the tunnel survived. An ssh that
    // can't bind its forwards (e.g. those ports are already served by another
    // session) exits fast under ExitOnForwardFailure=yes — surface that instead
    // of leaving the user with no feedback.
    private func startTunnel(_ host: HostEntry) {
        do {
            let pid = try controller.start(host: host, forward: nil)
            actionError = nil
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if !controller.isAlive(pid) {
                    actionError = "Couldn't start \(host.alias): tunnel exited immediately — its forward ports may already be in use."
                }
                await store.refresh()
            }
        } catch {
            actionError = String(describing: error)
        }
    }
}
