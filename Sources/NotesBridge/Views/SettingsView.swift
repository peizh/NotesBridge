import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("NotesBridge Settings")
                .font(.largeTitle.weight(.semibold))
                .accessibilityIdentifier("settings.title")

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
                    LabeledContent("Launch Mode") {
                        Text(appModel.isRunningBundledApp ? "Bundled App" : "Command-line build")
                            .foregroundStyle(appModel.isRunningBundledApp ? .green : .orange)
                    }

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

                    if appModel.isRunningBundledApp {
                        Button("Reveal NotesBridge App in Finder") {
                            appModel.revealCurrentAppInFinder()
                        }
                    }

                    if !appModel.isRunningBundledApp && appModel.buildFlavor.supportsInlineEnhancements {
                        Button("Relaunch as Bundled App") {
                            appModel.relaunchAsBundledApp()
                        }
                    }

                    Text(appModel.inlineEnhancementsSummary)
                        .foregroundStyle(.secondary)

                    if appModel.isRunningBundledApp && !appModel.interactionAvailability.accessibilityGranted {
                        Text("If NotesBridge is already checked in Accessibility but still shows Required here, remove it and add the current NotesBridge.app bundle again.")
                            .foregroundStyle(.secondary)
                    }
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
                        Text("Keyboard slash navigation is unavailable in the current build. Use the mouse, or type an exact slash command and press Space.")
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
                        .accessibilityIdentifier("settings.chooseVault")

                        Button("Reveal in Finder") {
                            appModel.revealVault()
                        }
                        .disabled(!appModel.hasVaultConfigured)
                        .accessibilityIdentifier("settings.revealVault")
                    }

                    TextField(
                        "Export Folder Name",
                        text: Binding(
                            get: { appModel.settings.exportFolderName },
                            set: { appModel.settings.exportFolderName = $0 }
                        )
                    )
                }

                Section("Attachments") {
                    Toggle(
                        "Use Obsidian attachment folder from .obsidian/app.json",
                        isOn: Binding(
                            get: { appModel.settings.useObsidianAttachmentFolder },
                            set: { appModel.settings.useObsidianAttachmentFolder = $0 }
                        )
                    )

                    TextField(
                        "Default Attachment Folder",
                        text: Binding(
                            get: { appModel.settings.attachmentFolderName },
                            set: { appModel.settings.attachmentFolderName = $0 }
                        )
                    )

                    LabeledContent("Resolved Folder") {
                        Text(appModel.attachmentStorageBasePath)
                    }

                    Text(appModel.attachmentStorageSourceDescription)
                        .foregroundStyle(.secondary)

                    if let attachmentStorageWarning = appModel.attachmentStorageWarning {
                        Text(attachmentStorageWarning)
                            .foregroundStyle(.orange)
                    }

                    Text("Apple Notes attachments are stored in one shared root and keep the exported folder hierarchy underneath it.")
                        .foregroundStyle(.secondary)
                }

                Section("Apple Notes Data") {
                    LabeledContent("Folder") {
                        Text(appModel.settings.appleNotesDataPath ?? "Not configured")
                            .foregroundStyle(appModel.hasAppleNotesDataFolderConfigured ? .primary : .secondary)
                    }

                    LabeledContent("Access") {
                        Text(appModel.appleNotesDataAccessLabel)
                            .foregroundStyle(appleNotesAccessColor)
                    }

                    Button("Choose Apple Notes Data Folder") {
                        appModel.chooseAppleNotesDataFolder()
                    }

                    Text("Choose the macOS Apple Notes container folder named group.com.apple.notes so NotesBridge can read NoteStore.sqlite and native attachments.")
                        .foregroundStyle(.secondary)

                    if let appleNotesDataAccessStatus = appModel.appleNotesDataAccessStatus {
                        Text(appleNotesDataAccessStatus.message)
                            .foregroundStyle(
                                appleNotesDataAccessStatus.level == .accessible ? Color.secondary : Color.orange
                            )
                    }
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
                        .accessibilityIdentifier("settings.refreshFolders")

                        Button(appModel.isSyncing ? "Syncing..." : "Sync All Notes to Obsidian") {
                            Task {
                                await appModel.syncAllNotes()
                            }
                        }
                        .disabled(!appModel.hasVaultConfigured || appModel.isSyncing)
                        .accessibilityIdentifier("settings.syncAllNotes")
                    }
                }

                Section("Current Status") {
                    Text(appModel.statusMessage)
                        .accessibilityIdentifier("settings.currentStatus")

                    if appModel.isSyncing {
                        syncProgressSection
                    }

                    Text("Current selection: \(appModel.selectionSummary)")
                        .foregroundStyle(.secondary)
                    Text("Slash commands: \(appModel.slashCommandsSummary)")
                        .foregroundStyle(.secondary)

                    if !appModel.slashDiagnostics.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Slash diagnostics")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(Array(appModel.slashDiagnostics.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var appleNotesAccessColor: Color {
        switch appModel.appleNotesDataAccessStatus?.level {
        case .accessible:
            return .green
        case .limited:
            return .orange
        case .invalid:
            return .red
        case nil:
            return .secondary
        }
    }

    @ViewBuilder
    private var syncProgressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let syncProgress = appModel.syncProgress {
                ProgressView(value: syncProgress.fractionCompleted)
                    .progressViewStyle(.linear)
                Text(syncProgress.summaryText)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.syncProgressSummary")

                if let currentFolderText = syncProgress.currentFolderText {
                    Text(currentFolderText)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.syncProgressCurrentFolder")
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
