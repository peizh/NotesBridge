import AppKit
import Foundation

@MainActor
struct BundledAppLauncher {
    private static let bundleIdentifier = "dev.notesbridge.app"
    private static let designatedRequirement = #"=designated => identifier "dev.notesbridge.app""#
    private let processRunner = ProcessRunner()

    var isRunningBundledApp: Bool {
        let bundleURL = Bundle.main.bundleURL
        let packageType = Bundle.main.object(forInfoDictionaryKey: "CFBundlePackageType") as? String
        return bundleURL.pathExtension == "app" && packageType == "APPL"
    }

    func relaunchCurrentExecutableAsBundledApp(
        requestInputMonitoringOnLaunch: Bool,
        completion: @escaping @MainActor (Result<Void, Error>) -> Void
    ) {
        do {
            let appURL = try prepareBundledApp()
            let configuration = NSWorkspace.OpenConfiguration()
            if requestInputMonitoringOnLaunch {
                configuration.environment = [
                    "NOTESBRIDGE_REQUEST_INPUT_MONITORING": "1",
                ]
            }

            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                Task { @MainActor in
                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func prepareBundledApp() throws -> URL {
        let appURL = try bundledAppURL()
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: appURL.path) {
            try fileManager.removeItem(at: appURL)
        }

        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let executableURL = try currentExecutableURL()
        let bundledExecutableURL = macOSURL.appendingPathComponent("NotesBridge", isDirectory: false)
        try fileManager.copyItem(at: executableURL, to: bundledExecutableURL)

        let infoPlist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleExecutable": "NotesBridge",
            "CFBundleIdentifier": Self.bundleIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "NotesBridge",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSUIElement": true,
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: infoPlist,
            format: .xml,
            options: 0
        )
        try plistData.write(
            to: contentsURL.appendingPathComponent("Info.plist", isDirectory: false),
            options: .atomic
        )

        _ = try processRunner.run(
            executable: "/usr/bin/codesign",
            arguments: [
                "--force",
                "--sign",
                "-",
                "--identifier",
                Self.bundleIdentifier,
                "--requirements",
                Self.designatedRequirement,
                "--deep",
                appURL.path,
            ]
        )

        return appURL
    }

    private func bundledAppURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("NotesBridge", isDirectory: true)
        .appendingPathComponent("NotesBridge.app", isDirectory: true)
    }

    private func currentExecutableURL() throws -> URL {
        if let executableURL = Bundle.main.executableURL {
            return executableURL
        }

        guard let executablePath = CommandLine.arguments.first, !executablePath.isEmpty else {
            throw BundledAppLauncherError.missingExecutable
        }
        return URL(fileURLWithPath: executablePath, isDirectory: false)
    }
}

private enum BundledAppLauncherError: LocalizedError {
    case missingExecutable

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            "Could not determine the NotesBridge executable path."
        }
    }
}
