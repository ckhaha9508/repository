import Foundation

/// All encoding, backup rotation and disk writes run on one utility queue.
final class LauncherPersistence: @unchecked Sendable {
    let fileURL: URL
    var backupURL: URL { fileURL.appendingPathExtension("backup") }
    private let queue = DispatchQueue(label: "com.nestlauncher.persistence", qos: .utility)

    init(fileURL: URL) { self.fileURL = fileURL }

    static func decode(_ data: Data) throws -> StorePayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(StorePayload.self, from: data)
        guard Set(payload.categories.map(\.id)).count == payload.categories.count,
              Set(payload.items.map(\.id)).count == payload.items.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return payload
    }

    private static func encode(_ payload: StorePayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    func save(_ payload: StorePayload, completion: @escaping (String?) -> Void) {
        queue.async {
            var failure: String?
            do {
                let data = try Self.encode(payload)
                try FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let previous = try? Data(contentsOf: self.fileURL), (try? Self.decode(previous)) != nil {
                    try previous.write(to: self.backupURL, options: .atomic)
                }
                try data.write(to: self.fileURL, options: .atomic)
            } catch { failure = error.localizedDescription }
            let message = failure
            DispatchQueue.main.async { completion(message) }
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    func export(_ payload: StorePayload, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try Self.encode(payload).write(to: destination, options: .atomic)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func restore(from source: URL) async throws -> StorePayload {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let data = try Data(contentsOf: source)
                    let payload = try Self.decode(data) // Validate before touching current data.
                    try FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: self.fileURL.path) {
                        let preserved = self.fileURL.appendingPathExtension("before-restore-\(UUID().uuidString).json")
                        try FileManager.default.copyItem(at: self.fileURL, to: preserved)
                    }
                    try data.write(to: self.fileURL, options: .atomic)
                    continuation.resume(returning: payload)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
