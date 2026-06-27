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

            if ports.forwards.isEmpty {
                Text("None yet — add one below.")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                ForEach(ports.forwards) { f in
                    HStack(spacing: 6) {
                        Circle().fill(color(for: ports.health[f.id] ?? .unknown))
                            .frame(width: 6, height: 6)
                        Text("localhost:\(String(f.localPort)) → \(f.remoteHost):\(String(f.remotePort))")
                            .font(.caption).lineLimit(1)
                        Spacer(minLength: 4)
                        Button { open(f) } label: { Image(systemName: "safari") }
                            .help("Open in browser")
                        Button { copy(f) } label: { Image(systemName: "doc.on.doc") }
                            .help("Copy localhost:\(String(f.localPort))")
                        Button { ports.remove(f) } label: { Image(systemName: "xmark.circle.fill") }
                            .help("Remove forward")
                    }
                    .buttonStyle(.borderless)
                }
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

    private func open(_ f: ManagedForward) {
        if let url = URL(string: f.localURL) { NSWorkspace.shared.open(url) }
    }

    private func copy(_ f: ManagedForward) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("localhost:\(String(f.localPort))", forType: .string)
    }

    private func color(for h: ForwardHealth) -> Color {
        switch h {
        case .reachable, .listenerOnly: return .green
        case .down: return .red
        case .unknown: return .gray
        }
    }
}
