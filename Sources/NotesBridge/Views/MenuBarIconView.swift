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
        if isSyncing {
            return Image(
                nsImage: RotatingMenuBarImageCache.shared.image(
                    symbolName: symbolName,
                    frameIndex: frameIndex
                )
            )
        }

        return Image(systemName: symbolName)
    }
}

@MainActor
private final class RotatingMenuBarImageCache {
    static let shared = RotatingMenuBarImageCache()

    private let frameCount = 12
    private let iconSize = NSSize(width: 18, height: 18)
    private var cache: [String: NSImage] = [:]

    func image(symbolName: String, frameIndex: Int) -> NSImage {
        let normalizedFrame = ((frameIndex % frameCount) + frameCount) % frameCount
        let cacheKey = "\(symbolName)-\(normalizedFrame)"

        if let cachedImage = cache[cacheKey] {
            return cachedImage
        }

        let image = makeImage(symbolName: symbolName, frameIndex: normalizedFrame)
        cache[cacheKey] = image
        return image
    }

    private func makeImage(symbolName: String, frameIndex: Int) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        guard let baseImage = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "NotesBridge"
        )?.withSymbolConfiguration(configuration) else {
            return NSImage(size: iconSize)
        }

        let image = NSImage(size: iconSize)
        image.lockFocus()

        let center = NSPoint(x: iconSize.width / 2, y: iconSize.height / 2)
        let rotation = NSAffineTransform()
        rotation.translateX(by: center.x, yBy: center.y)
        rotation.rotate(byDegrees: CGFloat(Double(frameIndex) * (360.0 / Double(frameCount))))
        rotation.translateX(by: -center.x, yBy: -center.y)
        rotation.concat()

        baseImage.draw(
            in: NSRect(origin: .zero, size: iconSize),
            from: NSRect(origin: .zero, size: baseImage.size),
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
