import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("NotesBridge Settings")
                .font(.largeTitle.weight(.semibold))

            Form {
                Section("Distribution") {
                    LabeledContent("Build") {
                        Text(appModel.buildFlavor.title)
                    }

                    Text(
                        appModel.buildFlavor.supportsInlineEnhancements
                            ? "This build can enhance Apple Notes inline through Accessibility."
                            : "This build only exposes settings, sync, and integration features."
                    )
                    .foregroundStyle(.secondary)
                }

                Section("Permissions") {
                    LabeledContent("Accessibility") {
                        Text(appModel.interactionAvailability.accessibilityGranted ? "Granted" : "Required")
                            .foregroundStyle(appModel.interactionAvailability.accessibilityGranted ? .green : .orange)
                    }

                    HStack {
                        Button("Request Accessibility Permission") {
                            appModel.requestAccessibilityPermission()
                        }
                        .disabled(!appModel.buildFlavor.supportsInlineEnhancements)

                        Button("Open Accessibility Settings") {
                            appModel.openAccessibilitySettings()
                        }
                    }

                    Text(appModel.interactionAvailability.summary)
                        .foregroundStyle(.secondary)
                }

                Section("Inline Enhancements") {
                    Toggle(
                        "Enable inline Apple Notes enhancements",
                        isOn: Binding(
                            get: { appModel.settings.enableInlineEnhancements },
                            set: { appModel.settings.enableInlineEnhancements = $0 }
                        )
                    )
                    .disabled(!appModel.buildFlavor.supportsInlineEnhancements)

                    Toggle(
                        "Show formatting bar for selected text",
                        isOn: Binding(
                            get: { appModel.settings.enableFormattingBar },
                            set: { appModel.settings.enableFormattingBar = $0 }
                        )
                    )
                    .disabled(!appModel.buildFlavor.supportsInlineEnhancements || !appModel.settings.enableInlineEnhancements)

                    Toggle(
                        "Enable markdown and list triggers at line start",
                        isOn: Binding(
                            get: { appModel.settings.enableMarkdownTriggers },
                            set: { appModel.settings.enableMarkdownTriggers = $0 }
                        )
                    )
                    .disabled(!appModel.buildFlavor.supportsInlineEnhancements || !appModel.settings.enableInlineEnhancements)

                    Toggle(
                        "Enable slash commands",
                        isOn: Binding(
                            get: { appModel.settings.enableSlashCommands },
                            set: { appModel.settings.enableSlashCommands = $0 }
                        )
                    )
                    .disabled(!appModel.buildFlavor.supportsInlineEnhancements || !appModel.settings.enableInlineEnhancements)

                    Text("Use / to open slash suggestions, or type an exact slash command and press Space to apply it inline.")
                        .foregroundStyle(.secondary)

                    if appModel.settings.enableSlashCommands && !appModel.slashKeyboardNavigationAvailable {
                        Text("Keyboard slash navigation is unavailable. Enable Input Monitoring for NotesBridge in Privacy & Security, or use the mouse and exact command plus Space.")
                            .foregroundStyle(.secondary)
                    }

                    Text("Inline enhancements support the formatting bar, markdown/list triggers, and slash commands.")
                        .foregroundStyle(.secondary)
                }

                Section("Obsidian") {
                    LabeledContent("Vault") {
                        Text(appModel.settings.vaultPath ?? "Not configured")
                            .foregroundStyle(appModel.hasVaultConfigured ? .primary : .secondary)
                    }

                    HStack {
                        Button("Choose Vault") {
                            appModel.chooseVaultDirectory()
                        }

                        Button("Reveal in Finder") {
                            appModel.revealVault()
                        }
                        .disabled(!appModel.hasVaultConfigured)
                    }

                    TextField(
                        "Export Folder Name",
                        text: Binding(
                            get: { appModel.settings.exportFolderName },
                            set: { appModel.settings.exportFolderName = $0 }
                        )
                    )
                }

                Section("Indexing & Sync") {
                    LabeledContent("Known Folders") {
                        Text("\(appModel.folderSummaries.count)")
                    }
                    LabeledContent("Indexed Notes") {
                        Text("\(appModel.syncedNoteCount)")
                    }
                    LabeledContent("Last Full Sync") {
                        Text(appModel.lastFullSyncLabel)
                    }

                    HStack {
                        Button("Refresh Folder Index") {
                            Task {
                                await appModel.refreshFolderSummaries()
                            }
                        }
                        .disabled(appModel.isRefreshingFolders)

                        Button(appModel.isSyncing ? "Syncing..." : "Sync All Notes to Obsidian") {
                            Task {
                                await appModel.syncAllNotes()
                            }
                        }
                        .disabled(!appModel.hasVaultConfigured || appModel.isSyncing)
                    }
                }

                Section("Current Status") {
                    Text(appModel.statusMessage)

                    if appModel.isSyncing {
                        syncProgressSection
                    }

                    Text("Current selection: \(appModel.selectionSummary)")
                        .foregroundStyle(.secondary)
                    Text("Slash commands: \(appModel.slashCommandsSummary)")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var syncProgressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let syncProgress = appModel.syncProgress {
                ProgressView(value: syncProgress.fractionCompleted)
                    .progressViewStyle(.linear)
                Text(syncProgress.summaryText)
                    .foregroundStyle(.secondary)

                if let currentFolderText = syncProgress.currentFolderText {
                    Text(currentFolderText)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                Text("Preparing sync progress...")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
