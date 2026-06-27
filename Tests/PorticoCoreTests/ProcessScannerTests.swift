import Testing
@testable import PorticoCore

private let psFixture = """
  701     1   01:23:45 ssh -L 5501:localhost:5501 -L 8100:terry:8100 -i /Users/t/.ssh/id_rsa terry@host
  812     1   00:00:09 autossh -M 0 -N -D 1080 jump
  990   701   10:10 sshd: terry@notty
 1001     1   05:00 ssh -o ControlPath=/tmp/cm.sock -R 9000:localhost:3000 build
 1500     1   00:01 /usr/bin/grep ssh
"""

@Test func parsesSSHClientLines() {
    let sessions = ProcessScanner.parse(psOutput: psFixture)
    // ssh (701), autossh (812), ssh (1001). sshd and grep excluded.
    #expect(sessions.count == 3)
}

@Test func extractsForwardsHostUserAndIdentity() {
    let s = ProcessScanner.parse(psOutput: psFixture).first { $0.pid == 701 }!
    #expect(s.host == "host")
    #expect(s.user == "terry")
    #expect(s.identityFile == "/Users/t/.ssh/id_rsa")
    #expect(s.elapsed == "01:23:45")
    #expect(s.forwards.count == 2)
    #expect(s.forwards.contains(Forward(kind: .local, bindAddress: nil, bindPort: 5501,
                                        targetHost: "localhost", targetPort: 5501)))
    #expect(s.forwards.contains(Forward(kind: .local, bindAddress: nil, bindPort: 8100,
                                        targetHost: "terry", targetPort: 8100)))
}

@Test func parsesDynamicForwardOnAutossh() {
    let s = ProcessScanner.parse(psOutput: psFixture).first { $0.pid == 812 }!
    #expect(s.host == "jump")
    #expect(s.forwards == [Forward(kind: .dynamic, bindAddress: nil, bindPort: 1080,
                                   targetHost: nil, targetPort: nil)])
}

@Test func capturesControlPath() {
    let s = ProcessScanner.parse(psOutput: psFixture).first { $0.pid == 1001 }!
    #expect(s.controlPath == "/tmp/cm.sock")
    #expect(s.ppid == 1)
    #expect(s.rawArgs.first == "ssh")
}

@Test func excludesSSHDAndNonSSH() {
    let sessions = ProcessScanner.parse(psOutput: psFixture)
    #expect(sessions.contains { $0.pid == 990 } == false)
    #expect(sessions.contains { $0.pid == 1500 } == false)
}

@Test func sshMasterModeDoesNotSwallowDestination() {
    let s = ProcessScanner.parse(psOutput: "  555     1   00:05 ssh -M -L 5501:localhost:5501 host")
        .first { $0.pid == 555 }!
    #expect(s.host == "host")
    #expect(s.forwards.contains(Forward(kind: .local, bindAddress: nil, bindPort: 5501,
                                        targetHost: "localhost", targetPort: 5501)))
}

@Test func sshMasterModeBareDestination() {
    let s = ProcessScanner.parse(psOutput: "  556     1   00:05 ssh -M host")
        .first { $0.pid == 556 }!
    #expect(s.host == "host")
}

@Test func scanRunsPSThroughRunner() throws {
    let fake = FakeCommandRunner()
    fake.stdoutByExecutable["/bin/ps"] = psFixture
    let scanner = ProcessScanner(runner: fake)
    let sessions = try scanner.scan()
    #expect(sessions.count == 3)
    #expect(fake.calls[0].0 == "/bin/ps")
    #expect(fake.calls[0].1 == ["-axww", "-o", "pid=,ppid=,etime=,command="])
}
