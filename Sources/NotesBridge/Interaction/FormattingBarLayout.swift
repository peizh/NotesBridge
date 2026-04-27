import CoreGraphics
import Foundation

enum FormattingBarLayout {
    enum CommandCluster {
        case typography
        case emphasis
        case lists
        case blocks
    }

    static let buttonSize: CGFloat = 34
    static let buttonSpacing: CGFloat = 5
    static let separatorSpacing: CGFloat = 10
    static let separatorWidth: CGFloat = 1
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let outerPadding: CGFloat = 2

    static let minimumWidth: CGFloat = 160
    static let maximumWidth: CGFloat = 464
    static let surfaceHeight: CGFloat = 56
    static let height: CGFloat = surfaceHeight + (outerPadding * 2)

    static let containerCornerRadius: CGFloat = 20
    static let buttonCornerRadius: CGFloat = 11

    static func groups(for commands: [FormattingCommand]) -> [[FormattingCommand]] {
        guard let first = commands.first else { return [] }

        var groups: [[FormattingCommand]] = [[first]]
        var lastCluster = cluster(for: first)

        for command in commands.dropFirst() {
            let currentCluster = cluster(for: command)
            if currentCluster == lastCluster {
                groups[groups.count - 1].append(command)
            } else {
                groups.append([command])
                lastCluster = currentCluster
            }
        }

        return groups
    }

    static func preferredSize(for commands: [FormattingCommand]) -> CGSize {
        let surfaceSize = surfaceSize(for: commands)
        return CGSize(
            width: surfaceSize.width + (outerPadding * 2),
            height: surfaceSize.height + (outerPadding * 2)
        )
    }

    static func surfaceSize(for commands: [FormattingCommand]) -> CGSize {
        let contentWidth = contentWidth(for: groups(for: commands))
        let width = min(
            max(contentWidth + (horizontalPadding * 2), minimumWidth - (outerPadding * 2)),
            maximumWidth - (outerPadding * 2)
        )
        return CGSize(width: width, height: surfaceHeight)
    }

    static func cluster(for command: FormattingCommand) -> CommandCluster {
        switch command {
        case .title, .heading, .subheading, .body:
            .typography
        case .bold, .strikethrough, .insertLink:
            .emphasis
        case .checklist, .bulletedList, .dashedList, .numberedList:
            .lists
        case .quote, .monostyled, .table:
            .blocks
        }
    }

    private static func contentWidth(for groups: [[FormattingCommand]]) -> CGFloat {
        guard !groups.isEmpty else { return minimumWidth }

        var width: CGFloat = 0

        for (groupIndex, group) in groups.enumerated() {
            width += CGFloat(group.count) * buttonSize
            if group.count > 1 {
                width += CGFloat(group.count - 1) * buttonSpacing
            }

            if groupIndex < groups.count - 1 {
                width += (separatorSpacing * 2) + separatorWidth
            }
        }

        return width
    }
}
