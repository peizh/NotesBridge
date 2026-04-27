import SwiftUI

struct FormattingBarView: View {
    let commands: [FormattingCommand]
    let localization: AppLocalization
    let onCommand: (FormattingCommand) -> Void

    var body: some View {
        let groups = FormattingBarLayout.groups(for: commands)
        let surfaceSize = FormattingBarLayout.surfaceSize(for: commands)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        HStack(spacing: FormattingBarLayout.buttonSpacing) {
                            ForEach(group) { command in
                                FormattingBarCommandButton(command: command, localization: localization, onCommand: onCommand)
                            }
                        }

                        if index < groups.count - 1 {
                            FormattingBarSeparator()
                                .padding(.horizontal, FormattingBarLayout.separatorSpacing)
                        }
                    }
                }
                .frame(
                    minWidth: max(
                        FormattingBarLayout.minimumWidth - (FormattingBarLayout.horizontalPadding * 2),
                        0
                    ),
                    alignment: .center
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, FormattingBarLayout.horizontalPadding)
            .padding(.vertical, FormattingBarLayout.verticalPadding)
        }
        .frame(
            width: surfaceSize.width,
            height: surfaceSize.height
        )
        .background {
            RoundedRectangle(cornerRadius: FormattingBarLayout.containerCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: FormattingBarLayout.containerCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.34), lineWidth: 0.8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: FormattingBarLayout.containerCornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                .padding(0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: FormattingBarLayout.containerCornerRadius, style: .continuous))
        .padding(FormattingBarLayout.outerPadding)
    }
}

private struct FormattingBarCommandButton: View {
    let command: FormattingCommand
    let localization: AppLocalization
    let onCommand: (FormattingCommand) -> Void

    @State private var isHovering = false

    var body: some View {
        Button {
            onCommand(command)
        } label: {
            Image(systemName: command.systemImage)
                .font(.system(size: 14.5, weight: .semibold))
                .frame(
                    width: FormattingBarLayout.buttonSize,
                    height: FormattingBarLayout.buttonSize
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: FormattingBarLayout.buttonCornerRadius,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(FormattingBarCommandButtonStyle(isHovering: isHovering))
        .onHover { hovering in
            isHovering = hovering
        }
        .help(localization.text(command.titleKey))
        .accessibilityLabel(localization.text(command.titleKey))
    }
}

private struct FormattingBarCommandButtonStyle: ButtonStyle {
    let isHovering: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fillOpacity: CGFloat = if !isEnabled {
            0.06
        } else if configuration.isPressed {
            0.24
        } else if isHovering {
            0.14
        } else {
            0
        }

        let strokeOpacity: CGFloat = if !isEnabled {
            0.08
        } else if configuration.isPressed {
            0.18
        } else if isHovering {
            0.12
        } else {
            0
        }

        return configuration.label
            .foregroundStyle(Color.primary.opacity(isEnabled ? 0.92 : 0.42))
            .background {
                RoundedRectangle(
                    cornerRadius: FormattingBarLayout.buttonCornerRadius,
                    style: .continuous
                )
                .fill(Color.white.opacity(fillOpacity))
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: FormattingBarLayout.buttonCornerRadius,
                    style: .continuous
                )
                .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}

private struct FormattingBarSeparator: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.06),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: FormattingBarLayout.separatorWidth, height: 22)
            .overlay(alignment: .trailing) {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 1, height: 22)
                    .offset(x: 0.5)
            }
    }
}
