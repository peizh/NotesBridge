import SwiftUI

struct FormattingBarView: View {
    let commands: [FormattingCommand]
    let localization: AppLocalization
    let onCommand: (FormattingCommand) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(commands) { command in
                Button {
                    onCommand(command)
                } label: {
                    FloatingToolPaletteIcon(systemImage: command.systemImage)
                }
                .buttonStyle(.plain)
                .help(localization.text(command.titleKey))
                .accessibilityLabel(localization.text(command.titleKey))
            }
        }
        .floatingToolPaletteContainer()
    }
}
