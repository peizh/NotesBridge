import Dispatch
import Foundation

protocol NotesDatabaseWatching: AnyObject {
    var onChange: (@MainActor @Sendable () -> Void)? { get set }
    func start(dataFolderURL: URL)
    func stop()
}

final class NotesDatabaseWatcher: NotesDatabaseWatching, @unchecked Sendable {
    var onChange: (@MainActor @Sendable () -> Void)?

    private let pollInterval: TimeInterval
    private let queue: DispatchQueue
    private var isRunning = false
    private var hasEstablishedBaseline = false
    private var lastModificationDates: [URL: Date] = [:]
    private var timer: DispatchSourceTimer?
    private var dataFolderURL: URL?

    init(
        pollInterval: TimeInterval = 2.0,
        queue: DispatchQueue = DispatchQueue(label: "dev.notesbridge.watcher")
    ) {
        self.pollInterval = pollInterval
        self.queue = queue
    }

    func start(dataFolderURL: URL) {
        stop()

        queue.sync {
            self.dataFolderURL = dataFolderURL
            self.isRunning = true
            self.hasEstablishedBaseline = false
            self.lastModificationDates = [:]

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
            timer.setEventHandler { [weak self] in
                self?.check()
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        let timer = queue.sync { () -> DispatchSourceTimer? in
            isRunning = false
            dataFolderURL = nil
            hasEstablishedBaseline = false
            lastModificationDates = [:]

            let timer = self.timer
            self.timer = nil
            return timer
        }

        timer?.setEventHandler {}
        timer?.cancel()
    }

    private func check() {
        guard isRunning, let dataFolderURL else { return }

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
                // File might be temporarily missing or unreadable.
            }
        }

        hasEstablishedBaseline = true

        if changed {
            emitChange()
        }
    }

    private func emitChange() {
        Task { @MainActor in
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
