import Testing
@testable import NotesBridge

struct InteractionAvailabilityTests {
    @Test
    func slashCommandsDoNotRequireInputMonitoringForCoreExecution() {
        let availability = InteractionAvailability(
            buildFlavor: .directDownload,
            accessibilityGranted: true,
            inputMonitoringGranted: false,
            notesIsFrontmost: true,
            editableFocus: true,
            inlineEnhancementsEnabled: true,
            formattingBarEnabled: true,
            markdownTriggersEnabled: true,
            slashCommandsEnabled: true
        )

        #expect(availability.canRunSlashCommands)
    }

    @Test
    func markdownTriggersDoNotRequireInputMonitoring() {
        let availability = InteractionAvailability(
            buildFlavor: .directDownload,
            accessibilityGranted: true,
            inputMonitoringGranted: false,
            notesIsFrontmost: true,
            editableFocus: true,
            inlineEnhancementsEnabled: true,
            formattingBarEnabled: true,
            markdownTriggersEnabled: true,
            slashCommandsEnabled: true
        )

        #expect(availability.canRunMarkdownTriggers)
    }
}
