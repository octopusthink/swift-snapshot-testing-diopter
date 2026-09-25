# SnapshotTestingDiopter

A [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) diff tool that points failed snapshots at Diopter.

```swift
.package(url: "https://github.com/octopusthink/swift-snapshot-testing-diopter", from: "0.1.0"),
```

```swift
import SnapshotTestingDiopter
import Testing

@Suite(.serialized, .snapshots(diffTool: .diopter)) enum Snapshots {}
```

The trait applies to every suite nested inside `Snapshots`. When a snapshot fails, the failure message uses the `diopter` command to compare the reference image with the one that failed.
