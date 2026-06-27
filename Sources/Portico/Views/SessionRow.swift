import SwiftUI
import PorticoCore

struct SessionRow: View {
    let session: SSHSession
    let health: [String: ForwardHealth]
    let canRestart: Bool
    let onKill: () -> Void
    let onRestart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle().fill(rowColor).frame(width: 8, height: 8)
                Text(session.user.map { "\($0)@\(session.host)" } ?? session.host)
                    .fontWeight(.medium)
                Spacer()
                if let e = session.elapsed { Text(e).font(.caption).foregroundStyle(.secondary) }
                Menu {
                    Button("Restart", action: onRestart).disabled(!canRestart)
                    Button("Kill", role: .destructive, action: onKill)
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            ForEach(session.forwards) { f in
                HStack(spacing: 6) {
                    Circle().fill(color(for: health[f.id] ?? .unknown))
                        .frame(width: 6, height: 6)
                    Text(label(for: f)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var rowColor: Color {
        if session.forwards.contains(where: { (health[$0.id] ?? .unknown) == .down }) { return .red }
        if session.forwards.contains(where: {
            ($0.kind == .local) && (health[$0.id] ?? .unknown) == .listenerOnly }) { return .yellow }
        return .green
    }

    private func color(for h: ForwardHealth) -> Color {
        switch h {
        case .reachable, .listenerOnly: return .green
        case .down: return .red
        case .unknown: return .gray
        }
    }

    private func label(for f: Forward) -> String {
        let bind = f.bindAddress ?? "localhost"
        switch f.kind {
        case .local: return "L \(bind):\(f.bindPort) → \(f.targetHost ?? ""):\(f.targetPort ?? 0)"
        case .remote: return "R \(bind):\(f.bindPort) → \(f.targetHost ?? ""):\(f.targetPort ?? 0)"
        case .dynamic: return "D \(bind):\(f.bindPort) (SOCKS)"
        }
    }
}
