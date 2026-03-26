import AppKit
import SwiftUI

struct MenuBarIconView: View {
    let symbolName: String
    let isSyncing: Bool
    let frameIndex: Int

    var body: some View {
        renderedImage
            .renderingMode(.template)
            .accessibilityLabel("NotesBridge")
    }

    private var renderedImage: Image {
        Image(
            nsImage: MenuBarImageCache.shared.image(
                symbolName: symbolName,
                frameIndex: isSyncing ? frameIndex : 0,
                isSyncing: isSyncing
            )
        )
    }
}

@MainActor
private final class MenuBarImageCache {
    static let shared = MenuBarImageCache()

    private let frameCount = 12
    private let iconSize = NSSize(width: 22, height: 22)
    private var cache: [String: NSImage] = [:]

    func image(symbolName: String, frameIndex: Int, isSyncing: Bool) -> NSImage {
        let normalizedFrame = isSyncing ? (((frameIndex % frameCount) + frameCount) % frameCount) : 0
        let cacheKey = "\(symbolName)-\(normalizedFrame)-\(isSyncing)"

        if let cachedImage = cache[cacheKey] {
            return cachedImage
        }

        let image = makeImage(symbolName: symbolName, frameIndex: normalizedFrame, isSyncing: isSyncing)
        cache[cacheKey] = image
        return image
    }

    private func makeImage(symbolName: String, frameIndex: Int, isSyncing: Bool) -> NSImage {
        // Point size 15.5 is often better for complex symbols to maintain padding
        let configuration = NSImage.SymbolConfiguration(pointSize: 15.5, weight: .regular)
        guard let baseImage = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "NotesBridge"
        )?.withSymbolConfiguration(configuration) else {
            return NSImage(size: iconSize)
        }

        let image = NSImage(size: iconSize)
        image.lockFocus()

        if isSyncing {
            let center = NSPoint(x: iconSize.width / 2, y: iconSize.height / 2)
            let rotation = NSAffineTransform()
            rotation.translateX(by: center.x, yBy: center.y)
            rotation.rotate(byDegrees: CGFloat(Double(frameIndex) * (360.0 / Double(frameCount))))
            rotation.translateX(by: -center.x, yBy: -center.y)
            rotation.concat()
        }

        // Visual adjustment: Shift down slightly (-1.0) to achieve visual vertical centering
        let visualYOffset: CGFloat = -1.0
        let drawRect = NSRect(
            x: (iconSize.width - baseImage.size.width) / 2,
            y: (iconSize.height - baseImage.size.height) / 2 + visualYOffset,
            width: baseImage.size.width,
            height: baseImage.size.height
        )

        baseImage.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: baseImage.size),
            operation: .sourceOver,
            fraction: 1
        )
        
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
