import Testing
import Foundation
@testable import PorticoCore

private func tempURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("portico-reg-\(UUID().uuidString).json")
}

@Test func recordsAndPersistsAcrossInstances() {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let reg = LaunchRegistry(fileURL: url)
    reg.record(LaunchedTunnel(pid: 100, executable: "/usr/bin/ssh", arguments: ["-fN", "terry"]))
    reg.record(LaunchedTunnel(pid: 200, executable: "/usr/bin/ssh", arguments: ["-fN", "jump"]))

    let reloaded = LaunchRegistry(fileURL: url)
    #expect(reloaded.all().count == 2)
    let argv = reloaded.argv(forPID: 100)
    #expect(argv?.0 == "/usr/bin/ssh")
    #expect(argv?.1 == ["-fN", "terry"])
}

@Test func removesByPID() {
    let url = tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let reg = LaunchRegistry(fileURL: url)
    reg.record(LaunchedTunnel(pid: 100, executable: "/usr/bin/ssh", arguments: ["-fN", "terry"]))
    reg.remove(pid: 100)
    #expect(reg.all().isEmpty)
    #expect(reg.argv(forPID: 100) == nil)
}
