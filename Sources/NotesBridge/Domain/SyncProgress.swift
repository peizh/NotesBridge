struct SyncProgress: Equatable, Sendable {
    var completedNotes: Int
    var totalNotes: Int
    var completedFolders: Int
    var totalFolders: Int
    var currentFolderName: String?
    var skippedNotes: Int

    var fractionCompleted: Double {
        guard totalNotes > 0 else { return 1 }
        let fraction = Double(completedNotes) / Double(totalNotes)
        return max(0, min(1, fraction))
    }

    var percentageText: String {
        "\(Int((fractionCompleted * 100).rounded()))%"
    }

    var summaryText: String {
        "\(percentageText) • \(completedNotes)/\(totalNotes) notes • \(completedFolders)/\(totalFolders) folders"
    }

    var currentFolderText: String? {
        guard let currentFolderName, !currentFolderName.isEmpty else { return nil }
        return "Current folder: \(currentFolderName)"
    }

    mutating func enterFolder(_ name: String) {
        currentFolderName = name
    }

    mutating func markProcessedNotes(_ count: Int = 1) {
        guard count > 0 else { return }
        completedNotes = min(totalNotes, completedNotes + count)
    }

    mutating func markSkippedNotes(_ count: Int) {
        guard count > 0 else { return }
        skippedNotes += count
        markProcessedNotes(count)
    }

    mutating func markCompletedFolder() {
        completedFolders = min(totalFolders, completedFolders + 1)
    }
}
