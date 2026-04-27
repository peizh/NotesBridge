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

    static let surfaceHorizontalPadding: CGFloat = 8
    static let jitterTolerance: CGFloat = 0.5
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
            .background(
                .thinMaterial,
                in: RoundedRectangle(
                    cornerRadius: FloatingToolPaletteStyle.containerCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: FloatingToolPaletteStyle.containerCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    Color.white.opacity(NotesBridgeGlassStyle.borderOpacity),
                    lineWidth: 0.8
                )
            }
            .padding(FloatingToolPaletteStyle.outerPadding)
    }
}
