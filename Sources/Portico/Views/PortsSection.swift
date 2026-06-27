import SwiftUI
import AppKit
import PorticoCore

// Inline VS Code-style ports manager: lists the forwards Portico actively
// manages and lets you add/remove/open them on the fly.
struct PortsSection: View {
    @ObservedObject var ports: PortsModel
    let catalog: [HostEntry]

    @State private var host = ""
    @State private var remoteHost = "localhost"
    @State private var remotePort = ""
    @State private var localPort = ""
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Forwarded ports").font(.caption).foregroundStyle(.secondary)

            if ports.activePorts.isEmpty {
                Text("No active forwards.")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                  VStack(alignment: .leading, spacing: 2) {
                    ForEach(ports.activePorts) { p in
                    HStack(spacing: 6) {
                        Circle().fill(color(for: p.health)).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("localhost:\(String(p.localPort))").font(.caption).lineLimit(1)
                            Text(p.remote.map { "\(p.owner) → \($0)" } ?? p.owner)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if !p.managed {
                            Text("ext").font(.caption2).foregroundStyle(.tertiary)
                                .help("Forwarded by \(p.owner), outside Portico")
                        }
                        Button { open(p) } label: { Image(systemName: "safari") }
                            .help("Open http://localhost:\(String(p.localPort))")
                        Button { copy(p) } label: { Image(systemName: "doc.on.doc") }
                            .help("Copy localhost:\(String(p.localPort))")
                        Button { ports.remove(p) } label: { Image(systemName: "xmark.circle.fill") }
                            .help("Remove forward")
                            .disabled(!p.managed)
                            .opacity(p.managed ? 1 : 0.25)
                    }
                    .buttonStyle(.borderless)
                    }
                  }
                }
                .frame(maxHeight: 180)
            }

            if let err = ports.lastError {
                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(2)
            }

            DisclosureGroup(isExpanded: $adding) {
                addForm
            } label: {
                Text("Add port forward").font(.caption)
            }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Host").font(.caption2).foregroundStyle(.secondary)
                Menu(host.isEmpty ? "select…" : host) {
                    ForEach(catalog) { h in Button(h.alias) { host = h.alias } }
                }
                .frame(maxWidth: 120)
            }
            HStack(spacing: 6) {
                TextField("remote host", text: $remoteHost).frame(width: 110)
                TextField("remote port", text: $remotePort).frame(width: 80)
            }
            HStack(spacing: 6) {
                TextField("local port (auto)", text: $localPort).frame(width: 110)
                Button("Add") { submit() }
                    .disabled(host.isEmpty || Int(remotePort) == nil)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.caption)
        .padding(.top, 2)
    }

    private func submit() {
        guard let rp = Int(remotePort) else { return }
        let lp = Int(localPort) // nil => auto
        let rh = remoteHost.trimmingCharacters(in: .whitespaces)
        ports.add(host: host, remoteHost: rh.isEmpty ? "localhost" : rh, remotePort: rp, localPort: lp)
        remotePort = ""; localPort = ""
    }

    private func open(_ p: ActivePort) {
        if let url = URL(string: p.localURL) { NSWorkspace.shared.open(url) }
    }

    private func copy(_ p: ActivePort) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("localhost:\(String(p.localPort))", forType: .string)
    }

    private func color(for h: ForwardHealth) -> Color {
        switch h {
        case .reachable, .listenerOnly: return .green
        case .down: return .red
        case .unknown: return .gray
        }
    }
}
