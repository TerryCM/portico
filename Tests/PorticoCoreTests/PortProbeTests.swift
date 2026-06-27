import Testing
import Foundation
import Network
@testable import PorticoCore

@Test func localHealthReachableWhenTCPConnects() {
    #expect(PortProbe.health(kind: .local, listenerPresent: true, tcpReachable: true) == .reachable)
}

@Test func localHealthDegradedWhenListenerButNoTCP() {
    #expect(PortProbe.health(kind: .local, listenerPresent: true, tcpReachable: false) == .listenerOnly)
}

@Test func localHealthDownWhenNoListener() {
    #expect(PortProbe.health(kind: .local, listenerPresent: false, tcpReachable: false) == .down)
}

@Test func remoteHealthyWhenListenerPresent() {
    #expect(PortProbe.health(kind: .remote, listenerPresent: true, tcpReachable: false) == .listenerOnly)
    #expect(PortProbe.health(kind: .dynamic, listenerPresent: false, tcpReachable: false) == .down)
}

@Test func parsesListeningPortsFromLsof() {
    let lsof = """
    ssh     701 terry    7u  IPv4 0x0      0t0  TCP 127.0.0.1:5501 (LISTEN)
    ssh     701 terry    9u  IPv6 0x0      0t0  TCP [::1]:8100 (LISTEN)
    ssh     701 terry   10u  IPv4 0x0      0t0  TCP 127.0.0.1:55012->1.2.3.4:22 (ESTABLISHED)
    """
    let ports = PortProbe.parseListeners(lsofOutput: lsof)
    #expect(ports.contains(5501))
    #expect(ports.contains(8100))
    #expect(ports.contains(55012) == false) // not a LISTEN row
}

@Test func tcpConnectSucceedsAgainstOpenPort() async throws {
    // Open an ephemeral listener, probe it, then tear down.
    let listener = try NWListener(using: .tcp, on: .any)
    listener.newConnectionHandler = { $0.cancel() }
    let ready = AsyncStream<UInt16> { cont in
        listener.stateUpdateHandler = { state in
            if case .ready = state, let p = listener.port { cont.yield(p.rawValue); cont.finish() }
        }
    }
    listener.start(queue: .global())
    var port: UInt16 = 0
    for await p in ready { port = p }
    defer { listener.cancel() }

    let probe = PortProbe()
    let ok = await probe.tcpConnect(host: "127.0.0.1", port: Int(port))
    #expect(ok == true)
}

@Test func tcpConnectFailsAgainstClosedPort() async {
    let probe = PortProbe(connectTimeout: 0.3)
    let ok = await probe.tcpConnect(host: "127.0.0.1", port: 1) // port 1 closed
    #expect(ok == false)
}

@Test func tcpConnectReturnsFalseForOutOfRangePort() async {
    let probe = PortProbe()
    #expect(await probe.tcpConnect(host: "127.0.0.1", port: 70000) == false)
    #expect(await probe.tcpConnect(host: "127.0.0.1", port: -1) == false)
}

@Test func probeClassifiesForwardsUsingInjectedLsof() async {
    let fake = FakeCommandRunner()
    fake.stdoutByExecutable["/usr/sbin/lsof"] =
        "ssh 1 t 7u IPv4 0 0t0 TCP 127.0.0.1:5501 (LISTEN)\n"
    let probe = PortProbe(runner: fake, connectTimeout: 0.3)
    let remote = Forward(kind: .remote, bindAddress: nil, bindPort: 5501,
                         targetHost: "localhost", targetPort: 5501)
    let missing = Forward(kind: .remote, bindAddress: nil, bindPort: 9999,
                          targetHost: "localhost", targetPort: 9999)
    let health = await probe.probe([remote, missing])
    #expect(health[remote.id] == .listenerOnly)
    #expect(health[missing.id] == .down)
}
