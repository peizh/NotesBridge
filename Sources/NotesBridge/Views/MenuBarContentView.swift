import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NotesBridge")
                    .font(.headline)
                Text(appModel.buildFlavor.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                statusRow(title: "Inline", value: appModel.interactionAvailability.summary)
                statusRow(title: "Slash", value: appModel.slashCommandsSummary)
                statusRow(title: "Selection", value: appModel.selectionSummary)
                statusRow(title: "Sync", value: "Last full sync: \(appModel.lastFullSyncLabel)")
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    appModel.openAppleNotes()
                } label: {
                    Label("Open Apple Notes", systemImage: "note.text")
                }

                Button {
                    Task {
                        await appModel.syncAllNotes()
                    }
                } label: {
                    Label(
                        appModel.isSyncing ? "Syncing Notes..." : "Sync All Notes to Obsidian",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .disabled(!appModel.hasVaultConfigured || appModel.isSyncing)

                Button {
                    openSettingsWindow()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit NotesBridge", systemImage: "xmark.circle")
            }
        }
        .padding(14)
        .frame(width: 360)
        .alert(
            "NotesBridge",
            isPresented: Binding(
                get: { appModel.errorMessage != nil },
                set: { if !$0 { appModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
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
