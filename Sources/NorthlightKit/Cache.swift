import Foundation

/// Last-good store. The dashboard is always-on and unattended, so a single failed
/// fetch must never blank a tile — it shows the previous value with a stale age
/// instead. Writes are best-effort; a cache failure is never surfaced as an error.
public struct Cache: Sendable {
    let directory: URL

    public init(name: String = "Northlight") {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.init(directory: base.appendingPathComponent(name, isDirectory: true))
    }

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Deletes everything stored here, subdirectories included.
    func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    func url(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    @concurrent public func save<T: Codable & Sendable>(_ value: T, as key: String) async {
        guard let data = try? JSONEncoder().encode(Stamped(fetchedAt: Date(), value: value)) else { return }
        try? data.write(to: url(for: key), options: .atomic)
    }

    @concurrent func remove(_ key: String) async {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    @concurrent public func load<T: Codable & Sendable>(_ type: T.Type, as key: String) async -> (value: T, fetchedAt: Date)? {
        guard let data = try? Data(contentsOf: url(for: key)),
              let stamped = try? JSONDecoder().decode(Stamped<T>.self, from: data)
        else { return nil }
        return (stamped.value, stamped.fetchedAt)
    }

    struct Stamped<T>: Codable where T: Codable {
        var fetchedAt: Date
        var value: T
    }
}
