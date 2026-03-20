import SwiftUI
import UniformTypeIdentifiers

struct SlashCommandCustomizationSheet: View {
    @Binding var items: [SlashCommandItemSetting]
    let localization: AppLocalization
    let onReset: () -> Void
    let onDone: () -> Void
    @State private var draggedCommand: FormattingCommand?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.text("Customize Slash Commands"))
                    .font(.title3.weight(.semibold))
                Text(localization.text("Reorder slash commands and choose which ones are visible in the slash menu."))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.command) { index, item in
                        row(for: item)
                        if index < items.count - 1 {
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
            }
            .onDrop(of: [.plainText], isTargeted: nil) { _, _ in
                draggedCommand = nil
                return false
            }
            .notesBridgeGlassCard(cornerRadius: NotesBridgeGlassStyle.compactCardCornerRadius)

            HStack {
                Spacer()

                Button(localization.text("Reset to Default")) {
                    onReset()
                }

                Button(localization.text("Done")) {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .frame(width: 440, height: 360)
    }

    private func visibilityBinding(for command: FormattingCommand) -> Binding<Bool> {
        Binding(
            get: {
                items.first(where: { $0.command == command })?.isVisible ?? false
            },
            set: { isVisible in
                guard let index = items.firstIndex(where: { $0.command == command }) else { return }
                items[index].isVisible = isVisible
            }
        )
    }

    @ViewBuilder
    private func row(for item: SlashCommandItemSetting) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 14)
                .onDrag {
                    draggedCommand = item.command
                    return NSItemProvider(object: item.command.rawValue as NSString)
                }

            Toggle(isOn: visibilityBinding(for: item.command)) {
                HStack(spacing: 8) {
                    Label(localization.text(item.command.titleKey), systemImage: item.command.systemImage)
                    Spacer(minLength: 8)
                    Text(SlashCommandCatalog.token(for: item.command))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .opacity(draggedCommand == item.command ? 0.55 : 1)
        .onDrop(
            of: [.plainText],
            delegate: SlashCommandItemDropDelegate(
                targetCommand: item.command,
                items: $items,
                draggedCommand: $draggedCommand
            )
        )
    }
}

private struct SlashCommandItemDropDelegate: DropDelegate {
    let targetCommand: FormattingCommand
    @Binding var items: [SlashCommandItemSetting]
    @Binding var draggedCommand: FormattingCommand?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let draggedCommand,
              draggedCommand != targetCommand,
              let fromIndex = items.firstIndex(where: { $0.command == draggedCommand }),
              let toIndex = items.firstIndex(where: { $0.command == targetCommand })
        else {
            return
        }

        if items[toIndex].command != draggedCommand {
            items.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: fromIndex < toIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedCommand = nil
        return true
    }
}
