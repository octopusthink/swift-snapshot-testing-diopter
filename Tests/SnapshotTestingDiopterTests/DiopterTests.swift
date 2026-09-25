//
//  DiopterTests.swift
//  SnapshotTestingDiopterTests
//

import Foundation
import SnapshotTestingDiopter
import Testing

// What the README promises compiles.
@Suite(.serialized, .snapshots(diffTool: .diopter)) enum Snapshots {}

struct DiopterTests {
    /// A throwaway checkout: `<root>/.git`, and a failed image outside it.
    let root: URL
    let failed: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)

        failed = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try Data("failed".utf8).write(to: failed)
    }

    @Test func keepsTheFailureAtTheTopOfTheCheckout() throws {
        let reference = root.appending(path: "AppTests/Screens/__Snapshots__/HomeTests/home.1.png").path(percentEncoded: false)

        let kept = SnapshotEnvironment.keepFailure(failed.path(percentEncoded: false), of: reference)

        #expect(URL(filePath: kept).standardizedFileURL == root.appending(path: "build/SnapshotFailures/HomeTests/home.1.png").standardizedFileURL)
        #expect(try Data(contentsOf: URL(filePath: kept)) == Data("failed".utf8))
    }

    @Test func commandComparesTheReferenceWithTheKeptFailure() {
        let reference = root.appending(path: "AppTests/__Snapshots__/HomeTests/home.1.png").path(percentEncoded: false)
        let kept = root.appending(path: "build/SnapshotFailures/HomeTests/home.1.png").standardizedFileURL.path(percentEncoded: false)

        let command = SnapshotTestingConfiguration.DiffTool.diopter(currentFilePath: reference, failedFilePath: failed.path(percentEncoded: false))

        #expect(command == "diopter \"\(reference)\" \"\(kept)\"")
    }

    @Test func leavesAFailureOutsideSnapshotsWhereItIs() {
        let reference = root.appending(path: "reference.png").path(percentEncoded: false)

        #expect(SnapshotEnvironment.keepFailure(failed.path(percentEncoded: false), of: reference) == failed.path(percentEncoded: false))
    }
}
