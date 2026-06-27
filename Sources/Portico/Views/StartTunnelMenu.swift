import SwiftUI
import PorticoCore

struct StartTunnelMenu: View {
    let catalog: [HostEntry]
    let onStart: (HostEntry) -> Void

    var body: some View {
        Menu("Start tunnel") {
            if catalog.isEmpty {
                Text("No hosts in ~/.ssh/config").foregroundStyle(.secondary)
            } else {
                ForEach(catalog) { host in
                    Button("\(host.alias)\(host.forwards.isEmpty ? "" : " (\(host.forwards.count) fwd)")") {
                        onStart(host)
                    }
                }
            }
        }
    }
}
