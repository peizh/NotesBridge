import SwiftUI

struct SlashCommandMenuView: View {
    let entries: [SlashCommandEntry]
    let localization: AppLocalization
    let selectedIndex: Int
    let onHoverIndex: (Int) -> Void
    let onSelectIndex: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button {
                    onSelectIndex(index)
                } label: {
                    HStack(spacing: FloatingToolPaletteStyle.rowSpacing) {
                        FloatingToolPaletteIcon(
                            systemImage: entry.command.systemImage,
                            foregroundStyle: AnyShapeStyle(index == selectedIndex ? .primary : .secondary)
                        )

                        Text(entry.localizedTitle(using: localization))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Text(entry.token)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, FloatingToolPaletteStyle.rowHorizontalPadding)
                    .padding(.vertical, FloatingToolPaletteStyle.rowVerticalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(for: index))
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: FloatingToolPaletteStyle.rowCornerRadius,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    if isHovering {
                        onHoverIndex(index)
                    }
                }
            }
        }
        .floatingToolPaletteContainer()
    }

    @ViewBuilder
    private func background(for index: Int) -> some View {
        if index == selectedIndex {
            RoundedRectangle(cornerRadius: FloatingToolPaletteStyle.rowCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(FloatingToolPaletteStyle.rowSelectionOpacity))
        } else {
            Color.clear
        }
    }
}
