import Foundation

// Persists the set of Portico-managed forwards (ssh has no "list forwards"
// command, so we remember what we added). JSON at fileURL, lock-guarded.
public final class ForwardStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func all() -> [ManagedForward] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    public func add(_ f: ManagedForward) {
        lock.lock(); defer { lock.unlock() }
        var items = load().filter { $0.id != f.id }
        items.append(f)
        save(items)
    }

    public func remove(_ f: ManagedForward) {
        lock.lock(); defer { lock.unlock() }
        save(load().filter { $0.id != f.id })
    }

    private func load() -> [ManagedForward] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([ManagedForward].self, from: data)
        else { return [] }
        return items
    }

    private func save(_ items: [ManagedForward]) {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
