import AppKit
import Foundation

@MainActor
protocol AppKitDirectoryPanelApplication {
    func currentActivationPolicy() -> NSApplication.ActivationPolicy
    @discardableResult func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) -> Bool
    func activateIgnoringOtherApps()
    func bringDirectoryPanelParentWindowForward()
}

@MainActor
struct LiveAppKitDirectoryPanelApplication: AppKitDirectoryPanelApplication {
    func currentActivationPolicy() -> NSApplication.ActivationPolicy {
        NSApp.activationPolicy()
    }

    @discardableResult
    func setActivationPolicy(_ policy: NSApplication.ActivationPolicy) -> Bool {
        NSApp.setActivationPolicy(policy)
    }

    func activateIgnoringOtherApps() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func bringDirectoryPanelParentWindowForward() {
        let parentWindow = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first { window in
                window.isVisible && !window.isMiniaturized
            }
        parentWindow?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
struct AppKitDirectoryPanel {
    typealias PanelRunner = @MainActor (NSOpenPanel) -> NSApplication.ModalResponse

    private let application: any AppKitDirectoryPanelApplication
    private let panelRunner: PanelRunner

    init(
        application: any AppKitDirectoryPanelApplication = LiveAppKitDirectoryPanelApplication(),
        panelRunner: @escaping PanelRunner = { panel in panel.runModal() }
    ) {
        self.application = application
        self.panelRunner = panelRunner
    }

    func chooseDirectory(
        title: String,
        prompt: String,
        message: String? = nil,
        directoryURL: URL? = nil,
        canCreateDirectories: Bool
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.message = message ?? ""
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = canCreateDirectories
        panel.directoryURL = directoryURL

        let shouldRestoreAccessoryPolicy = application.currentActivationPolicy() == .accessory
        let changedActivationPolicy = shouldRestoreAccessoryPolicy
            ? application.setActivationPolicy(.regular)
            : false

        application.activateIgnoringOtherApps()
        application.bringDirectoryPanelParentWindowForward()

        defer {
            if changedActivationPolicy {
                application.setActivationPolicy(.accessory)
            }
        }

        guard panelRunner(panel) == .OK else {
            return nil
        }

        return panel.url
    }
}

@MainActor
protocol VaultDirectorySelecting {
    func chooseVaultDirectory(title: String, prompt: String) -> URL?
}

@MainActor
struct ObsidianVaultDirectorySelector: VaultDirectorySelecting {
    private let directoryPanel: AppKitDirectoryPanel

    init(directoryPanel: AppKitDirectoryPanel = AppKitDirectoryPanel()) {
        self.directoryPanel = directoryPanel
    }

    func chooseVaultDirectory(title: String, prompt: String) -> URL? {
        directoryPanel.chooseDirectory(
            title: title,
            prompt: prompt,
            canCreateDirectories: true
        )
    }
}
