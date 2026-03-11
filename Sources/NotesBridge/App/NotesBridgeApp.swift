import SwiftUI

@main
struct NotesBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel: AppModel

    init() {
        _appModel = StateObject(wrappedValue: AppRuntime.shared.appModel)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appModel)
        } label: {
            MenuBarIconView(
                symbolName: appModel.menuBarSymbolName,
                isSyncing: appModel.isSyncing,
                frameIndex: appModel.menuBarSyncFrameIndex
            )
            .frame(width: 18, height: 18)
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
