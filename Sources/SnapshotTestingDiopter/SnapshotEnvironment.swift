//
//  SnapshotEnvironment.swift
//  SnapshotTestingDiopter
//

import Foundation

/**
 Where the images that failed a run are kept for Diopter to open.

 The tests can't run `diopter` themselves when they're on a simulator, so each
 failure is copied into `failuresDirectory`, laid out as in `__Snapshots__/`,
 for the scheme's test post-action to open once they're done.
 */
public enum SnapshotEnvironment {
    /// Set in the test scheme's environment to keep failures somewhere other
    /// than `build/SnapshotFailures/` at the top of the checkout.
    public static let failuresDirectoryKey = "SNAPSHOT_FAILURES_DIRECTORY"

    /**
     Every image that failed this run, for the scheme's test post-action to
     open in Diopter: `SNAPSHOT_FAILURES_DIRECTORY` if it's set, or
     `build/SnapshotFailures/` at the top of the checkout `reference` is in
     (the nearest directory above it with a `.git`), where git ignores it.

     `nil` if `reference` isn't in a `__Snapshots__` directory.
     */
    public static func failuresDirectory(for reference: String) -> URL? {
        if let directory = ProcessInfo.processInfo.environment[failuresDirectoryKey], !directory.isEmpty {
            return URL(filePath: directory, directoryHint: .isDirectory)
        }

        guard let references = reference.range(of: "/__Snapshots__/") else { return nil }

        // The directory the tests are in.
        let testsDirectory = URL(filePath: String(reference[..<references.lowerBound]), directoryHint: .isDirectory)

        return checkoutDirectory(containing: testsDirectory)
            .appending(path: "build/SnapshotFailures", directoryHint: .isDirectory)
    }

    /// Copies the image that failed against `reference` into
    /// `failuresDirectory(for:)`, returning its path there—or where it was, if
    /// it couldn't be copied.
    public static func keepFailure(_ failed: String, of reference: String) -> String {
        guard
            let references = reference.range(of: "/__Snapshots__/"),
            let failuresDirectory = failuresDirectory(for: reference)
        else { return failed }

        let kept = failuresDirectory.appending(path: String(reference[references.upperBound...]))

        do {
            try FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: kept)
            try FileManager.default.copyItem(at: URL(filePath: failed), to: kept)

            return kept.path(percentEncoded: false)
        } catch {
            return failed
        }
    }

    /// The nearest directory at or above `directory` with a `.git` in it
    /// If there isn't one, the one `directory` is in.
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
