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

@Test func forwardScannerDedupesByPortAndCapturesPID() {
    let lsof = """
    ssh   55985 terry 10u IPv4 0x0 0t0 TCP 127.0.0.1:8100 (LISTEN)
    ssh   55985 terry 12u IPv6 0x0 0t0 TCP [::1]:8100 (LISTEN)
    ssh   55985 terry 14u IPv4 0x0 0t0 TCP 127.0.0.1:3000 (LISTEN)
    node  4242  terry  5u IPv4 0x0 0t0 TCP *:5173 (LISTEN)
    ssh   55985 terry 16u IPv4 0x0 0t0 TCP 127.0.0.1:55012->1.2.3.4:22 (ESTABLISHED)
    """
    let found = ForwardScanner.parse(lsofOutput: lsof)
    #expect(found.count == 2) // 8100 (deduped), 3000; node and ESTABLISHED excluded
    #expect(found.contains { $0.localPort == 8100 && $0.pid == 55985 })
    #expect(found.contains { $0.localPort == 3000 })
    #expect(found.contains { $0.localPort == 5173 } == false)
}

@MainActor @Test func portsModelMergesDetectedAndManaged() async {
    let runner = FakeCommandRunner()
    runner.exitByExecutable["/usr/bin/ssh"] = 0
    // lsof reports an external forward (8100, owned by a terry ssh pid 55985)
    runner.stdoutByExecutable["/usr/sbin/lsof"] =
        "ssh 55985 t 10u IPv4 0 0t0 TCP 127.0.0.1:8100 (LISTEN)\n"
    // ps reports that pid 55985 is the terry session
    runner.stdoutByExecutable["/bin/ps"] = "55985 1 10:00 ssh -o ControlMaster=yes terry\n"
    let mgr = ControlMasterManager(runner: runner, controlDir: tempDir())
    let forwarder = PortForwarder(runner: runner, master: mgr)
    let store = ForwardStore(fileURL: tempDir().appendingPathComponent("f.json"))
    let model = PortsModel(
        store: store, forwarder: forwarder,
        forwardScanner: ForwardScanner(runner: runner),
        processScanner: ProcessScanner(runner: runner),
        probe: PortProbe(runner: runner, connectTimeout: 0.2))

    let chosen = model.add(host: "jump", remoteHost: "localhost", remotePort: 3000, localPort: 7777)
    #expect(chosen == 7777)
    await model.refresh()

    // External forward shows, labeled by its owning session, not managed.
    let external = model.activePorts.first { $0.localPort == 8100 }
    #expect(external?.owner == "terry")
    #expect(external?.managed == false)
    // Managed forward shows even though lsof didn't report it (listener not up here).
    let managed = model.activePorts.first { $0.localPort == 7777 }
    #expect(managed?.managed == true)
    #expect(managed?.owner == "jump")
}

@MainActor @Test func externalForwardRecoversRemoteFromConfig() async {
    let runner = FakeCommandRunner()
    runner.stdoutByExecutable["/usr/sbin/lsof"] =
        "ssh 55985 t 10u IPv4 0 0t0 TCP 127.0.0.1:2024 (LISTEN)\n"
    runner.stdoutByExecutable["/bin/ps"] = "55985 1 10:00 ssh terry\n"
    let mgr = ControlMasterManager(runner: runner, controlDir: tempDir())
    let forwarder = PortForwarder(runner: runner, master: mgr)
    let store = ForwardStore(fileURL: tempDir().appendingPathComponent("f.json"))
    let terry = HostEntry(alias: "terry", hostName: nil, user: nil,
                          forwards: [Forward(kind: .local, bindAddress: nil, bindPort: 2024,
                                             targetHost: "localhost", targetPort: 2024)])
    let model = PortsModel(
        store: store, forwarder: forwarder,
        forwardScanner: ForwardScanner(runner: runner),
        processScanner: ProcessScanner(runner: runner),
        probe: PortProbe(runner: runner, connectTimeout: 0.2),
        catalogLoader: { [terry] })
    await model.refresh()
    let row = model.activePorts.first { $0.localPort == 2024 }
    #expect(row?.owner == "terry")
    #expect(row?.managed == false)
    #expect(row?.remote == "localhost:2024") // both sides, recovered from config
}
