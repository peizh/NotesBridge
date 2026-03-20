import AppKit
import SwiftUI

@MainActor
final class FloatingFormattingBarController {
    private let executor: FormattingCommandExecutor
    private var panel: NSPanel?
    private var hostingController: NSHostingController<FormattingBarView>?

    init(executor: FormattingCommandExecutor) {
        self.executor = executor
    }

    func update(
        selectionContext: SelectionContext?,
        availability: InteractionAvailability,
        commands: [FormattingCommand],
        localization: AppLocalization
    ) {
        guard availability.canShowFormattingBar,
              let selectionContext,
              selectionContext.hasSelection,
              !commands.isEmpty
        else {
            hide()
            return
        }

        let anchorRect = selectionContext.selectionRect.map(convertAccessibilityRectToAppKit) ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let panel = ensurePanel()
        hostingController?.rootView = FormattingBarView(commands: commands, localization: localization) { [weak self] command in
            self?.executor.perform(command)
            self?.hide()
        }

        let size = hostingController?.view.fittingSize ?? CGSize(width: 420, height: 46)
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

        let rootView = FormattingBarView(commands: [], localization: AppLocalization(language: .system)) { [weak self] command in
            self?.executor.perform(command)
            self?.hide()
        }
        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 46),
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
        let verticalPadding: CGFloat = 10
        let preferredAboveY = anchorRect.maxY + verticalPadding
        let preferredBelowY = anchorRect.minY - panelSize.height - verticalPadding

        let aboveFits = preferredAboveY + panelSize.height <= visibleFrame.maxY
        let belowFits = preferredBelowY >= visibleFrame.minY

        let unclampedX = anchorRect.midX - (panelSize.width / 2)
        let x = min(
            max(unclampedX, visibleFrame.minX + horizontalPadding),
            visibleFrame.maxX - panelSize.width - horizontalPadding
        )

        let chosenY: CGFloat
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

        return CGPoint(x: x, y: chosenY)
    }
}
