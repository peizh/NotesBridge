import Foundation

struct InteractionAvailability: Equatable, Sendable {
    var buildFlavor: BuildFlavor
    var accessibilityGranted: Bool
    var inputMonitoringGranted: Bool
    var notesIsFrontmost: Bool
    var editableFocus: Bool
    var inlineEnhancementsEnabled: Bool
    var formattingBarEnabled: Bool
    var markdownTriggersEnabled: Bool
    var slashCommandsEnabled: Bool

    static func `default`(for buildFlavor: BuildFlavor) -> InteractionAvailability {
        InteractionAvailability(
            buildFlavor: buildFlavor,
            accessibilityGranted: false,
            inputMonitoringGranted: false,
            notesIsFrontmost: false,
            editableFocus: false,
            inlineEnhancementsEnabled: false,
            formattingBarEnabled: false,
            markdownTriggersEnabled: false,
            slashCommandsEnabled: false
        )
    }

    var supportsInlineEnhancements: Bool {
        buildFlavor.supportsInlineEnhancements
    }

    var canMonitorNotes: Bool {
        supportsInlineEnhancements && accessibilityGranted && inlineEnhancementsEnabled
    }

    var canShowFormattingBar: Bool {
        canMonitorNotes && notesIsFrontmost && editableFocus && formattingBarEnabled
    }

    var canRunMarkdownTriggers: Bool {
        canMonitorNotes && notesIsFrontmost && editableFocus && markdownTriggersEnabled
    }

    var canRunSlashCommands: Bool {
        canMonitorNotes && notesIsFrontmost && editableFocus && slashCommandsEnabled
    }

    var summary: String {
        if !supportsInlineEnhancements {
            return "Inline enhancements are disabled in the Mac App Store build."
        }
        if !accessibilityGranted {
            return "Accessibility permission is required for Notes enhancements."
        }
        if !inlineEnhancementsEnabled {
            return "Inline enhancements are disabled in Settings."
        }
        if !notesIsFrontmost {
            return "Bring Apple Notes to the front to enable formatting tools."
        }
        if !editableFocus {
            return "Focus the Apple Notes editor to use inline formatting tools."
        }
        return "Inline enhancements are active in Apple Notes."
    }
}
