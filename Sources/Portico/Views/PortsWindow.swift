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
                if let remote = p.remote {
                    Text(remote).font(.body.monospaced()).foregroundStyle(.secondary)
                } else {
                    Text("unknown").foregroundStyle(.tertiary)
                        .help("This forward wasn't created by Portico and its remote target isn't in ~/.ssh/config")
                }
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Add a forward").font(.subheadline.bold())
            HStack(alignment: .bottom, spacing: 8) {
                field("1 · Host") {
                    Menu(host.isEmpty ? "select…" : host) {
                        ForEach(store.catalog) { h in Button(h.alias) { host = h.alias } }
                    }.frame(width: 130)
                }
                arrow
                field("2 · Remote (on that host)") {
                    HStack(spacing: 4) {
                        TextField("localhost", text: $remoteHost).frame(width: 110)
                        Text(":").foregroundStyle(.secondary)
                        TextField("port", text: $remotePort).frame(width: 70)
                    }
                }
                arrow
                field("3 · Local port") {
                    TextField("auto", text: $localPort).frame(width: 80)
                }
                Button("Add forward") { submit() }
                    .disabled(host.isEmpty || Int(remotePort) == nil)
                    .padding(.bottom, 1)
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            content()
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").foregroundStyle(.tertiary).padding(.bottom, 4)
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
