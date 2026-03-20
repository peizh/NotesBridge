import SwiftUI

enum NotesBridgeGlassStyle {
    static let cardCornerRadius: CGFloat = 16
    static let compactCardCornerRadius: CGFloat = 14
    static let borderOpacity: CGFloat = 0.26
    static let shadowRadius: CGFloat = 16
    static let shadowYOffset: CGFloat = 8
}

extension View {
    func notesBridgeGlassCard(cornerRadius: CGFloat = NotesBridgeGlassStyle.cardCornerRadius) -> some View {
        self
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(NotesBridgeGlassStyle.borderOpacity),
                        lineWidth: 0.8
                    )
            }
            .shadow(
                color: Color.black.opacity(0.12),
                radius: NotesBridgeGlassStyle.shadowRadius,
                x: 0,
                y: NotesBridgeGlassStyle.shadowYOffset
            )
    }
}
