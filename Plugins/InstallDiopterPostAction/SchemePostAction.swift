//
//  SchemePostAction.swift
//  InstallDiopterPostAction
//

import Foundation

/**
 The test post-action that opens a run's snapshot failures in Diopter, and how
 to add it to a scheme.

 Tests on a simulator can't open anything on the Mac, so they only keep their
 failures (see `SnapshotEnvironment` in the library); this opens them once the
 run is over. It mirrors `SnapshotEnvironment.openFailures(in:with:)`, which
 does the same from tests that run on the Mac—and moves the failures aside
 first, so this finds nothing left to open.

 The scheme is edited as text, not parsed and rewritten, so everything Xcode
 wrote stays exactly as it was.
 */
enum SchemePostAction {
    /// In the script, so a scheme it's already in can be told apart.
    static let marker = "SnapshotTestingDiopter"

    static let title = "Open snapshot failures in Diopter"

    static let script = """
        # Opens this run's snapshot failures in Diopter. Added by \(marker)'s install-diopter-post-action.
        checkout="$(git -C "$SRCROOT" rev-parse --show-toplevel 2>/dev/null)" || checkout="$SRCROOT"
        failures="$checkout/build/SnapshotFailures"
        [ -d "$failures" ] || exit 0
        # Xcode doesn't read your shell profile, so look where diopter's usually installed too.
        diopter="$(PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/Applications/Diopter.app/Contents/Resources:$HOME/Applications/Diopter.app/Contents/Resources" command -v diopter)" || {
          echo "\(marker): couldn't find diopter to open the failures in $failures." >&2
          exit 0
        }
        # Moved aside so a later run that fails nothing doesn't open them again.
        opened="$failures-opened"
        rm -rf "$opened" "$opened.references"
        mv "$failures" "$opened"
        mv "$failures.references" "$opened.references" || exit 0
        while IFS= read -r references; do
          "$diopter" "$references" "$opened"
        done < "$opened.references"

        """

    enum Outcome: Equatable {
        case installed(String)
        /// Had an earlier version of the script, which is replaced.
        case updated(String)
        case alreadyInstalled
        /// No `TestAction` with tests in it.
        case noTests
        /// No `BuildableReference` to take `$SRCROOT` from.
        case noBuildable
    }

    /// Whether the scheme runs any tests.
    static func hasTests(_ scheme: String) -> Bool {
        guard let testAction = testAction(in: scheme) else { return false }

        let body = scheme[testAction.body]

        return body.contains("<TestableReference") || body.contains("<TestPlanReference")
    }

    /// `scheme`, with the post-action added to its `TestAction`.
    static func install(in scheme: String) -> Outcome {
        guard hasTests(scheme), let testAction = testAction(in: scheme) else { return .noTests }
        if let installed = scheme[testAction.body].range(of: marker) {
            return update(in: scheme, at: installed.lowerBound)
        }

        guard let buildable = firstBuildableReference(in: scheme) else { return .noBuildable }

        let indent = indentation(ofLineAt: testAction.start, in: scheme)
        let unit = "   "
        let body = scheme[testAction.body]

        if let postActionsEnd = body.range(of: "</PostActions>") {
            // Before the line `</PostActions>` is on.
            let lineStart = scheme[..<postActionsEnd.lowerBound].lastIndex(of: "\n").map(scheme.index(after:)) ?? postActionsEnd.lowerBound
            let action = executionAction(buildable: buildable, indent: indent + unit + unit, unit: unit)

            return .installed(String(scheme[..<lineStart]) + action + String(scheme[lineStart...]))
        }

        // Where Xcode puts them: first thing in the `TestAction`, after any pre-actions.
        let insertion = body.range(of: "</PreActions>").map { scheme.index(after: scheme[$0.upperBound...].firstIndex(of: "\n") ?? $0.upperBound) }
            ?? scheme.index(after: scheme[testAction.body].firstIndex(of: "\n") ?? testAction.body.lowerBound)
        let postActions = """
            \(indent + unit)<PostActions>
            \(executionAction(buildable: buildable, indent: indent + unit + unit, unit: unit))\(indent + unit)</PostActions>

            """

        return .installed(String(scheme[..<insertion]) + postActions + String(scheme[insertion...]))
    }

    /// `scheme` with the script of the post-action whose `marker` is at
    /// `index` replaced by the current one.
    private static func update(in scheme: String, at index: String.Index) -> Outcome {
        // An escaped attribute holds no `"`, so it runs from the quote before
        // `index` to the next.
        guard
            let attribute = scheme[..<index].range(of: "scriptText = \"", options: .backwards),
            let end = scheme[index...].firstIndex(of: "\"")
        else { return .alreadyInstalled }

        let current = escaped(script)

        guard scheme[attribute.upperBound..<end] != current else { return .alreadyInstalled }

        return .updated(String(scheme[..<attribute.upperBound]) + current + String(scheme[end...]))
    }

    // MARK: - Building the action

    private static func executionAction(buildable: String, indent: String, unit: String) -> String {
        let content = indent + unit
        let environment = content + unit

        return """
            \(indent)<ExecutionAction
            \(indent)   ActionType = "Xcode.IDEStandardExecutionActionsCore.ExecutionActionType.ShellScriptAction">
            \(content)<ActionContent
            \(content)   title = "\(escaped(title))"
            \(content)   scriptText = "\(escaped(script))">
            \(environment)<EnvironmentBuildable>
            \(reindented(buildable, to: environment + unit))\(environment)</EnvironmentBuildable>
            \(content)</ActionContent>
            \(indent)</ExecutionAction>

            """
    }

    /// As Xcode writes an attribute.
    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "\n", with: "&#10;")
    }

    /// Each line of `block` moved to `indent`, keeping how far in it is
    /// relative to its first.
    private static func reindented(_ block: String, to indent: String) -> String {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
        let common = lines.filter { !$0.allSatisfy(\.isWhitespace) }.map { $0.prefix { $0 == " " }.count }.min() ?? 0

        return lines.map { indent + $0.dropFirst(common) + "\n" }.joined()
    }

    // MARK: - Finding things in a scheme

    private struct Element {
        /// Where `<TestAction` starts.
        let start: String.Index
        /// Between its opening tag's `>` and its closing tag.
        let body: Range<String.Index>
    }

    private static func testAction(in scheme: String) -> Element? {
        guard
            let open = scheme.range(of: "<TestAction"),
            let openEnd = scheme[open.upperBound...].firstIndex(of: ">"),
            scheme[scheme.index(before: openEnd)] != "/",
            let close = scheme[openEnd...].range(of: "</TestAction>")
        else { return nil }

        return Element(start: open.lowerBound, body: scheme.index(after: openEnd)..<close.lowerBound)
    }

    /// The first `<BuildableReference>…</BuildableReference>`—the scheme's
    /// own, in its `BuildAction`—with the indentation of its first line.
    private static func firstBuildableReference(in scheme: String) -> String? {
        guard
            let open = scheme.range(of: "<BuildableReference"),
            let close = scheme[open.upperBound...].range(of: "</BuildableReference>")
        else { return nil }

        return indentation(ofLineAt: open.lowerBound, in: scheme) + scheme[open.lowerBound..<close.upperBound]
    }

    private static func indentation(ofLineAt index: String.Index, in text: String) -> String {
        let lineStart = text[..<index].lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex

        return String(text[lineStart..<index].prefix { $0 == " " || $0 == "\t" })
    }

    // MARK: - Finding schemes

    /// Every scheme in the Xcode projects and workspaces in `directory`, or
    /// (for a package's `.swiftpm/xcode`) in `directory` itself, shared or not.
    static func schemes(in directory: URL) -> [URL] {
        let manager = FileManager.default

        func contents(of directory: URL, withExtension pathExtension: String) -> [URL] {
            ((try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == pathExtension }
        }

        let containers = [directory] + contents(of: directory, withExtension: "xcodeproj") + contents(of: directory, withExtension: "xcworkspace")

        return containers.flatMap { container in
            ([container.appending(path: "xcshareddata")] + contents(of: container.appending(path: "xcuserdata"), withExtension: "xcuserdatad"))
                .flatMap { contents(of: $0.appending(path: "xcschemes"), withExtension: "xcscheme") }
        }
        .sorted { $0.path < $1.path }
    }
}
