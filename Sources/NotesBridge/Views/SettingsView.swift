import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showingInlineToolbarCustomization = false
    @State private var showingSlashCommandCustomization = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(appModel.t("NotesBridge Settings"))
                .font(.largeTitle.weight(.semibold))
                .accessibilityIdentifier("settings.title")

            Form {
                Section(appModel.t("Version")) {
                    LabeledContent(appModel.t("Build")) {
                        Text(appModel.localizedBuildFlavorTitle)
                    }

                    LabeledContent(appModel.t("Version")) {
                        Text(appModel.currentAppVersionDisplay)
                            .accessibilityIdentifier("settings.currentVersion")
                    }

                    Picker(
                        appModel.t("Language"),
                        selection: Binding(
                            get: { appModel.settings.appLanguage },
                            set: { appModel.settings.appLanguage = $0 }
                        )
                    ) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(appModel.languageDisplayName(for: language)).tag(language)
                        }
                    }

                    Text(
                        appModel.buildFlavor.supportsInlineEnhancements
                            ? appModel.t("This build can enhance Apple Notes inline through Accessibility.")
                            : appModel.t("This build only exposes settings, sync, and integration features.")
                    )
                    .foregroundStyle(.secondary)

                    if appModel.showsAppUpdateSettings {
                        Button(appModel.t("Check for Updates...")) {
                            appModel.checkForUpdates()
                        }
                        .disabled(!appModel.canCheckForUpdates)
                        .accessibilityIdentifier("settings.checkForUpdates")

                        Toggle(
                            appModel.t("Automatically check for updates"),
                            isOn: Binding(
                                get: { appModel.automaticallyChecksForUpdates },
                                set: { appModel.setAutomaticallyChecksForUpdates($0) }
                            )
                        )
                        .accessibilityIdentifier("settings.automaticallyChecksForUpdates")

                        Toggle(
                            appModel.t("Automatically download and install updates"),
                            isOn: Binding(
                                get: { appModel.automaticallyDownloadsUpdates },
                                set: { appModel.setAutomaticallyDownloadsUpdates($0) }
                            )
                        )
                        .disabled(!appModel.automaticallyChecksForUpdates)
                        .accessibilityIdentifier("settings.automaticallyDownloadsUpdates")

                        Text(appModel.t("NotesBridge checks GitHub Releases through Sparkle for direct-download updates."))
                            .foregroundStyle(.secondary)
                    }
                }

                Section(appModel.t("Permissions")) {
                    LabeledContent(appModel.t("Launch Mode")) {
                        Text(appModel.isRunningBundledApp ? appModel.t("Bundled App") : appModel.t("Command-line build"))
                            .foregroundStyle(appModel.isRunningBundledApp ? .green : .orange)
                    }

                    LabeledContent(appModel.t("Accessibility")) {
                        Text(appModel.interactionState.availability.accessibilityGranted ? appModel.t("Granted") : appModel.t("Required"))
                            .foregroundStyle(appModel.interactionState.availability.accessibilityGranted ? .green : .orange)
                    }

                    HStack {
                        Button(appModel.t("Request Accessibility Permission")) {
                            appModel.requestAccessibilityPermission()
                        }
                        .disabled(!appModel.buildFlavor.supportsInlineEnhancements)

                        Button(appModel.t("Open Accessibility Settings")) {
                            appModel.openAccessibilitySettings()
                        }
                    }

                    if appModel.isRunningBundledApp {
                        Button(appModel.t("Reveal NotesBridge App in Finder")) {
                            appModel.revealCurrentAppInFinder()
                        }
                    }

                    if !appModel.isRunningBundledApp && appModel.buildFlavor.supportsInlineEnhancements {
                        Button(appModel.t("Relaunch as Bundled App")) {
                            appModel.relaunchAsBundledApp()
                        }
                    }

                    Text(appModel.inlineEnhancementsSummary)
                        .foregroundStyle(.secondary)

                    if appModel.isRunningBundledApp && !appModel.interactionState.availability.accessibilityGranted {
                        Text(appModel.t("If NotesBridge is already checked in Accessibility but still shows Required here, remove it and add the current NotesBridge.app bundle again."))
                            .foregroundStyle(.secondary)
                    }

                    if appModel.showsAppUpdateSettings {
                        LabeledContent(appModel.t("App Management")) {
                            Text(appModel.appManagementPermissionLabel)
                                .foregroundStyle(.orange)
                        }

                        HStack {
                            Button(appModel.t("Request App Management Permission")) {
                                appModel.requestAppManagementPermission()
                            }

                            Button(appModel.t("Open App Management Settings")) {
                                appModel.openAppManagementSettings()
                            }
                        }

                        Text(appModel.appManagementPermissionSummary)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(appModel.t("Inline Enhancements")) {
                    Toggle(
                        appModel.t("Enable inline Apple Notes enhancements"),
                        isOn: Binding(
                            get: { appModel.settings.enableInlineEnhancements },
                            set: { appModel.settings.enableInlineEnhancements = $0 }
                        )
                    )
                    .disabled(!appModel.buildFlavor.supportsInlineEnhancements)

                    LabeledContent(appModel.t("Inline Toolbar")) {
                        HStack(spacing: 12) {
                            Toggle(
                                appModel.t("Enable Inline Toolbar"),
                                isOn: Binding(
                                    get: { appModel.settings.enableFormattingBar },
                                    set: { appModel.settings.enableFormattingBar = $0 }
                                )
                            )

                            Button(appModel.t("Customize...")) {
                                showingInlineToolbarCustomization = true
                            }
                            .disabled(!appModel.settings.enableFormattingBar)
                        }
                    }
                    .disabled(!appModel.buildFlavor.supportsInlineEnhancements || !appModel.settings.enableInlineEnhancements)

                    LabeledContent(appModel.t("Slash Commands")) {
                        HStack(spacing: 12) {
                            Toggle(
                                appModel.t("Enable slash commands"),
                                isOn: Binding(
                                    get: { appModel.settings.enableSlashCommands },
                                    set: { appModel.settings.enableSlashCommands = $0 }
                                )
                            )

                            Button(appModel.t("Customize...")) {
                                showingSlashCommandCustomization = true
                            }
                            .disabled(!appModel.settings.enableSlashCommands)
                        }
                    }
                    .disabled(!appModel.buildFlavor.supportsInlineEnhancements || !appModel.settings.enableInlineEnhancements)

                    LabeledContent(appModel.t("Markdown")) {
                        Toggle(
                            appModel.t("Enable Markdown"),
                            isOn: Binding(
                                get: { appModel.settings.enableMarkdownTriggers },
                                set: { appModel.settings.enableMarkdownTriggers = $0 }
                            )
                        )
                    }
                    .disabled(!appModel.buildFlavor.supportsInlineEnhancements || !appModel.settings.enableInlineEnhancements)

                    Text(appModel.t("Use / to open slash suggestions, or type an exact slash command and press Space to apply it inline."))
                        .foregroundStyle(.secondary)

                    Text(appModel.t("Inline enhancements support the formatting bar, markdown/list triggers, and slash commands."))
                        .foregroundStyle(.secondary)
                }

                Section(appModel.t("Obsidian")) {
                    LabeledContent(appModel.t("Vault")) {
                        Text(appModel.settings.vaultPath ?? appModel.t("Not configured"))
                            .foregroundStyle(appModel.hasVaultConfigured ? .primary : .secondary)
                    }

                    HStack {
                        Button(appModel.t("Choose Vault")) {
                            appModel.chooseVaultDirectory()
                        }
                        .accessibilityIdentifier("settings.chooseVault")

                        Button(appModel.t("Reveal in Finder")) {
                            appModel.revealVault()
                        }
                        .disabled(!appModel.hasVaultConfigured)
                        .accessibilityIdentifier("settings.revealVault")
                    }

                    TextField(
                        appModel.t("Export Folder Name"),
                        text: Binding(
                            get: { appModel.settings.exportFolderName },
                            set: { appModel.settings.exportFolderName = $0 }
                        )
                    )
                }

                Section(appModel.t("Attachments")) {
                    Toggle(
                        appModel.t("Use Obsidian attachment folder from .obsidian/app.json"),
                        isOn: Binding(
                            get: { appModel.settings.useObsidianAttachmentFolder },
                            set: { appModel.settings.useObsidianAttachmentFolder = $0 }
                        )
                    )

                    TextField(
                        appModel.t("Default Attachment Folder"),
                        text: Binding(
                            get: { appModel.settings.attachmentFolderName },
                            set: { appModel.settings.attachmentFolderName = $0 }
                        )
                    )

                    LabeledContent(appModel.t("Resolved Folder")) {
                        Text(appModel.attachmentStorageBasePath)
                    }

                    Text(appModel.attachmentStorageSourceDescription)
                        .foregroundStyle(.secondary)

                    if let attachmentStorageWarning = appModel.attachmentStorageWarning {
                        Text(attachmentStorageWarning)
                            .foregroundStyle(.orange)
                    }

                    Text(appModel.t("Apple Notes attachments are stored in one shared root and keep the exported folder hierarchy underneath it."))
                        .foregroundStyle(.secondary)
                }

                Section(appModel.t("Apple Notes Data")) {
                    LabeledContent(appModel.t("Folder")) {
                        Text(appModel.settings.appleNotesDataPath ?? appModel.t("Not configured"))
                            .foregroundStyle(appModel.hasAppleNotesDataFolderConfigured ? .primary : .secondary)
                    }

                    LabeledContent(appModel.t("Access")) {
                        Text(appModel.appleNotesDataAccessLabel)
                            .foregroundStyle(appleNotesAccessColor)
                    }

                    Button(appModel.t("Choose Apple Notes Data Folder")) {
                        appModel.chooseAppleNotesDataFolder()
                    }

                    Text(appModel.t("Choose the macOS Apple Notes container folder named group.com.apple.notes so NotesBridge can read NoteStore.sqlite and native attachments."))
                        .foregroundStyle(.secondary)

                    if let appleNotesDataAccessStatus = appModel.appleNotesDataAccessStatus {
                        Text(appleNotesDataAccessStatus.message)
                            .foregroundStyle(
                                appleNotesDataAccessStatus.level == .accessible ? Color.secondary : Color.orange
                            )
                    }
                }

                Section(appModel.t("Indexing & Sync")) {
                    LabeledContent(appModel.t("Known Folders")) {
                        Text("\(appModel.knownFolderCount)")
                    }
                    LabeledContent(appModel.t("Indexed Notes")) {
                        Text("\(appModel.syncedNoteCount)")
                    }
                    LabeledContent(appModel.t("Last Sync")) {
                        Text(appModel.lastSyncLabel)
                    }
                    LabeledContent(appModel.t("Last Full Sync")) {
                        Text(appModel.lastFullSyncLabel)
                    }

                    Toggle(
                        appModel.t("Enable Automatic Sync"),
                        isOn: Binding(
                            get: { appModel.settings.automaticSyncEnabled },
                            set: { appModel.settings.automaticSyncEnabled = $0 }
                        )
                    )

                    Picker(
                        appModel.t("Automatic Sync Trigger"),
                        selection: Binding(
                            get: { appModel.settings.automaticSyncTrigger },
                            set: { appModel.settings.automaticSyncTrigger = $0 }
                        )
                    ) {
                        ForEach(AutomaticSyncTrigger.allCases) { trigger in
                            Text(appModel.t(trigger.displayKey)).tag(trigger)
                        }
                    }
                    .disabled(!appModel.settings.automaticSyncEnabled)

                    if appModel.settings.automaticSyncTrigger == .periodic {
                        Picker(
                            appModel.t("Automatic Sync Interval"),
                            selection: Binding(
                                get: { appModel.settings.automaticSyncInterval },
                                set: { appModel.settings.automaticSyncInterval = $0 }
                            )
                        ) {
                            ForEach(AutomaticSyncInterval.allCases) { interval in
                                Text(appModel.t(interval.displayKey)).tag(interval)
                            }
                        }
                        .disabled(!appModel.settings.automaticSyncEnabled)
                    }

                    HStack {
                        Button(appModel.t("Refresh Folder Index")) {
                            Task {
                                await appModel.refreshFolderSummaries()
                            }
                        }
                        .disabled(appModel.isRefreshingFolders)
                        .accessibilityIdentifier("settings.refreshFolders")

                        Button(appModel.isSyncing ? appModel.t("Syncing...") : appModel.t("Sync Changed Notes")) {
                            Task {
                                await appModel.syncChangedNotes()
                            }
                        }
                        .disabled(!appModel.hasVaultConfigured || appModel.isSyncing)
                        .accessibilityIdentifier("settings.syncAllNotes")

                        Button(appModel.t("Run Full Sync")) {
                            Task {
                                await appModel.runFullSync()
                            }
                        }
                        .disabled(!appModel.hasVaultConfigured || appModel.isSyncing)
                        .accessibilityIdentifier("settings.runFullSync")
                    }
                }

                Section(appModel.t("Current Status")) {
                    Text(appModel.statusMessage)
                        .accessibilityIdentifier("settings.currentStatus")

                    if appModel.isSyncing {
                        syncProgressSection
                    }

                    Text(appModel.tf("Current selection: %@", appModel.selectionSummary))
                        .foregroundStyle(.secondary)
                    Text(appModel.tf("Slash commands: %@", appModel.slashCommandsSummary))
                        .foregroundStyle(.secondary)

                    if !appModel.slashDiagnostics.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appModel.t("Slash diagnostics"))
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
        .sheet(isPresented: $showingInlineToolbarCustomization) {
            InlineToolbarCustomizationSheet(
                items: Binding(
                    get: { appModel.settings.inlineToolbarItems },
                    set: { appModel.settings.inlineToolbarItems = InlineToolbarItemSetting.normalized($0) }
                ),
                localization: appModel.localization,
                onReset: {
                    appModel.resetInlineToolbarItems()
                },
                onDone: {
                    showingInlineToolbarCustomization = false
                }
            )
        }
        .sheet(isPresented: $showingSlashCommandCustomization) {
            SlashCommandCustomizationSheet(
                items: Binding(
                    get: { appModel.settings.slashCommandItems },
                    set: { appModel.settings.slashCommandItems = SlashCommandItemSetting.normalized($0) }
                ),
                localization: appModel.localization,
                onReset: {
                    appModel.resetSlashCommandItems()
                },
                onDone: {
                    showingSlashCommandCustomization = false
                }
            )
        }
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
                Text(syncProgress.localizedSummaryText(using: appModel.localization))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.syncProgressSummary")

                if let currentFolderText = syncProgress.localizedCurrentFolderText(using: appModel.localization) {
                    Text(currentFolderText)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.syncProgressCurrentFolder")
                }
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                Text(appModel.t("Preparing sync progress..."))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
