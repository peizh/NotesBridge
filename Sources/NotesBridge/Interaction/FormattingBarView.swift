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
                    Image(systemName: command.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(localization.text(command.titleKey))
                .accessibilityLabel(localization.text(command.titleKey))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary)
        }
        .padding(4)
    }
}
