import AppKit
import SwiftUI

@MainActor
final class SlashCommandMenuController {
    private let onHoverIndex: (Int) -> Void
    private let onSelectIndex: (Int) -> Void
    private var panel: NSPanel?
    private var hostingController: NSHostingController<SlashCommandMenuView>?

    init(
        onHoverIndex: @escaping (Int) -> Void,
        onSelectIndex: @escaping (Int) -> Void
    ) {
        self.onHoverIndex = onHoverIndex
        self.onSelectIndex = onSelectIndex
    }

    func update(entries: [SlashCommandEntry], selectedIndex: Int, anchorRect: CGRect?) {
        let panel = ensurePanel()
        hostingController?.rootView = rootView(entries: entries, selectedIndex: selectedIndex)

        let size = hostingController?.view.fittingSize ?? CGSize(width: 320, height: 120)
        let anchorRect = anchorRect.map(convertAccessibilityRectToAppKit) ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let targetScreen = screen(containing: anchorRect) ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSScreen.screens.reduce(CGRect.null) { partialResult, screen in
            partialResult.union(screen.visibleFrame)
        }
        let origin = bestPanelOrigin(for: anchorRect, panelSize: size, visibleFrame: visibleFrame)

        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let hostingController = NSHostingController(rootView: rootView(entries: [], selectedIndex: 0))
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.level = .floating
        panel.isFloatingPanel = true
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

    private func rootView(entries: [SlashCommandEntry], selectedIndex: Int) -> SlashCommandMenuView {
        SlashCommandMenuView(
            entries: entries,
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
}
