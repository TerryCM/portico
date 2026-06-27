import SwiftUI
import PorticoCore

struct SettingsView: View {
    // Type as PorticoCore.Settings: SwiftUI also exports a `Settings` symbol,
    // so a bare `Settings` is ambiguous here.
    @EnvironmentObject var settings: PorticoCore.Settings

    var body: some View {
        Form {
            Slider(value: $settings.pollInterval, in: 1...30, step: 1) {
                Text("Refresh interval")
            } minimumValueLabel: { Text("1s") } maximumValueLabel: { Text("30s") }
            Text("Every \(Int(settings.pollInterval))s").font(.caption).foregroundStyle(.secondary)

            Toggle("Launch at login", isOn: $settings.launchAtLogin)
        }
        .padding(20)
        .frame(width: 360)
    }
}
