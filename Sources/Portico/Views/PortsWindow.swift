import SwiftUI
import AppKit
import PorticoCore

// The full, resizable manager — a real table of every active forward plus an
// add form and a read-only session list. Opened from the menu-bar dropdown.
struct PortsWindow: View {
    @EnvironmentObject var store: MonitorStore
    @EnvironmentObject var ports: PortsModel

    @State private var host = ""
    @State private var remoteHost = "localhost"
    @State private var remotePort = ""
    @State private var localPort = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text("Forwarded ports").font(.headline)
            portsTable

            addForm.padding(.top, 4)

            Divider()
            Text("SSH sessions").font(.headline)
            sessionList
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 460)
    }

    private var header: some View {
        HStack {
            Text("Portico").font(.title2.bold())
            Spacer()
            if let err = ports.lastError {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(1)
            }
            Button { Task { await ports.refresh(); await store.refresh() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    private var portsTable: some View {
        Table(ports.activePorts) {
            TableColumn("") { p in
                Circle().fill(color(for: p.health)).frame(width: 8, height: 8)
            }.width(18)
            TableColumn("Local") { p in
                Text("localhost:\(String(p.localPort))").font(.body.monospaced())
            }
            TableColumn("Owner") { p in Text(p.owner) }
            TableColumn("Remote") { p in
                Text(p.remote ?? (p.managed ? "" : "external")).foregroundStyle(.secondary)
            }
            TableColumn("") { p in
                HStack(spacing: 8) {
                    Button { open(p.localPort) } label: { Image(systemName: "safari") }
                        .help("Open http://localhost:\(String(p.localPort))")
                    Button { copy(p.localPort) } label: { Image(systemName: "doc.on.doc") }
                        .help("Copy localhost:\(String(p.localPort))")
                    Button { ports.remove(p) } label: { Image(systemName: "xmark.circle.fill") }
                        .help("Remove forward").disabled(!p.managed).opacity(p.managed ? 1 : 0.25)
                }
                .buttonStyle(.borderless)
            }.width(96)
        }
        .frame(minHeight: 200)
    }

    private var addForm: some View {
        HStack(spacing: 8) {
            Menu(host.isEmpty ? "Host…" : host) {
                ForEach(store.catalog) { h in Button(h.alias) { host = h.alias } }
            }.frame(width: 130)
            TextField("remote host", text: $remoteHost).frame(width: 120)
            TextField("remote port", text: $remotePort).frame(width: 90)
            TextField("local (auto)", text: $localPort).frame(width: 90)
            Button("Add forward") { submit() }
                .disabled(host.isEmpty || Int(remotePort) == nil)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var sessionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if store.sessions.isEmpty {
                    Text("No active SSH sessions").foregroundStyle(.secondary)
                }
                ForEach(store.sessions) { s in
                    HStack(spacing: 8) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text(s.user.map { "\($0)@\(s.host)" } ?? s.host)
                        if !s.forwards.isEmpty {
                            Text("\(s.forwards.count) fwd").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let e = s.elapsed { Text(e).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .frame(maxHeight: 140)
    }

    private func submit() {
        guard let rp = Int(remotePort) else { return }
        let rh = remoteHost.trimmingCharacters(in: .whitespaces)
        ports.add(host: host, remoteHost: rh.isEmpty ? "localhost" : rh,
                  remotePort: rp, localPort: Int(localPort))
        remotePort = ""; localPort = ""
    }

    private func open(_ port: Int) {
        if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
    }

    private func copy(_ port: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("localhost:\(port)", forType: .string)
    }

    private func color(for h: ForwardHealth) -> Color {
        switch h {
        case .reachable, .listenerOnly: return .green
        case .down: return .red
        case .unknown: return .gray
        }
    }
}
