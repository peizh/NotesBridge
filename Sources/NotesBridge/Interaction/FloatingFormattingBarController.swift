import AppKit
import SwiftUI

@MainActor
final class FloatingFormattingBarController: ContextualSurfaceController {
    private let executor: FormattingCommandExecutor

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

        let rootView = FormattingBarView(commands: commands, localization: localization) { [weak self] command in
            self?.executor.perform(command)
            self?.hide()
        }

        let size = FormattingBarLayout.preferredSize(for: commands)
        update(rootView: rootView, anchorRect: selectionContext.selectionRect, size: size, preferredEdge: .maxY)
    }
}
