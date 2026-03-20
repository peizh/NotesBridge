import SwiftUI

enum FloatingToolPaletteStyle {
    static let iconSize: CGFloat = 26
    static let iconCornerRadius: CGFloat = 8
    static let iconFontSize: CGFloat = 15

    static let containerCornerRadius: CGFloat = 14
    static let rowCornerRadius: CGFloat = 8

    static let containerHorizontalPadding: CGFloat = 7
    static let containerVerticalPadding: CGFloat = 5
    static let outerPadding: CGFloat = 2

    static let rowHorizontalPadding: CGFloat = 7
    static let rowVerticalPadding: CGFloat = 5
    static let rowSpacing: CGFloat = 6
    static let rowSelectionOpacity: CGFloat = 0.15
}

struct FloatingToolPaletteIcon: View {
    let systemImage: String
    var foregroundStyle: AnyShapeStyle = AnyShapeStyle(.primary)

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: FloatingToolPaletteStyle.iconFontSize, weight: .semibold))
            .foregroundStyle(foregroundStyle)
            .frame(width: FloatingToolPaletteStyle.iconSize, height: FloatingToolPaletteStyle.iconSize)
            .contentShape(RoundedRectangle(cornerRadius: FloatingToolPaletteStyle.iconCornerRadius, style: .continuous))
    }
}

extension View {
    func floatingToolPaletteContainer() -> some View {
        self
            .padding(.horizontal, FloatingToolPaletteStyle.containerHorizontalPadding)
            .padding(.vertical, FloatingToolPaletteStyle.containerVerticalPadding)
            .notesBridgeGlassCard(cornerRadius: FloatingToolPaletteStyle.containerCornerRadius)
            .padding(FloatingToolPaletteStyle.outerPadding)
    }
}
