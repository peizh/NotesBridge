import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(appModel.t("NotesBridge"))
                    .font(.headline)
                Text(appModel.localizedBuildFlavorTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                statusRow(title: appModel.t("Inline"), value: appModel.inlineEnhancementsSummary)
                statusRow(title: appModel.t("Slash"), value: appModel.slashCommandsSummary)
                statusRow(title: appModel.t("Selection"), value: appModel.selectionSummary)
                statusRow(title: appModel.t("Sync"), value: appModel.tf("Last sync: %@", appModel.lastSyncLabel))
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    appModel.openAppleNotes()
                } label: {
                    Label(appModel.t("Open Apple Notes"), systemImage: "note.text")
                }

                Button {
                    Task {
                        await appModel.syncChangedNotes()
                    }
                } label: {
                    Label(
                        appModel.isSyncing ? appModel.t("Syncing Notes...") : appModel.t("Sync Changed Notes"),
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .disabled(!appModel.hasVaultConfigured || appModel.isSyncing)

                Button {
                    openSettingsWindow()
                } label: {
                    Label(appModel.t("Open Settings"), systemImage: "gearshape")
                }

                if !appModel.isRunningBundledApp && appModel.buildFlavor.supportsInlineEnhancements {
                    Button {
                        appModel.relaunchAsBundledApp()
                    } label: {
                        Label(appModel.t("Relaunch as Bundled App"), systemImage: "app.badge")
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label(appModel.t("Quit NotesBridge"), systemImage: "xmark.circle")
            }
        }
        .padding(14)
        .frame(width: 360)
        .alert(
            appModel.t("NotesBridge"),
            isPresented: Binding(
                get: { appModel.errorMessage != nil },
                set: { if !$0 { appModel.errorMessage = nil } }
            )
        ) {
            Button(appModel.t("OK"), role: .cancel) {
                appModel.errorMessage = nil
            }
        } message: {
            Text(appModel.errorMessage ?? "")
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: AppWindowID.settings)
    }
}
