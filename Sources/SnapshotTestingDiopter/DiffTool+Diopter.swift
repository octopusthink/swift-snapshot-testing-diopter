//
//  DiffTool+Diopter.swift
//  SnapshotTestingDiopter
//

@_exported import SnapshotTesting

extension SnapshotTestingConfiguration.DiffTool {
    /**
     A `diopter` command for the failure, which is also kept for the scheme's
     test post-action to open (see `SnapshotEnvironment.failuresDirectory`).

     It's run on the Mac once the tests are done.
     */
    public static let diopter = Self { reference, failed in
        "diopter \"\(reference)\" \"\(SnapshotEnvironment.keepFailure(failed, of: reference))\""
    }
}
