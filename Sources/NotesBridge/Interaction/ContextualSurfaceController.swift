import AppKit
import SwiftUI

@MainActor
class ContextualSurfaceController {
    private(set) var panel: NSPanel?
    private(set) var hostingController: NSHostingController<AnyView>?
    private var lastFrame: CGRect?
    private var lastAnchorRect: CGRect?

    func update<Content: View>(
        rootView: Content,
        anchorRect: CGRect?,
        size: CGSize,
        preferredEdge: NSRectEdge
    ) {
        let panel = ensurePanel(with: rootView)
        if let hostingController {
            hostingController.rootView = AnyView(rootView)
            hostingController.view.layoutSubtreeIfNeeded()
            panel.contentView?.layoutSubtreeIfNeeded()
        }

        let appKitAnchorRect = anchorRect.map(convertAccessibilityRectToAppKit) ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let targetScreen = screen(containing: appKitAnchorRect) ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSScreen.screens.reduce(CGRect.null) { partialResult, screen in
            partialResult.union(screen.visibleFrame)
        }

        let origin = bestPanelOrigin(for: appKitAnchorRect, panelSize: size, visibleFrame: visibleFrame, preferredEdge: preferredEdge)
        let targetFrame = CGRect(origin: origin, size: size)

        if lastFrame.map({ !approximatelyEqual($0, targetFrame) }) ?? true {
            panel.setFrame(targetFrame, display: true)
            lastFrame = targetFrame
        }

        if !panel.isVisible {
            if panel.becomesKeyOnlyIfNeeded {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
        } else if !panel.isKeyWindow && panel.becomesKeyOnlyIfNeeded {
             panel.makeKey()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        lastFrame = nil
        lastAnchorRect = nil
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var isKeyWindow: Bool {
        panel?.isKeyWindow == true
    }

    func makePanel(contentRect: CGRect) -> NSPanel {
        let panel = ContextualSurfacePanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        return panel
    }

    private func ensurePanel<Content: View>(with rootView: Content) -> NSPanel {
        if let panel {
            return panel
        }

        let hostingController = NSHostingController(rootView: AnyView(rootView))
        let panel = makePanel(contentRect: CGRect(origin: .zero, size: hostingController.view.fittingSize))
        panel.contentViewController = hostingController
        panel.contentView?.layoutSubtreeIfNeeded()

        self.panel = panel
        self.hostingController = hostingController
        return panel
    }

    func convertAccessibilityRectToAppKit(_ rect: CGRect) -> CGRect {
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

    func screen(containing rect: CGRect) -> NSScreen? {
        let anchorPoint = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(anchorPoint) })
    }

    func bestPanelOrigin(
        for anchorRect: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        preferredEdge: NSRectEdge
    ) -> CGPoint {
        let horizontalPadding: CGFloat = FloatingToolPaletteStyle.surfaceHorizontalPadding
        let verticalPadding: CGFloat = preferredEdge == .maxY ? 10 : 6

        let preferredAboveY = anchorRect.maxY + verticalPadding
        let preferredBelowY = anchorRect.minY - panelSize.height - verticalPadding

        let aboveFits = preferredAboveY + panelSize.height <= visibleFrame.maxY
        let belowFits = preferredBelowY >= visibleFrame.minY

        let unclampedX: CGFloat
        if preferredEdge == .maxY {
            unclampedX = anchorRect.midX - (panelSize.width / 2)
        } else {
            unclampedX = anchorRect.minX - 6
        }

        let x = min(
            max(unclampedX, visibleFrame.minX + horizontalPadding),
            visibleFrame.maxX - panelSize.width - horizontalPadding
        )

        let chosenY: CGFloat
        if preferredEdge == .maxY {
            if aboveFits {
                chosenY = preferredAboveY
            } else if belowFits {
                chosenY = preferredBelowY
            } else {
                chosenY = min(
                    max(preferredAboveY, visibleFrame.minY + verticalPadding),
                    visibleFrame.maxY - panelSize.height - verticalPadding
                )
            }
        } else {
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
        }

        return CGPoint(x: x, y: chosenY)
    }

    func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = FloatingToolPaletteStyle.jitterTolerance) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }
}

class ContextualSurfacePanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
