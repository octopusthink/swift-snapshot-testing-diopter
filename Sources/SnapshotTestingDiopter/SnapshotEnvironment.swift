//
//  SnapshotEnvironment.swift
//  SnapshotTestingDiopter
//

import Foundation
import os

/**
 Where the images that failed a run are kept for Diopter to open.

 Each failure is copied into `failuresDirectory(for:)`, laid out as in
 `__Snapshots__/`, and the `__Snapshots__` directory it failed against is
 listed beside it, in `SnapshotFailures.references`. Once the tests are done
 Diopter is opened on each of those against the failures:

 - by the test process itself, as it exits, when it's on the Mac;
 - by the scheme's test post-action when it's on a simulator, which can't
   open anything on the Mac. The `install-diopter-post-action` plugin adds it.

 Either way the failures are then moved aside, to `SnapshotFailures-opened/`,
 so a later run that fails nothing doesn't open them again.
 */
public enum SnapshotEnvironment {
    /**
     Every image that failed this run: `build/SnapshotFailures/` at the top
     of the checkout `reference` is in (the nearest directory above it with a
     `.git`), where git ignores it.

     `nil` if `reference` isn't in a `__Snapshots__` directory.
     */
    public static func failuresDirectory(for reference: String) -> URL? {
        guard let snapshotsDirectory = snapshotsDirectory(of: reference) else { return nil }

        return checkoutDirectory(containing: snapshotsDirectory.deletingLastPathComponent())
            .appending(path: "build/SnapshotFailures", directoryHint: .isDirectory)
    }

    /// Copies the image that failed against `reference` into
    /// `failuresDirectory(for:)`, returning its path there—or where it was, if
    /// it couldn't be copied.
    public static func keepFailure(_ failed: String, of reference: String) -> String {
        guard
            let references = reference.range(of: "/__Snapshots__/"),
            let snapshotsDirectory = snapshotsDirectory(of: reference),
            let failuresDirectory = failuresDirectory(for: reference)
        else { return failed }

        let kept = failuresDirectory.appending(path: String(reference[references.upperBound...]))

        return state.withLock { state in
            do {
                try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: kept)
                try FileManager.default.copyItem(at: URL(filePath: failed), to: kept)
                try addReferences(snapshotsDirectory, to: failuresDirectory)
            } catch {
                return failed
            }

            #if os(macOS)
            if state.failuresDirectories.isEmpty, ProcessInfo.processInfo.environment["CI"] == nil {
                atexit { SnapshotEnvironment.openFailuresOnExit() }
            }
            state.failuresDirectories.insert(failuresDirectory)
            #endif

            return kept.path(percentEncoded: false)
        }
    }

    // MARK: - Opening failures

    /// The `__Snapshots__` directories the failures in `failuresDirectory`
    /// failed against, one per line.
    static func referencesFile(of failuresDirectory: URL) -> URL {
        failuresDirectory.deletingLastPathComponent()
            .appending(path: "\(failuresDirectory.lastPathComponent).references", directoryHint: .notDirectory)
    }

    // Only the Mac can open anything: a simulator leaves its failures to the
    // scheme's post-action.
    #if os(macOS)
    /**
     Moves the failures in `failuresDirectory` aside and opens `diopter` on
     each `__Snapshots__` directory they failed against, comparing it with
     them. Mirrors the post-action the plugin installs.

     Doesn't wait for `diopter`: returns what it launched.
     */
    @discardableResult
    static func openFailures(in failuresDirectory: URL, with diopter: URL) throws -> [Process] {
        let manager = FileManager.default
        let references = referencesFile(of: failuresDirectory)

        guard manager.fileExists(atPath: failuresDirectory.path(percentEncoded: false)) else { return [] }

        let opened = failuresDirectory.deletingLastPathComponent()
            .appending(path: "\(failuresDirectory.lastPathComponent)-opened", directoryHint: .isDirectory)
        let openedReferences = referencesFile(of: opened)

        try? manager.removeItem(at: opened)
        try? manager.removeItem(at: openedReferences)
        try manager.moveItem(at: failuresDirectory, to: opened)
        try manager.moveItem(at: references, to: openedReferences)

        return try String(contentsOf: openedReferences, encoding: .utf8)
            .split(separator: "\n")
            .map { snapshotsDirectory in
                let process = Process()
                process.executableURL = diopter
                process.arguments = [String(snapshotsDirectory), path(of: opened)]
                try process.run()

                return process
            }
    }

    /// `diopter` on the `PATH`, or where it's usually installed: Xcode doesn't
    /// read your shell profile, so its `PATH` often doesn't have it.
    static func findDiopter() -> URL? {
        let path = ProcessInfo.processInfo.environment["PATH", default: ""].split(separator: ":").map(String.init)
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let usual = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/Applications/Diopter.app/Contents/Resources",
            "\(home)/Applications/Diopter.app/Contents/Resources",
        ]

        return (path + usual)
            .map { URL(filePath: $0, directoryHint: .isDirectory).appending(path: "diopter") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    private static func openFailuresOnExit() {
        guard let diopter = findDiopter() else { return }

        for failuresDirectory in state.withLock({ $0.failuresDirectories }) {
            _ = try? openFailures(in: failuresDirectory, with: diopter)
        }
    }
    #endif

    // MARK: - Bookkeeping

    private struct State: Sendable {
        /// Every directory a failure was kept in this run, to open on exit.
        var failuresDirectories: Set<URL> = []
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    private static func addReferences(_ snapshotsDirectory: URL, to failuresDirectory: URL) throws {
        let references = referencesFile(of: failuresDirectory)
        let line = path(of: snapshotsDirectory)
        let listed = (try? String(contentsOf: references, encoding: .utf8)) ?? ""

        guard !listed.split(separator: "\n").contains(Substring(line)) else { return }

        try (listed + line + "\n").write(to: references, atomically: true, encoding: .utf8)
    }

    /// Without the trailing `/` a directory's has, as the shell would write it.
    private static func path(of url: URL) -> String {
        let path = url.path(percentEncoded: false)

        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// `…/__Snapshots__`, from the path of a reference in it.
    static func snapshotsDirectory(of reference: String) -> URL? {
        guard let references = reference.range(of: "/__Snapshots__/") else { return nil }

        return URL(filePath: String(reference[..<references.lowerBound]), directoryHint: .isDirectory)
            .appending(path: "__Snapshots__", directoryHint: .isDirectory)
    }

    /// The nearest directory at or above `directory` with a `.git` in it—or,
    /// if there isn't one, the one `directory` is in.
    static func checkoutDirectory(containing directory: URL) -> URL {
        var candidate = directory.standardizedFileURL

        while candidate.path(percentEncoded: false) != "/" {
            if FileManager.default.fileExists(atPath: candidate.appending(path: ".git").path(percentEncoded: false)) {
                return candidate
            }

            candidate = candidate.deletingLastPathComponent()
        }

        return directory.deletingLastPathComponent()
    }
}
