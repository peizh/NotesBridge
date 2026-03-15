import SwiftUI

struct SlashCommandMenuView: View {
    let entries: [SlashCommandEntry]
    let localization: AppLocalization
    let selectedIndex: Int
    let onHoverIndex: (Int) -> Void
    let onSelectIndex: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button {
                    onSelectIndex(index)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.localizedTitle(using: localization))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(entry.token)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        Image(systemName: entry.command.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(for: index))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    if isHovering {
                        onHoverIndex(index)
                    }
                }
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

    @ViewBuilder
    private func background(for index: Int) -> some View {
        if index == selectedIndex {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.18))
        } else {
            Color.clear
        }
    }
}
