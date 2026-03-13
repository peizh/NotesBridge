import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var uiTestWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppRuntime.shared.launchMode.isUITesting {
            NSApp.setActivationPolicy(.regular)
            presentUITestWindow()
            AppRuntime.shared.uiTestRecorder?.recordWindowReady()
            NSApp.activate(ignoringOtherApps: true)
            scheduleUITestAutomationIfNeeded()
        } else {
            NSApp.setActivationPolicy(.accessory)
            scheduleDebugSyncIfNeeded()
        }
    }

    private func presentUITestWindow() {
        let rootView = SettingsView()
            .environmentObject(AppRuntime.shared.appModel)
            .frame(width: 640, height: 560)
            .padding(24)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "NotesBridge UI Test"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 688, height: 608))
        window.center()
        window.makeKeyAndOrderFront(nil)
        uiTestWindow = window
    }

    private func scheduleUITestAutomationIfNeeded() {
        guard AppRuntime.shared.launchMode.uiTestConfiguration?.automationAction == .syncAllNotes else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Task {
                await AppRuntime.shared.appModel.syncAllNotes()
            }
        }
    }

    private func scheduleDebugSyncIfNeeded() {
        guard ProcessInfo.processInfo.environment["NOTESBRIDGE_DEBUG_SYNC_ON_LAUNCH"] == "1" else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            Task {
                await AppRuntime.shared.appModel.syncAllNotes()
            }
        }
    }
}
