import AppKit
import SwiftUI

@MainActor
final class SlashCommandMenuController {
    private let onHoverIndex: (Int) -> Void
    private let onSelectIndex: (Int) -> Void
    private let onFrameUpdated: (CGRect) -> Void
    private let onKeyboardAction: (SlashCommandKeyboardAction) -> Void
    private let onPassthroughKeyDown: (NSEvent) -> Void
    private var panel: NSPanel?
    private var hostingController: NSHostingController<SlashCommandMenuView>?
    private var lastEntries: [SlashCommandEntry] = []
    private var lastSelectedIndex = 0
    private var lastFrame: CGRect?
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
        let panel = ensurePanel()
        let contentChanged = lastEntries != entries || lastSelectedIndex != selectedIndex || lastLocalization.language != localization.language
        if contentChanged {
            hostingController?.rootView = rootView(entries: entries, localization: localization, selectedIndex: selectedIndex)
            hostingController?.view.layoutSubtreeIfNeeded()
            panel.contentView?.layoutSubtreeIfNeeded()
            lastEntries = entries
            lastSelectedIndex = selectedIndex
            lastLocalization = localization
        }

        let fittedSize = hostingController?.view.fittingSize ?? CGSize(width: 260, height: 88)
        let size = CGSize(
            width: max(260, fittedSize.width),
            height: max(44, fittedSize.height)
        )
        let anchorRect = anchorRect.map(convertAccessibilityRectToAppKit) ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let targetScreen = screen(containing: anchorRect) ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSScreen.screens.reduce(CGRect.null) { partialResult, screen in
            partialResult.union(screen.visibleFrame)
        }
        let origin = bestPanelOrigin(for: anchorRect, panelSize: size, visibleFrame: visibleFrame)
        let targetFrame = CGRect(origin: origin, size: size)

        if lastFrame.map({ !approximatelyEqual($0, targetFrame) }) ?? true {
            panel.setFrame(targetFrame, display: true)
            lastFrame = targetFrame
            onFrameUpdated(panel.frame)
        }

        if !panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        } else if !panel.isKeyWindow {
            panel.makeKey()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        lastFrame = nil
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var isKeyWindow: Bool {
        panel?.isKeyWindow == true
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let hostingController = NSHostingController(rootView: rootView(entries: [], localization: lastLocalization, selectedIndex: 0))
        let panel = SlashCommandPanel(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 88),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            onKeyboardAction: onKeyboardAction,
            onPassthroughKeyDown: onPassthroughKeyDown
        )
        panel.contentViewController = hostingController
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.contentView?.layoutSubtreeIfNeeded()

        self.panel = panel
        self.hostingController = hostingController
        return panel
    }

    private func rootView(entries: [SlashCommandEntry], localization: AppLocalization, selectedIndex: Int) -> SlashCommandMenuView {
        SlashCommandMenuView(
            entries: entries,
            localization: localization,
            selectedIndex: selectedIndex,
            onHoverIndex: onHoverIndex,
            onSelectIndex: onSelectIndex
        )
    }

    private func convertAccessibilityRectToAppKit(_ rect: CGRect) -> CGRect {
        let desktopFrame = NSScreen.screens.reduce(CGRect.null) { partialResult, screen in
            partialResult.union(screen.frame)
        }
        guard !desktopFrame.isNull else { return rect }

        return CGRect(
            x: rect.origin.x,
            y: desktopFrame.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        let anchorPoint = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) })
    }

    private func bestPanelOrigin(for anchorRect: CGRect, panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 6
        let preferredBelowY = anchorRect.minY - panelSize.height - verticalPadding
        let preferredAboveY = anchorRect.maxY + verticalPadding

        let belowFits = preferredBelowY >= visibleFrame.minY
        let aboveFits = preferredAboveY + panelSize.height <= visibleFrame.maxY

        let x = min(
            max(anchorRect.minX - 6, visibleFrame.minX + horizontalPadding),
            visibleFrame.maxX - panelSize.width - horizontalPadding
        )

        let chosenY: CGFloat
        if belowFits {
            chosenY = preferredBelowY
        } else if aboveFits {
            chosenY = preferredAboveY
        } else {
            chosenY = min(
                max(preferredBelowY, visibleFrame.minY + verticalPadding),
                visibleFrame.maxY - panelSize.height - verticalPadding
            )
        }

        return CGPoint(x: x, y: chosenY)
    }

    private func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }
}

private final class SlashCommandPanel: NSPanel {
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

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
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
