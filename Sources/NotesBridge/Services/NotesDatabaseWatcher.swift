import Foundation
import OSLog

@MainActor
final class NotesDatabaseWatcher {
    var onChange: (@MainActor @Sendable () -> Void)?
    private let pollInterval: TimeInterval = 2.0
    private var isRunning = false
    private var hasEstablishedBaseline = false
    private var lastModificationDates: [URL: Date] = [:]
    private var timer: Timer?
    private var dataFolderURL: URL?

    init() {}

    func start(dataFolderURL: URL) {
        self.dataFolderURL = dataFolderURL
        self.isRunning = true
        self.hasEstablishedBaseline = false
        self.lastModificationDates = [:]

        self.scheduleTimer()
    }

    func stop() {
        isRunning = false
        self.timer?.invalidate()
        self.timer = nil
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.check()
            }
        }
    }

    private func check() {
        guard isRunning, let dataFolderURL = dataFolderURL else { return }

        let databaseURLs = findDatabaseFiles(in: dataFolderURL)
        var changed = false

        for url in databaseURLs {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let modificationDate = attributes[.modificationDate] as? Date {
                    if let lastDate = lastModificationDates[url], modificationDate > lastDate {
                        changed = true
                    } else if hasEstablishedBaseline, lastModificationDates[url] == nil {
                        changed = true
                    }
                    lastModificationDates[url] = modificationDate
                }
            } catch {
                // File might be temporarily missing or unreadable
            }
        }

        hasEstablishedBaseline = true

        if changed {
            onChange?()
        }
    }

    private func findDatabaseFiles(in rootURL: URL) -> [URL] {
        var urls: [URL] = []
        let fileManager = FileManager.default

        let rootDatabase = rootURL.appendingPathComponent("NoteStore.sqlite", isDirectory: false)
        if fileManager.fileExists(atPath: rootDatabase.path) {
            urls.append(rootDatabase)
            urls.append(URL(fileURLWithPath: rootDatabase.path + "-wal"))
        }

        let accountsURL = rootURL.appendingPathComponent("Accounts", isDirectory: true)
        if let accountDirectories = try? fileManager.contentsOfDirectory(
            at: accountsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for accountDirectory in accountDirectories {
                let database = accountDirectory.appendingPathComponent("NoteStore.sqlite", isDirectory: false)
                if fileManager.fileExists(atPath: database.path) {
                    urls.append(database)
                    urls.append(URL(fileURLWithPath: database.path + "-wal"))
                }
            }
        }

        return urls
    }
}
