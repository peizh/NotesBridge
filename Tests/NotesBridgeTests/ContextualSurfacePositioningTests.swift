import XCTest
import SwiftUI
@testable import NotesBridge

@MainActor
final class ContextualSurfacePositioningTests: XCTestCase {
    private var controller: ContextualSurfaceController!

    override func setUp() {
        super.setUp()
        controller = ContextualSurfaceController()
    }

    func testBestPanelOriginPreferredBelow() {
        let anchorRect = CGRect(x: 100, y: 500, width: 200, height: 20)
        let panelSize = CGSize(width: 260, height: 100)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        // Preferred below (.minY)
        let origin = controller.bestPanelOrigin(
            for: anchorRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            preferredEdge: .minY
        )

        // anchorRect.minY - panelSize.height - verticalPadding (6)
        // 500 - 100 - 6 = 394
        XCTAssertEqual(origin.y, 394)
        // unclampedX = 100 - 6 = 94
        XCTAssertEqual(origin.x, 94)
    }

    func testBestPanelOriginPreferredAbove() {
        let anchorRect = CGRect(x: 100, y: 500, width: 200, height: 20)
        let panelSize = CGSize(width: 260, height: 100)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        // Preferred above (.maxY)
        let origin = controller.bestPanelOrigin(
            for: anchorRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            preferredEdge: .maxY
        )

        // anchorRect.maxY + verticalPadding (10)
        // 520 + 10 = 530
        XCTAssertEqual(origin.y, 530)
        // unclampedX = 100 + 100 - 130 = 70 (midX - panelSize.width / 2)
        XCTAssertEqual(origin.x, 70)
    }

    func testBestPanelOriginFlipsBelowToAbove() {
        // Anchor near bottom
        let anchorRect = CGRect(x: 100, y: 50, width: 200, height: 20)
        let panelSize = CGSize(width: 260, height: 100)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        // Preferred below, but not enough space
        let origin = controller.bestPanelOrigin(
            for: anchorRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            preferredEdge: .minY
        )

        // Should flip to above: 70 + 6 = 76
        XCTAssertEqual(origin.y, 76)
    }

    func testBestPanelOriginFlipsAboveToBelow() {
        // Anchor near top
        let anchorRect = CGRect(x: 100, y: 950, width: 200, height: 20)
        let panelSize = CGSize(width: 260, height: 100)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        // Preferred above, but not enough space
        let origin = controller.bestPanelOrigin(
            for: anchorRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            preferredEdge: .maxY
        )

        // Should flip to below: 950 - 100 - 10 = 840
        XCTAssertEqual(origin.y, 840)
    }

    func testBestPanelOriginClampsToEdges() {
        let anchorRect = CGRect(x: 950, y: 500, width: 20, height: 20)
        let panelSize = CGSize(width: 260, height: 100)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 1000)

        let origin = controller.bestPanelOrigin(
            for: anchorRect,
            panelSize: panelSize,
            visibleFrame: visibleFrame,
            preferredEdge: .minY
        )

        // x should be clamped to visibleFrame.maxX - panelSize.width - 8
        // 1000 - 260 - 8 = 732
        XCTAssertEqual(origin.x, 732)
    }

    func testContextualSurfacePanelDoesNotUseRectangularWindowShadow() {
        let panel = controller.makePanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 60))

        XCTAssertFalse(panel.hasShadow)
    }

    func testSlashCommandPanelDoesNotUseRectangularWindowShadow() {
        let slashController = SlashCommandMenuController(
            onHoverIndex: { _ in },
            onSelectIndex: { _ in },
            onFrameUpdated: { _ in },
            onKeyboardAction: { _ in },
            onPassthroughKeyDown: { _ in }
        )

        let panel = slashController.makePanel(contentRect: CGRect(x: 0, y: 0, width: 260, height: 88))

        XCTAssertFalse(panel.hasShadow)
    }
}
