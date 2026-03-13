#if canImport(XCTest)
import XCTest

final class NotesBridgeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSyncFromSettingsExportsNotesAndUpdatesStatus() throws {
        let testRootURL = try makeUITestRootDirectory()
        let appBinaryURL = try notesBridgeBinaryURL()
        let appBundleURL = try makeUITestAppBundle(for: appBinaryURL, in: testRootURL)
        let appExecutableURL = appBundleURL.appendingPathComponent("Contents/MacOS/NotesBridge", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: testRootURL)
        }

        let vaultURL = testRootURL.appendingPathComponent("vault", isDirectory: true)
        let dataFolderURL = testRootURL.appendingPathComponent("group.com.apple.notes", isDirectory: true)
        let statusFileURL = testRootURL.appendingPathComponent("ui-test-status.txt", isDirectory: false)
        let windowReadyFileURL = testRootURL.appendingPathComponent("ui-test-window-ready", isDirectory: false)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataFolderURL, withIntermediateDirectories: true)

        let appProcess = Process()
        appProcess.executableURL = appExecutableURL
        appProcess.environment = [
            "NOTESBRIDGE_UI_TEST_MODE": "1",
            "NOTESBRIDGE_UI_TEST_ROOT": testRootURL.path,
            "NOTESBRIDGE_UI_TEST_AUTORUN": "sync-all-notes",
            "NOTESBRIDGE_APPSTORE": "1",
        ]
        try appProcess.run()
        defer {
            if appProcess.isRunning {
                appProcess.terminate()
                appProcess.waitUntilExit()
            }
        }

        XCTAssertTrue(
            waitForCondition(timeout: 10) {
                FileManager.default.fileExists(atPath: windowReadyFileURL.path)
            },
            currentStatusDescription(statusFileURL: statusFileURL, process: appProcess)
        )

        let successText = "Synced 3 note(s) across 2 folder(s)."
        XCTAssertTrue(
            waitForCondition(timeout: 15) {
                let statusMessage = (try? String(contentsOf: statusFileURL)) ?? ""
                return statusMessage.contains(successText)
            },
            currentStatusDescription(statusFileURL: statusFileURL, process: appProcess)
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: vaultURL.appendingPathComponent("Apple Notes/Inbox/First Note.md").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: vaultURL.appendingPathComponent("Apple Notes/Inbox/Second Note.md").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: vaultURL.appendingPathComponent("Apple Notes/Projects/Specs/Roadmap.md").path
            )
        )

        let firstNoteContents = try String(
            contentsOf: vaultURL.appendingPathComponent("Apple Notes/Inbox/First Note.md"),
            encoding: .utf8
        )
        XCTAssertTrue(
            firstNoteContents.contains("[[Apple Notes/Projects/Specs/Roadmap|Roadmap]]"),
            firstNoteContents
        )
    }

    private func notesBridgeBinaryURL() throws -> URL {
        let bundleProductsURL = Bundle(for: type(of: self))
            .bundleURL
            .deletingLastPathComponent()
        let candidates = [
            bundleProductsURL.appendingPathComponent("NotesBridge", isDirectory: false),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/debug/NotesBridge", isDirectory: false),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/arm64-apple-macosx/debug/NotesBridge", isDirectory: false),
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        throw UITestError.binaryNotFound(candidates.map(\.path))
    }

    private func makeUITestRootDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesBridge-UITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeUITestAppBundle(for executableURL: URL, in rootURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let bundleURL = rootURL.appendingPathComponent("NotesBridgeUITest.app", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let bundledExecutableURL = macOSURL.appendingPathComponent("NotesBridge", isDirectory: false)
        if fileManager.fileExists(atPath: bundledExecutableURL.path) {
            try fileManager.removeItem(at: bundledExecutableURL)
        }
        try fileManager.copyItem(at: executableURL, to: bundledExecutableURL)

        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "NotesBridge",
            "CFBundleIdentifier": "notes.ui-tests.NotesBridge",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "NotesBridge",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSUIElement": false,
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(
            to: contentsURL.appendingPathComponent("Info.plist", isDirectory: false),
            options: .atomic
        )
        return bundleURL
    }

    private func waitForCondition(
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.1,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        } while Date() < deadline
        return condition()
    }

    private func currentStatusDescription(statusFileURL: URL, process: Process) -> String {
        let statusMessage = (try? String(contentsOf: statusFileURL)) ?? "<missing>"
        let runningState = process.isRunning ? "running" : "exited(\(process.terminationStatus))"
        return "App process is \(runningState). Current status: \(statusMessage)"
    }
}

private enum UITestError: LocalizedError {
    case binaryNotFound([String])

    var errorDescription: String? {
        switch self {
        case let .binaryNotFound(candidates):
            "Could not find the NotesBridge executable. Checked: \(candidates.joined(separator: ", "))"
        }
    }
}
#endif
