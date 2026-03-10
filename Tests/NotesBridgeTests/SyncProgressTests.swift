import Testing
@testable import NotesBridge

struct SyncProgressTests {
    @Test
    func formatsProgressSummaryAndCurrentFolder() {
        let progress = SyncProgress(
            completedNotes: 2,
            totalNotes: 5,
            completedFolders: 1,
            totalFolders: 3,
            currentFolderName: "Journal",
            skippedNotes: 0
        )

        #expect(progress.fractionCompleted == 0.4)
        #expect(progress.percentageText == "40%")
        #expect(progress.summaryText == "40% • 2/5 notes • 1/3 folders")
        #expect(progress.currentFolderText == "Current folder: Journal")
    }

    @Test
    func zeroNoteSyncReportsComplete() {
        let progress = SyncProgress(
            completedNotes: 0,
            totalNotes: 0,
            completedFolders: 0,
            totalFolders: 0,
            currentFolderName: nil,
            skippedNotes: 0
        )

        #expect(progress.fractionCompleted == 1)
        #expect(progress.percentageText == "100%")
        #expect(progress.summaryText == "100% • 0/0 notes • 0/0 folders")
    }

    @Test
    func skippedNotesAdvanceCompletion() {
        var progress = SyncProgress(
            completedNotes: 1,
            totalNotes: 4,
            completedFolders: 0,
            totalFolders: 2,
            currentFolderName: "Inbox",
            skippedNotes: 0
        )

        progress.markSkippedNotes(2)

        #expect(progress.completedNotes == 3)
        #expect(progress.skippedNotes == 2)
        #expect(progress.fractionCompleted == 0.75)
    }

    @Test
    func progressClampsAtFinalBounds() {
        var progress = SyncProgress(
            completedNotes: 1,
            totalNotes: 2,
            completedFolders: 1,
            totalFolders: 2,
            currentFolderName: "Inbox",
            skippedNotes: 0
        )

        progress.markProcessedNotes(3)
        progress.markCompletedFolder()

        #expect(progress.completedNotes == 2)
        #expect(progress.completedFolders == 2)
        #expect(progress.fractionCompleted == 1)
        #expect(progress.percentageText == "100%")
    }
}
