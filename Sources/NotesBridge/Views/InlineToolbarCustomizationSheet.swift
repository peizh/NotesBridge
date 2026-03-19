import SwiftUI
import UniformTypeIdentifiers

struct InlineToolbarCustomizationSheet: View {
    @Binding var items: [InlineToolbarItemSetting]
    let localization: AppLocalization
    let onReset: () -> Void
    let onDone: () -> Void
    @State private var draggedCommand: FormattingCommand?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.text("Customize Inline Toolbar"))
                    .font(.title3.weight(.semibold))
                Text(localization.text("Reorder items and choose which ones are visible in the inline toolbar."))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.command) { index, item in
                        row(for: item, index: index)
                        if index < items.count - 1 {
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.quaternary)
            )

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
        .padding(18)
        .frame(width: 440, height: 420)
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
    private func row(for item: InlineToolbarItemSetting, index: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 14)
                .onDrag {
                    draggedCommand = item.command
                    return NSItemProvider(object: item.command.rawValue as NSString)
                }

            Toggle(isOn: visibilityBinding(for: item.command)) {
                Label(localization.text(item.command.titleKey), systemImage: item.command.systemImage)
            }
            .toggleStyle(.checkbox)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(draggedCommand == item.command ? 0.55 : 1)
        .onDrop(
            of: [.plainText],
            delegate: InlineToolbarItemDropDelegate(
                targetCommand: item.command,
                items: $items,
                draggedCommand: $draggedCommand
            )
        )
    }
}

private struct InlineToolbarItemDropDelegate: DropDelegate {
    let targetCommand: FormattingCommand
    @Binding var items: [InlineToolbarItemSetting]
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
