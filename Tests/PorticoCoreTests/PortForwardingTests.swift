import Testing
import Foundation
@testable import PorticoCore

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("portico-pf-\(UUID().uuidString)", isDirectory: true)
}

@Test func managedForwardIDAndURL() {
    let f = ManagedForward(host: "terry", localPort: 8100, remoteHost: "localhost", remotePort: 8100)
    #expect(f.id == "terry:8100")
    #expect(f.localURL == "http://localhost:8100")
}

@Test func freePortReturnsUsablePort() {
    let p = FreePort.find()
    #expect(p != nil)
    #expect((p ?? 0) > 1024)
    #expect((p ?? 0) <= 65535)
}

@Test func controlMasterConnectArgsAreClean() {
    let args = ControlMasterManager.connectArgs(socket: "/tmp/cm.sock", host: "terry")
    #expect(args == ["-M", "-S", "/tmp/cm.sock", "-fN",
                     "-o", "ControlMaster=yes", "-o", "ClearAllForwardings=yes", "terry"])
}

@Test func controlMasterCheckUsesSocket() {
    let args = ControlMasterManager.checkArgs(socket: "/tmp/cm.sock", host: "terry")
    #expect(args == ["-O", "check", "-S", "/tmp/cm.sock", "terry"])
}

@Test func isConnectedReflectsSSHExitCode() {
    let runner = FakeCommandRunner()
    let mgr = ControlMasterManager(runner: runner, controlDir: tempDir())
    runner.exitByExecutable["/usr/bin/ssh"] = 0
    #expect(mgr.isConnected("terry") == true)
    runner.exitByExecutable["/usr/bin/ssh"] = 255
    #expect(mgr.isConnected("terry") == false)
}

@Test func forwardArgsUseDevNullToStayClean() {
    let f = ManagedForward(host: "terry", localPort: 19999, remoteHost: "localhost", remotePort: 22)
    let args = PortForwarder.forwardArgs(socket: "/tmp/cm.sock", f)
    #expect(args == ["-O", "forward", "-F", "/dev/null",
                     "-L", "19999:localhost:22", "-S", "/tmp/cm.sock", "terry"])
}

@Test func cancelArgsMirrorForward() {
    let f = ManagedForward(host: "terry", localPort: 19999, remoteHost: "localhost", remotePort: 22)
    let args = PortForwarder.cancelArgs(socket: "/tmp/cm.sock", f)
    #expect(args == ["-O", "cancel", "-F", "/dev/null",
                     "-L", "19999:localhost:22", "-S", "/tmp/cm.sock", "terry"])
}

@Test func addConnectsMasterThenForwards() throws {
    let runner = FakeCommandRunner()
    runner.exitByExecutable["/usr/bin/ssh"] = 0 // check ok, forward ok
    let mgr = ControlMasterManager(runner: runner, controlDir: tempDir())
    let forwarder = PortForwarder(runner: runner, master: mgr)
    let f = ManagedForward(host: "terry", localPort: 7000, remoteHost: "localhost", remotePort: 3000)
    try forwarder.add(f)
    // last ssh call must be the -O forward with the right -L spec
    let last = runner.calls.last
    #expect(last?.1.contains("forward") == true)
    #expect(last?.1.contains("7000:localhost:3000") == true)
}

@Test func addThrowsWhenForwardFails() {
    let runner = FakeCommandRunner()
    runner.exitByExecutable["/usr/bin/ssh"] = 0 // master check passes
    let mgr = ControlMasterManager(runner: runner, controlDir: tempDir())
    // make only the forward request fail by switching exit after connect check
    final class FailingForward: CommandRunner, @unchecked Sendable {
        var checkedOnce = false
        func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
            if arguments.contains("forward") {
                return CommandResult(stdout: "", stderr: "Port forwarding failed", exitCode: 255)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0) // check -> connected
        }
    }
    let failing = FailingForward()
    let mgr2 = ControlMasterManager(runner: failing, controlDir: tempDir())
    let forwarder = PortForwarder(runner: failing, master: mgr2)
    let f = ManagedForward(host: "terry", localPort: 7000, remoteHost: "localhost", remotePort: 3000)
    #expect(throws: PortForwarderError.self) { try forwarder.add(f) }
    _ = (mgr, runner)
}

@Test func forwardStoreRoundTrips() {
    let url = tempDir().appendingPathComponent("forwards.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = ForwardStore(fileURL: url)
    store.add(ManagedForward(host: "terry", localPort: 7000, remoteHost: "localhost", remotePort: 3000))
    store.add(ManagedForward(host: "jump", localPort: 7001, remoteHost: "localhost", remotePort: 8080))
    let reloaded = ForwardStore(fileURL: url)
    #expect(reloaded.all().count == 2)
    store.remove(ManagedForward(host: "terry", localPort: 7000, remoteHost: "localhost", remotePort: 3000))
    #expect(ForwardStore(fileURL: url).all().map(\.id) == ["jump:7001"])
}

@MainActor @Test func portsModelAddRecordsAndProbes() async {
    let runner = FakeCommandRunner()
    runner.exitByExecutable["/usr/bin/ssh"] = 0
    let mgr = ControlMasterManager(runner: runner, controlDir: tempDir())
    let forwarder = PortForwarder(runner: runner, master: mgr)
    let store = ForwardStore(fileURL: tempDir().appendingPathComponent("f.json"))
    let model = PortsModel(store: store, forwarder: forwarder,
                           probe: PortProbe(runner: runner, connectTimeout: 0.2))
    let chosen = model.add(host: "terry", remoteHost: "localhost", remotePort: 3000, localPort: 7777)
    #expect(chosen == 7777)
    #expect(model.forwards.map(\.id) == ["terry:7777"])
    #expect(model.lastError == nil)
}
