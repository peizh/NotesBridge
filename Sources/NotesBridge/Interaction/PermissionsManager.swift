import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var inputMonitoringGranted = false

    init() {
        refresh()
    }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    func requestAccessibilityPermission() {
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    func requestInputMonitoringPermission() {
        inputMonitoringGranted = CGRequestListenEventAccess()
    }

    @discardableResult
    func openAccessibilitySettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return openSystemSettingsApp()
        }
        return NSWorkspace.shared.open(url) || openSystemSettingsApp()
    }

    @discardableResult
    func openInputMonitoringSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return openSystemSettingsApp()
        }
        return NSWorkspace.shared.open(url) || openSystemSettingsApp()
    }

    private func openSystemSettingsApp() -> Bool {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/System/Applications/System Settings.app"),
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in }
        return true
    }
}
