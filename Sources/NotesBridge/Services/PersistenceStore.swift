import Foundation

protocol PersistenceStoring: Sendable {
    func loadSettings() -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
    func loadSyncIndex() -> SyncIndex
    func saveSyncIndex(_ index: SyncIndex) throws
}

struct PersistenceStore: PersistenceStoring {
    private let directoryName = "NotesBridge"

    func loadSettings() -> AppSettings {
        load(AppSettings.self, from: "settings.json") ?? .default
    }

    func saveSettings(_ settings: AppSettings) throws {
        try save(settings, to: "settings.json")
    }

    func loadSyncIndex() -> SyncIndex {
        load(SyncIndex.self, from: "sync-index.json") ?? SyncIndex()
    }

    func saveSyncIndex(_ index: SyncIndex) throws {
        try save(index, to: "sync-index.json")
    }

    private func load<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        guard let fileURL = try? fileURL(for: fileName),
              let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to fileName: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)

        let fileURL = try fileURL(for: fileName)
        try data.write(to: fileURL, options: .atomic)
    }

    private func fileURL(for fileName: String) throws -> URL {
        let fileManager = FileManager.default
        let baseDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(directoryName, isDirectory: true)

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        return baseDirectory.appendingPathComponent(fileName)
    }
}
