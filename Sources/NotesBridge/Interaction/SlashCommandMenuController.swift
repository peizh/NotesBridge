import AppKit
import SwiftUI

@MainActor
final class SlashCommandMenuController: ContextualSurfaceController {
    private let onHoverIndex: (Int) -> Void
    private let onSelectIndex: (Int) -> Void
    private let onFrameUpdated: (CGRect) -> Void
    private let onKeyboardAction: (SlashCommandKeyboardAction) -> Void
    private let onPassthroughKeyDown: (NSEvent) -> Void

    private var lastEntries: [SlashCommandEntry] = []
    private var lastSelectedIndex = 0
    private var lastLocalization = AppLocalization(language: .system)

    init(
        onHoverIndex: @escaping (Int) -> Void,
        onSelectIndex: @escaping (Int) -> Void,
        onFrameUpdated: @escaping (CGRect) -> Void,
        onKeyboardAction: @escaping (SlashCommandKeyboardAction) -> Void,
        onPassthroughKeyDown: @escaping (NSEvent) -> Void
    ) {
        self.onHoverIndex = onHoverIndex
        self.onSelectIndex = onSelectIndex
        self.onFrameUpdated = onFrameUpdated
        self.onKeyboardAction = onKeyboardAction
        self.onPassthroughKeyDown = onPassthroughKeyDown
    }

    func update(entries: [SlashCommandEntry], localization: AppLocalization, selectedIndex: Int, anchorRect: CGRect?) {
        let contentChanged = lastEntries != entries || lastSelectedIndex != selectedIndex || lastLocalization.language != localization.language
        if contentChanged {
            lastEntries = entries
            lastSelectedIndex = selectedIndex
            lastLocalization = localization
        }

        let fittedSize = hostingController?.view.fittingSize ?? CGSize(width: 260, height: 88)
        let size = CGSize(
            width: max(260, fittedSize.width),
            height: max(44, fittedSize.height)
        )

        let rootView = SlashCommandMenuView(
            entries: entries,
            localization: localization,
            selectedIndex: selectedIndex,
            onHoverIndex: onHoverIndex,
            onSelectIndex: onSelectIndex
        )

        let oldFrame = panel?.frame
        update(rootView: rootView, anchorRect: anchorRect, size: size, preferredEdge: .minY)

        if let newFrame = panel?.frame, oldFrame != newFrame {
            onFrameUpdated(newFrame)
        }
    }

    override func makePanel(contentRect: CGRect) -> NSPanel {
        let panel = SlashCommandPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            onKeyboardAction: onKeyboardAction,
            onPassthroughKeyDown: onPassthroughKeyDown
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        return panel
    }
}

private final class SlashCommandPanel: ContextualSurfacePanel {
    private let onKeyboardAction: (SlashCommandKeyboardAction) -> Void
    private let onPassthroughKeyDown: (NSEvent) -> Void

    init(
        contentRect: CGRect,
        styleMask style: NSWindow.StyleMask,
        backing bufferingType: NSWindow.BackingStoreType,
        defer flag: Bool,
        onKeyboardAction: @escaping (SlashCommandKeyboardAction) -> Void,
        onPassthroughKeyDown: @escaping (NSEvent) -> Void
    ) {
        self.onKeyboardAction = onKeyboardAction
        self.onPassthroughKeyDown = onPassthroughKeyDown
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
    }

    override func keyDown(with event: NSEvent) {
        guard let action = SlashCommandKeyboardAction(keyCode: event.keyCode) else {
            onPassthroughKeyDown(event)
            return
        }

        onKeyboardAction(action)
    }

    override func cancelOperation(_ sender: Any?) {
        onKeyboardAction(.dismiss)
    }
}
