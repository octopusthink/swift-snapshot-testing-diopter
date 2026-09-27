//
//  InstallDiopterPostAction.swift
//  InstallDiopterPostAction
//

import Foundation
import PackagePlugin

/**
 Adds the test post-action that opens a run's snapshot failures in Diopter
 (see `SchemePostAction`) to an Xcode project's schemes: every scheme with
 tests, or only those named with `--scheme`. A scheme that has it already is
 left alone.
 */
@main
struct InstallDiopterPostAction: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // A package's tests run on the Mac from `swift test`, where they open
        // their own failures. Its schemes, if Xcode has written any, live here.
        try install(in: context.package.directoryURL.appending(path: ".swiftpm/xcode"), arguments: arguments)
    }

    func install(in directory: URL, arguments: [String]) throws {
        var arguments = ArgumentExtractor(arguments)
        let named = Set(arguments.extractOption(named: "scheme"))

        let schemes = SchemePostAction.schemes(in: directory)
            .filter { named.isEmpty || named.contains($0.deletingPathExtension().lastPathComponent) }

        guard !schemes.isEmpty else {
            Diagnostics.error(named.isEmpty ? "No schemes found in \(directory.path(percentEncoded: false))." : "No scheme named \(named.sorted().joined(separator: ", ")).")
            return
        }

        for url in schemes {
            let name = url.deletingPathExtension().lastPathComponent
            let scheme = try String(contentsOf: url, encoding: .utf8)

            switch SchemePostAction.install(in: scheme) {
            case .installed(let updated):
                try updated.write(to: url, atomically: true, encoding: .utf8)
                print("\(name): added the test post-action that opens snapshot failures in Diopter.")
            case .alreadyInstalled:
                print("\(name): already opens snapshot failures in Diopter.")
            case .noTests where named.isEmpty:
                continue
            case .noTests:
                Diagnostics.warning("\(name): runs no tests, so it has nothing to open.")
            case .noBuildable:
                Diagnostics.warning("\(name): builds nothing to take $SRCROOT from, so it can't be given the post-action.")
            }
        }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension InstallDiopterPostAction: XcodeCommandPlugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        try install(in: context.xcodeProject.directoryURL, arguments: arguments)
    }
}
#endif
