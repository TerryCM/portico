import Testing
import Foundation
@testable import PorticoCore

@Test func systemRunnerCapturesStdout() throws {
    let runner = SystemCommandRunner()
    let result = try runner.run("/bin/echo", ["hello world"])
    #expect(result.exitCode == 0)
    #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello world")
}

@Test func systemRunnerReportsNonzeroExit() throws {
    let runner = SystemCommandRunner()
    let result = try runner.run("/bin/sh", ["-c", "exit 3"])
    #expect(result.exitCode == 3)
}

@Test func fakeRunnerReturnsConfiguredOutputAndRecordsCalls() throws {
    let fake = FakeCommandRunner()
    fake.stdoutByExecutable["/bin/ps"] = "PSOUT"
    let r = try fake.run("/bin/ps", ["-axww"])
    #expect(r.stdout == "PSOUT")
    #expect(fake.calls.count == 1)
    #expect(fake.calls[0].1 == ["-axww"])
}

@Test func systemSpawnerSpawnsAndTerminates() throws {
    let spawner = SystemProcessSpawner()
    let pid = try spawner.spawnDetached("/bin/sh", ["-c", "sleep 30"])
    #expect(pid > 0)
    #expect(spawner.isAlive(pid: pid) == true)
    try spawner.terminate(pid: pid, force: true)
    // give the OS a moment to reap
    Thread.sleep(forTimeInterval: 0.2)
    #expect(spawner.isAlive(pid: pid) == false)
}
