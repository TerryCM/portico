import Testing
import Foundation
@testable import PorticoCore

private let twoSessionPS = """
  701     1   01:00 ssh -L 5501:localhost:5501 terry@host
  812     1   02:00 ssh -R 9000:localhost:3000 build
"""

@Test func aggregateEmptyWhenNoSessions() {
    #expect(MonitorStore.aggregate(sessions: [], forwardHealth: [:]) == .empty)
}

@Test func aggregateRedWhenAnyForwardDown() {
    let s = ProcessScanner.parse(psOutput: twoSessionPS)
    let local = s[0].forwards[0]
    let health = [local.id: ForwardHealth.down]
    #expect(MonitorStore.aggregate(sessions: s, forwardHealth: health) == .red)
}

@Test func aggregateYellowWhenLocalListenerOnly() {
    let s = ProcessScanner.parse(psOutput: twoSessionPS)
    let local = s[0].forwards[0]
    let remote = s[1].forwards[0]
    let health = [local.id: ForwardHealth.listenerOnly, remote.id: ForwardHealth.listenerOnly]
    #expect(MonitorStore.aggregate(sessions: s, forwardHealth: health) == .yellow)
}

@Test func aggregateGreenWhenAllHealthy() {
    let s = ProcessScanner.parse(psOutput: twoSessionPS)
    let local = s[0].forwards[0]
    let remote = s[1].forwards[0]
    // local reachable, remote listenerOnly == healthy for remote
    let health = [local.id: ForwardHealth.reachable, remote.id: ForwardHealth.listenerOnly]
    #expect(MonitorStore.aggregate(sessions: s, forwardHealth: health) == .green)
}

@MainActor @Test func refreshPopulatesSessionsCatalogAndHealth() async {
    let fakePS = FakeCommandRunner()
    fakePS.stdoutByExecutable["/bin/ps"] = twoSessionPS
    fakePS.stdoutByExecutable["/usr/sbin/lsof"] = "ssh 1 t 7u IPv4 0 0t0 TCP 127.0.0.1:9000 (LISTEN)\n"
    let scanner = ProcessScanner(runner: fakePS)
    let probe = PortProbe(runner: fakePS, connectTimeout: 0.2)
    let host = HostEntry(alias: "terry", hostName: nil, user: nil, forwards: [])
    let settings = Settings(defaults: UserDefaults(suiteName: "ms-\(UUID().uuidString)")!,
                            loginItem: NoopLogin())
    let store = MonitorStore(scanner: scanner, probe: probe,
                             catalogLoader: { [host] }, settings: settings)
    await store.refresh()
    #expect(store.sessions.count == 2)
    #expect(store.catalog == [host])
    let remote = store.sessions[1].forwards[0]
    #expect(store.forwardHealth[remote.id] == .listenerOnly)
}

@MainActor @Test func refreshSetsLastErrorAndKeepsPriorStateOnScanThrow() async {
    let fakePS = FakeCommandRunner()
    fakePS.stdoutByExecutable["/bin/ps"] = twoSessionPS
    fakePS.stdoutByExecutable["/usr/sbin/lsof"] = "ssh 1 t 7u IPv4 0 0t0 TCP 127.0.0.1:9000 (LISTEN)\n"
    let scanner = ProcessScanner(runner: fakePS)
    let probe = PortProbe(runner: fakePS, connectTimeout: 0.2)
    let host = HostEntry(alias: "terry", hostName: nil, user: nil, forwards: [])
    let settings = Settings(defaults: UserDefaults(suiteName: "ms-\(UUID().uuidString)")!,
                            loginItem: NoopLogin())
    let store = MonitorStore(scanner: scanner, probe: probe,
                             catalogLoader: { [host] }, settings: settings)
    await store.refresh()
    #expect(store.sessions.count == 2)
    #expect(store.lastError == nil)
    let priorSessions = store.sessions

    fakePS.throwOnExecutable = ["/bin/ps"]
    await store.refresh()
    #expect(store.lastError != nil)
    #expect(store.sessions == priorSessions)
}

private struct NoopLogin: LoginItemControlling {
    var isEnabled: Bool { false }
    func setEnabled(_ on: Bool) throws {}
}
