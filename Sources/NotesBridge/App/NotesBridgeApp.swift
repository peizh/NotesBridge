import SwiftUI

@main
struct NotesBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra("NotesBridge", systemImage: appModel.menuBarSymbolName) {
            MenuBarContentView()
                .environmentObject(appModel)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: AppWindowID.settings) {
            SettingsView()
                .environmentObject(appModel)
                .frame(width: 640, height: 560)
                .padding(24)
        }
        .windowResizability(.contentSize)
    }
}
