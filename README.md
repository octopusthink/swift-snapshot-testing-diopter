# SnapshotTestingDiopter

A [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) diff tool that opens failed snapshots in Diopter.

```swift
.package(url: "https://github.com/octopusthink/swift-snapshot-testing-diopter", from: "1.0.0"),
```

```swift
import SnapshotTestingDiopter
import Testing

@Suite(.serialized, .snapshots(diffTool: .diopter)) enum Snapshots {}
```

## Opening failures after a run

For failed snapshots to open in Diopter after a test suite finishes, run the package's command plugin:

- **Xcode project:** in the Project navigator, right-click the project and choose **InstallDiopterPostAction**.
- **Package:**
  ```bash
  swift package --allow-writing-to-package-directory install-diopter-post-action
  ```

By default the plugin adds the post-action to every scheme that runs tests.
