//
//  DiopterTests.swift
//  SnapshotTestingDiopterTests
//

import Foundation
@testable import SnapshotTestingDiopter
import Testing

// What the README promises compiles.
@Suite(.serialized, .snapshots(diffTool: .diopter)) enum Snapshots {}

struct DiopterTests {
    /// A throwaway checkout: `<root>/.git`, and a failed image outside it.
    let root: URL
    let failed: URL

    var failures: URL { root.appending(path: "build/SnapshotFailures", directoryHint: .isDirectory).standardizedFileURL }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)

        failed = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try Data("failed".utf8).write(to: failed)
    }

    func reference(_ path: String) -> String {
        root.appending(path: path).path(percentEncoded: false)
    }

    @Test func keepsTheFailureAtTheTopOfTheCheckout() throws {
        let kept = SnapshotEnvironment.keepFailure(failed.path(percentEncoded: false), of: reference("AppTests/Screens/__Snapshots__/HomeTests/home.1.png"))

        #expect(URL(filePath: kept).standardizedFileURL == failures.appending(path: "HomeTests/home.1.png"))
        #expect(try Data(contentsOf: URL(filePath: kept)) == Data("failed".utf8))
    }

    @Test func listsEachSnapshotsDirectoryOnce() throws {
        for path in ["AppTests/__Snapshots__/A/a.png", "AppTests/__Snapshots__/A/b.png", "AppTests/Screens/__Snapshots__/B/c.png"] {
            _ = SnapshotEnvironment.keepFailure(failed.path(percentEncoded: false), of: reference(path))
        }

        let listed = try String(contentsOf: SnapshotEnvironment.referencesFile(of: failures), encoding: .utf8)

        #expect(listed == """
            \(reference("AppTests/__Snapshots__"))
            \(reference("AppTests/Screens/__Snapshots__"))

            """)
    }

    @Test func commandComparesTheReferenceWithTheKeptFailure() {
        let reference = reference("AppTests/__Snapshots__/HomeTests/home.1.png")
        let kept = failures.appending(path: "HomeTests/home.1.png").path(percentEncoded: false)

        let command = SnapshotTestingConfiguration.DiffTool.diopter(currentFilePath: reference, failedFilePath: failed.path(percentEncoded: false))

        #expect(command == "diopter \"\(reference)\" \"\(kept)\"")
    }

    @Test func leavesAFailureOutsideSnapshotsWhereItIs() {
        #expect(SnapshotEnvironment.keepFailure(failed.path(percentEncoded: false), of: reference("reference.png")) == failed.path(percentEncoded: false))
    }

    #if os(macOS)
    @Test func opensEachSnapshotsDirectoryAgainstTheFailuresMovedAside() throws {
        _ = SnapshotEnvironment.keepFailure(failed.path(percentEncoded: false), of: reference("AppTests/__Snapshots__/A/a.png"))

        // Writes what it was run with, one line per argument.
        let log = root.appending(path: "diopter.log")
        let diopter = root.appending(path: "diopter")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" >> '\(log.path(percentEncoded: false))'\n".write(to: diopter, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: diopter.path(percentEncoded: false))

        for process in try SnapshotEnvironment.openFailures(in: failures, with: diopter) {
            process.waitUntilExit()
        }

        let opened = root.appending(path: "build/SnapshotFailures-opened").standardizedFileURL

        #expect(try String(contentsOf: log, encoding: .utf8) == """
            \(reference("AppTests/__Snapshots__"))
            \(opened.path(percentEncoded: false).dropLast())

            """)
        #expect(!FileManager.default.fileExists(atPath: failures.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: opened.appending(path: "A/a.png").path(percentEncoded: false)))
        #expect(try SnapshotEnvironment.openFailures(in: failures, with: diopter).isEmpty)
    }
    #endif
}
