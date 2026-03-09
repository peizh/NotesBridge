import SwiftUI

struct FormattingBarView: View {
    let commands: [FormattingCommand]
    let onCommand: (FormattingCommand) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(commands) { command in
                Button {
                    onCommand(command)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: command.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(command.shortLabel)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderless)
                .help(command.accessibilityLabel)
                .accessibilityLabel(command.accessibilityLabel)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary)
        }
        .padding(6)
    }
}
