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
        let settingsSnapshotFileURL = testRootURL.appendingPathComponent("ui-test-settings.json", isDirectory: false)
        let windowReadyFileURL = testRootURL.appendingPathComponent("ui-test-window-ready", isDirectory: false)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dataFolderURL, withIntermediateDirectories: true)

        let appProcess = Process()
        appProcess.executableURL = appExecutableURL
        appProcess.environment = mergedEnvironment([
            "NOTESBRIDGE_UI_TEST_MODE": "1",
            "NOTESBRIDGE_UI_TEST_ROOT": testRootURL.path,
            "NOTESBRIDGE_UI_TEST_AUTORUN": "sync-all-notes",
            "NOTESBRIDGE_APPSTORE": "1",
        ])
        try appProcess.run()
        defer {
            terminate(process: appProcess)
        }

        XCTAssertTrue(
            waitForCondition(timeout: 10) {
                FileManager.default.fileExists(atPath: windowReadyFileURL.path)
            },
            currentStatusDescription(statusFileURL: statusFileURL, process: appProcess)
        )

        let settingsSnapshot = try loadSettingsSnapshot(from: settingsSnapshotFileURL)
        XCTAssertEqual(settingsSnapshot.buildFlavor, "appStore")
        XCTAssertFalse(settingsSnapshot.showsAppUpdateSettings)

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

    func testDirectDownloadSettingsShowVersionAndUpdateControls() throws {
        let testRootURL = try makeUITestRootDirectory()
        let appBinaryURL = try notesBridgeBinaryURL()
        let appBundleURL = try makeUITestAppBundle(for: appBinaryURL, in: testRootURL)
        let appExecutableURL = appBundleURL.appendingPathComponent("Contents/MacOS/NotesBridge", isDirectory: false)
        let settingsSnapshotFileURL = testRootURL.appendingPathComponent("ui-test-settings.json", isDirectory: false)
        let windowReadyFileURL = testRootURL.appendingPathComponent("ui-test-window-ready", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: testRootURL)
        }

        let appProcess = Process()
        appProcess.executableURL = appExecutableURL
        appProcess.environment = mergedEnvironment([
            "NOTESBRIDGE_UI_TEST_MODE": "1",
            "NOTESBRIDGE_UI_TEST_ROOT": testRootURL.path,
        ])
        try appProcess.run()
        defer {
            terminate(process: appProcess)
        }

        XCTAssertTrue(
            waitForCondition(timeout: 10) {
                FileManager.default.fileExists(atPath: windowReadyFileURL.path)
            }
        )

        let settingsSnapshot = try loadSettingsSnapshot(from: settingsSnapshotFileURL)
        XCTAssertEqual(settingsSnapshot.buildFlavor, "directDownload")
        XCTAssertEqual(settingsSnapshot.currentVersion, "1.2.3")
        XCTAssertEqual(settingsSnapshot.currentVersionDisplay, "1.2.3 (456)")
        XCTAssertEqual(settingsSnapshot.currentBuildNumber, "456")
        XCTAssertTrue(settingsSnapshot.showsAppUpdateSettings)
        XCTAssertTrue(settingsSnapshot.canCheckForUpdates)
        XCTAssertTrue(settingsSnapshot.automaticallyChecksForUpdates)
        XCTAssertFalse(settingsSnapshot.automaticallyDownloadsUpdates)
    }

    func testAppStoreSettingsHideUpdateControls() throws {
        let testRootURL = try makeUITestRootDirectory()
        let appBinaryURL = try notesBridgeBinaryURL()
        let appBundleURL = try makeUITestAppBundle(for: appBinaryURL, in: testRootURL)
        let appExecutableURL = appBundleURL.appendingPathComponent("Contents/MacOS/NotesBridge", isDirectory: false)
        let settingsSnapshotFileURL = testRootURL.appendingPathComponent("ui-test-settings.json", isDirectory: false)
        let windowReadyFileURL = testRootURL.appendingPathComponent("ui-test-window-ready", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: testRootURL)
        }

        let appProcess = Process()
        appProcess.executableURL = appExecutableURL
        appProcess.environment = mergedEnvironment([
            "NOTESBRIDGE_UI_TEST_MODE": "1",
            "NOTESBRIDGE_UI_TEST_ROOT": testRootURL.path,
            "NOTESBRIDGE_APPSTORE": "1",
        ])
        try appProcess.run()
        defer {
            terminate(process: appProcess)
        }

        XCTAssertTrue(
            waitForCondition(timeout: 10) {
                FileManager.default.fileExists(atPath: windowReadyFileURL.path)
            }
        )

        let settingsSnapshot = try loadSettingsSnapshot(from: settingsSnapshotFileURL)
        XCTAssertEqual(settingsSnapshot.buildFlavor, "appStore")
        XCTAssertFalse(settingsSnapshot.showsAppUpdateSettings)
        XCTAssertFalse(settingsSnapshot.canCheckForUpdates)
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
        let frameworksURL = contentsURL.appendingPathComponent("Frameworks", isDirectory: true)
        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: frameworksURL, withIntermediateDirectories: true)

        let bundledExecutableURL = macOSURL.appendingPathComponent("NotesBridge", isDirectory: false)
        if fileManager.fileExists(atPath: bundledExecutableURL.path) {
            try fileManager.removeItem(at: bundledExecutableURL)
        }
        try fileManager.copyItem(at: executableURL, to: bundledExecutableURL)
        try addFrameworkRPath(to: bundledExecutableURL)

        let sparkleFrameworkURL = try sparkleFrameworkURL(for: executableURL)
        let bundledSparkleFrameworkURL = frameworksURL.appendingPathComponent("Sparkle.framework", isDirectory: true)
        if fileManager.fileExists(atPath: bundledSparkleFrameworkURL.path) {
            try fileManager.removeItem(at: bundledSparkleFrameworkURL)
        }
        try fileManager.copyItem(at: sparkleFrameworkURL, to: bundledSparkleFrameworkURL)

        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "NotesBridge",
            "CFBundleIdentifier": "notes.ui-tests.NotesBridge",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "NotesBridge",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "456",
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
        try adHocSign(path: bundledSparkleFrameworkURL.path, deep: true)
        try adHocSign(path: bundleURL.path, deep: true)
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

    private func sparkleFrameworkURL(for executableURL: URL) throws -> URL {
        let candidate = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("Sparkle.framework", isDirectory: true)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw UITestError.missingSparkleFramework(candidate.path)
        }
        return candidate
    }

    private func addFrameworkRPath(to executableURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/install_name_tool")
        process.arguments = [
            "-add_rpath",
            "@executable_path/../Frameworks",
            executableURL.path,
        ]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UITestError.failedToRewriteRPath(executableURL.path)
        }
    }

    private func mergedEnvironment(_ overrides: [String: String]) -> [String: String] {
        ProcessInfo.processInfo.environment.merging(overrides) { _, new in new }
    }

    private func terminate(process: Process) {
        guard process.isRunning else {
            return
        }

        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private func adHocSign(path: String, deep: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = deep
            ? ["--force", "--sign", "-", "--deep", path]
            : ["--force", "--sign", "-", path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw UITestError.failedToSignBundle(path)
        }
    }

    private func loadSettingsSnapshot(from url: URL) throws -> UITestSettingsSnapshot {
        XCTAssertTrue(
            waitForCondition(timeout: 10) {
                FileManager.default.fileExists(atPath: url.path)
            }
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(UITestSettingsSnapshot.self, from: data)
    }
}

private enum UITestError: LocalizedError {
    case binaryNotFound([String])
    case missingSparkleFramework(String)
    case failedToRewriteRPath(String)
    case failedToSignBundle(String)

    var errorDescription: String? {
        switch self {
        case let .binaryNotFound(candidates):
            "Could not find the NotesBridge executable. Checked: \(candidates.joined(separator: ", "))"
        case let .missingSparkleFramework(path):
            "Could not find Sparkle.framework at \(path)."
        case let .failedToRewriteRPath(path):
            "Failed to add the Frameworks rpath to \(path)."
        case let .failedToSignBundle(path):
            "Failed to ad-hoc sign \(path)."
        }
    }
}

private struct UITestSettingsSnapshot: Decodable {
    let buildFlavor: String
    let currentVersion: String
    let currentVersionDisplay: String
    let currentBuildNumber: String
    let showsAppUpdateSettings: Bool
    let canCheckForUpdates: Bool
    let automaticallyChecksForUpdates: Bool
    let automaticallyDownloadsUpdates: Bool
}
#endif
