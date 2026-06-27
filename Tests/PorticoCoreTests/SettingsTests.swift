import Testing
import Foundation
@testable import PorticoCore

private final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    var isEnabled: Bool = false
    func setEnabled(_ on: Bool) throws { isEnabled = on }
}

private func freshDefaults() -> UserDefaults {
    let suite = "portico-test-\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

@Test func clampsIntervalToRange() {
    #expect(Settings.clampInterval(0.1) == 1)
    #expect(Settings.clampInterval(3) == 3)
    #expect(Settings.clampInterval(99) == 30)
}

@MainActor @Test func persistsPollIntervalClamped() {
    let defaults = freshDefaults()
    let s = Settings(defaults: defaults, loginItem: FakeLoginItem())
    s.pollInterval = 99
    #expect(s.pollInterval == 30)
    #expect(defaults.double(forKey: "pollInterval") == 30)

    let reloaded = Settings(defaults: defaults, loginItem: FakeLoginItem())
    #expect(reloaded.pollInterval == 30)
}

@MainActor @Test func defaultsToThreeSeconds() {
    let s = Settings(defaults: freshDefaults(), loginItem: FakeLoginItem())
    #expect(s.pollInterval == 3)
}

@MainActor @Test func togglingLaunchAtLoginCallsLoginItem() {
    let login = FakeLoginItem()
    let s = Settings(defaults: freshDefaults(), loginItem: login)
    s.launchAtLogin = true
    #expect(login.isEnabled == true)
}
