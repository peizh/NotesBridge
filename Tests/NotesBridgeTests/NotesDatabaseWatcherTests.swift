import XCTest
@testable import NotesBridge

@MainActor
final class NotesDatabaseWatcherTests: XCTestCase {
    func testWatcherDetectsFileChange() async throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("NoteStore.sqlite")
        try "initial".write(to: dbURL, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "Change detected")
        let watcher = NotesDatabaseWatcher()
        defer { watcher.stop() }

        watcher.onChange = {
            expectation.fulfill()
        }

        watcher.start(dataFolderURL: tempDir)

        // Wait for first poll to record initial dates
        try await Task.sleep(nanoseconds: 2_500_000_000)

        // Modify file
        try "changed".write(to: dbURL, atomically: true, encoding: .utf8)

        // Poll interval is 2s, wait enough time
        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testWatcherDetectsFirstPostBaselineWALCreation() async throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("NoteStore.sqlite")
        let walURL = URL(fileURLWithPath: dbURL.path + "-wal")
        try "initial".write(to: dbURL, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "WAL creation detected")
        let watcher = NotesDatabaseWatcher()
        defer { watcher.stop() }

        watcher.onChange = {
            expectation.fulfill()
        }

        watcher.start(dataFolderURL: tempDir)

        // Let the watcher record the baseline without a WAL file.
        try await Task.sleep(nanoseconds: 2_500_000_000)

        try "wal".write(to: walURL, atomically: true, encoding: .utf8)

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testWatcherDetectsFirstPostBaselineDatabaseCreation() async throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let rootDatabaseURL = tempDir.appendingPathComponent("NoteStore.sqlite")
        try "initial".write(to: rootDatabaseURL, atomically: true, encoding: .utf8)

        let expectation = expectation(description: "Account database creation detected")
        let watcher = NotesDatabaseWatcher()
        defer { watcher.stop() }

        watcher.onChange = {
            expectation.fulfill()
        }

        watcher.start(dataFolderURL: tempDir)

        try await Task.sleep(nanoseconds: 2_500_000_000)

        let accountDirectory = tempDir
            .appendingPathComponent("Accounts", isDirectory: true)
            .appendingPathComponent("Primary", isDirectory: true)
        try fileManager.createDirectory(at: accountDirectory, withIntermediateDirectories: true)
        try "account-db".write(
            to: accountDirectory.appendingPathComponent("NoteStore.sqlite"),
            atomically: true,
            encoding: .utf8
        )

        await fulfillment(of: [expectation], timeout: 5.0)
    }
}
