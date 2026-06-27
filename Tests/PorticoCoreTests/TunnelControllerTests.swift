import Testing
import Foundation
@testable import PorticoCore

private func tempReg() -> LaunchRegistry {
    LaunchRegistry(fileURL: FileManager.default.temporaryDirectory
        .appendingPathComponent("portico-tc-\(UUID().uuidString).json"))
}

@Test func startArgumentsBuildsForwardFlags() {
    let host = HostEntry(alias: "terry", hostName: nil, user: nil,
                         forwards: [Forward(kind: .local, bindAddress: nil, bindPort: 5501,
                                            targetHost: "localhost", targetPort: 5501)])
    let args = TunnelController.startArguments(host: host, forward: nil)
    #expect(args == ["-N", "-o", "ExitOnForwardFailure=yes", "-L", "5501:localhost:5501", "terry"])
}

@Test func startArgumentsAreTrackableAndFailFast() {
    let host = HostEntry(alias: "terry", hostName: nil, user: nil, forwards: [])
    let args = TunnelController.startArguments(host: host, forward: nil)
    // No -f: the tunnel must be the spawned process so its pid is trackable.
    #expect(args.contains("-f") == false)
    #expect(args.contains("-fN") == false)
    #expect(args.contains("-N"))
    // Fail fast when a forward port is already bound instead of lingering.
    #expect(args.contains("ExitOnForwardFailure=yes"))
}

@Test func startArgumentsWithSingleForward() {
    let host = HostEntry(alias: "jump", hostName: nil, user: nil, forwards: [])
    let fwd = Forward(kind: .dynamic, bindAddress: nil, bindPort: 1080,
                      targetHost: nil, targetPort: nil)
    let args = TunnelController.startArguments(host: host, forward: fwd)
    #expect(args == ["-N", "-o", "ExitOnForwardFailure=yes", "-D", "1080", "jump"])
}

@Test func startSpawnsSSHAndRecordsRegistry() throws {
    let spawner = FakeProcessSpawner()
    let reg = tempReg()
    let controller = TunnelController(spawner: spawner, registry: reg)
    let host = HostEntry(alias: "terry", hostName: nil, user: nil, forwards: [])
    let pid = try controller.start(host: host, forward: nil)
    #expect(spawner.spawned.count == 1)
    #expect(spawner.spawned[0].0 == "/usr/bin/ssh")
    #expect(spawner.spawned[0].1 == ["-N", "-o", "ExitOnForwardFailure=yes", "terry"])
    #expect(reg.argv(forPID: pid)?.1 == ["-N", "-o", "ExitOnForwardFailure=yes", "terry"])
}

@Test func isAliveReflectsSpawnerState() {
    let spawner = FakeProcessSpawner()
    spawner.alivePIDs = [4242]
    let controller = TunnelController(spawner: spawner, registry: tempReg())
    #expect(controller.isAlive(4242) == true)
    #expect(controller.isAlive(9999) == false)
}

@Test func killTerminatesAndDeregisters() throws {
    let spawner = FakeProcessSpawner()
    let reg = tempReg()
    reg.record(LaunchedTunnel(pid: 700, executable: "/usr/bin/ssh", arguments: ["-fN", "terry"]))
    spawner.alivePIDs = [700]
    let controller = TunnelController(spawner: spawner, registry: reg)
    let session = SSHSession(pid: 700, ppid: 1, user: nil, host: "terry", identityFile: nil,
                             forwards: [], controlPath: nil, elapsed: nil,
                             rawArgs: ["ssh", "-fN", "terry"])
    try controller.kill(session)
    #expect(spawner.terminated.contains { $0.0 == 700 })
    #expect(reg.argv(forPID: 700) == nil)
}

@Test func restartUsesRegistryArgvWhenKnown() throws {
    let spawner = FakeProcessSpawner()
    let reg = tempReg()
    reg.record(LaunchedTunnel(pid: 700, executable: "/usr/bin/ssh", arguments: ["-fN", "-L", "5501:localhost:5501", "terry"]))
    spawner.alivePIDs = [700]
    let controller = TunnelController(spawner: spawner, registry: reg)
    let session = SSHSession(pid: 700, ppid: 1, user: nil, host: "terry", identityFile: nil,
                             forwards: [], controlPath: nil, elapsed: nil,
                             rawArgs: ["ssh", "-fN", "terry"]) // raw differs; registry wins
    let newPID = try controller.restart(session)
    #expect(spawner.terminated.contains { $0.0 == 700 })
    #expect(spawner.spawned[0].1 == ["-fN", "-L", "5501:localhost:5501", "terry"])
    #expect(reg.argv(forPID: newPID!)?.1 == ["-fN", "-L", "5501:localhost:5501", "terry"])
    #expect(reg.argv(forPID: 700) == nil)
}

@Test func restartFallsBackToSessionRawArgs() throws {
    let spawner = FakeProcessSpawner()
    let reg = tempReg() // empty — foreign session
    let controller = TunnelController(spawner: spawner, registry: reg)
    let session = SSHSession(pid: 800, ppid: 1, user: nil, host: "build", identityFile: nil,
                             forwards: [], controlPath: nil, elapsed: nil,
                             rawArgs: ["ssh", "-fN", "build"])
    spawner.alivePIDs = [800]
    let newPID = try controller.restart(session)
    // rawArgs[0] ("ssh") dropped; the rest are passed to sshPath
    #expect(spawner.spawned[0].0 == "/usr/bin/ssh")
    #expect(spawner.spawned[0].1 == ["-fN", "build"])
    #expect(newPID != nil)
}

@Test func canRestartFalseWhenNoReproducibleArgs() {
    let reg = tempReg()
    let controller = TunnelController(spawner: FakeProcessSpawner(), registry: reg)
    let foreign = SSHSession(pid: 900, ppid: 1, user: nil, host: "x", identityFile: nil,
                             forwards: [], controlPath: nil, elapsed: nil, rawArgs: ["ssh"])
    #expect(controller.canRestart(foreign) == false)
}

@Test func restartForeignAutosshReturnsNil() throws {
    let spawner = FakeProcessSpawner()
    let reg = tempReg() // empty — foreign session
    let controller = TunnelController(spawner: spawner, registry: reg)
    let session = SSHSession(pid: 850, ppid: 1, user: nil, host: "jump", identityFile: nil,
                             forwards: [], controlPath: nil, elapsed: nil,
                             rawArgs: ["autossh", "-M", "0", "-N", "-D", "1080", "jump"])
    spawner.alivePIDs = [850]
    let result = try controller.restart(session)
    #expect(result == nil)
    #expect(spawner.spawned.isEmpty)
    #expect(controller.canRestart(session) == false)
}

@Test func killEscalatesToSIGKILLWhenStillAlive() async throws {
    let spawner = FakeProcessSpawner()
    let reg = tempReg()
    spawner.alivePIDs = [700]
    spawner.ignoresSIGTERM = [700]
    let controller = TunnelController(spawner: spawner, registry: reg, killGrace: 0.05)
    let session = SSHSession(pid: 700, ppid: 1, user: nil, host: "terry", identityFile: nil,
                             forwards: [], controlPath: nil, elapsed: nil,
                             rawArgs: ["ssh", "-fN", "terry"])
    try controller.kill(session)
    try await Task.sleep(for: .seconds(0.25))
    #expect(spawner.terminated.contains { $0 == (700, true) })
    #expect(spawner.isAlive(pid: 700) == false)
}

@Test func forwardFlagBuildsRemoteWithBindAddress() {
    let fwd = Forward(kind: .remote, bindAddress: "127.0.0.1", bindPort: 9000,
                      targetHost: "localhost", targetPort: 3000)
    #expect(TunnelController.forwardFlag(fwd) == ["-R", "127.0.0.1:9000:localhost:3000"])
    let host = HostEntry(alias: "build", hostName: nil, user: nil, forwards: [fwd])
    let args = TunnelController.startArguments(host: host, forward: nil)
    #expect(args == ["-N", "-o", "ExitOnForwardFailure=yes", "-R", "127.0.0.1:9000:localhost:3000", "build"])
}
