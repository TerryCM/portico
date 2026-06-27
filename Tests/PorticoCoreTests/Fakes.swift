import Foundation
@testable import PorticoCore

final class FakeCommandRunner: CommandRunner, @unchecked Sendable {
    var stdoutByExecutable: [String: String] = [:]
    var exitByExecutable: [String: Int32] = [:]
    var throwOnExecutable: Set<String> = []
    private(set) var calls: [(String, [String])] = []

    struct RunnerError: Error {}

    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        calls.append((executable, arguments))
        if throwOnExecutable.contains(executable) { throw RunnerError() }
        return CommandResult(
            stdout: stdoutByExecutable[executable] ?? "",
            stderr: "",
            exitCode: exitByExecutable[executable] ?? 0
        )
    }
}

final class FakeProcessSpawner: ProcessSpawner, @unchecked Sendable {
    var nextPID: Int32 = 4242
    var alivePIDs: Set<Int32> = []
    var ignoresSIGTERM: Set<Int32> = []
    private(set) var spawned: [(String, [String])] = []
    private(set) var terminated: [(Int32, Bool)] = []

    @discardableResult
    func spawnDetached(_ executable: String, _ arguments: [String]) throws -> Int32 {
        spawned.append((executable, arguments))
        let pid = nextPID
        nextPID += 1
        alivePIDs.insert(pid)
        return pid
    }

    func terminate(pid: Int32, force: Bool) throws {
        terminated.append((pid, force))
        if force || !ignoresSIGTERM.contains(pid) { alivePIDs.remove(pid) }
    }

    func isAlive(pid: Int32) -> Bool { alivePIDs.contains(pid) }
}
