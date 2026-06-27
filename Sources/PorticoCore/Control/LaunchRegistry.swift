import Foundation

public struct LaunchedTunnel: Codable, Equatable, Sendable {
    public let pid: Int32
    public let executable: String
    public let arguments: [String]
    public init(pid: Int32, executable: String, arguments: [String]) {
        self.pid = pid; self.executable = executable; self.arguments = arguments
    }
}

public final class LaunchRegistry: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func all() -> [LaunchedTunnel] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    public func record(_ t: LaunchedTunnel) {
        lock.lock(); defer { lock.unlock() }
        var items = load().filter { $0.pid != t.pid }
        items.append(t)
        save(items)
    }

    public func remove(pid: Int32) {
        lock.lock(); defer { lock.unlock() }
        save(load().filter { $0.pid != pid })
    }

    public func argv(forPID pid: Int32) -> (String, [String])? {
        lock.lock(); defer { lock.unlock() }
        guard let t = load().first(where: { $0.pid == pid }) else { return nil }
        return (t.executable, t.arguments)
    }

    private func load() -> [LaunchedTunnel] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([LaunchedTunnel].self, from: data)
        else { return [] }
        return items
    }

    private func save(_ items: [LaunchedTunnel]) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
