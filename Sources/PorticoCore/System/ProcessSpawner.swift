import Foundation

public protocol ProcessSpawner: Sendable {
    @discardableResult
    func spawnDetached(_ executable: String, _ arguments: [String]) throws -> Int32
    func terminate(pid: Int32, force: Bool) throws
    func isAlive(pid: Int32) -> Bool
}

public struct SystemProcessSpawner: ProcessSpawner {
    public init() {}

    @discardableResult
    public func spawnDetached(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Detach stdio so the child is not tied to our pipes.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process.processIdentifier
    }

    public func terminate(pid: Int32, force: Bool) throws {
        let sig = force ? SIGKILL : SIGTERM
        if kill(pid, sig) != 0 && errno != ESRCH {
            throw POSIXError(.init(rawValue: errno) ?? .EPERM)
        }
    }

    public func isAlive(pid: Int32) -> Bool {
        // signal 0 = existence/permission check without delivering a signal
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
