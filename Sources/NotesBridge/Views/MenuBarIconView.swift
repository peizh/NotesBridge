import SwiftUI

struct MenuBarIconView: View {
    let symbolName: String
    let isSyncing: Bool
    let frameIndex: Int

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 15.5, weight: .regular))
            .frame(width: 22, height: 22)
            .rotationEffect(.degrees(isSyncing ? rotationDegrees : 0))
            .accessibilityLabel("NotesBridge")
    }

    private var rotationDegrees: Double {
        let frameCount = 12
        let normalizedFrame = ((frameIndex % frameCount) + frameCount) % frameCount
        return Double(normalizedFrame) * (360.0 / Double(frameCount))
    }
}
