// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SnapshotTestingDiopter",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "SnapshotTestingDiopter", targets: ["SnapshotTestingDiopter"]),
        .plugin(name: "InstallDiopterPostAction", targets: ["InstallDiopterPostAction"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.0"),
    ],
    targets: [
        .target(
            name: "SnapshotTestingDiopter",
            dependencies: [
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
        .plugin(
            name: "InstallDiopterPostAction",
            capability: .command(
                intent: .custom(
                    verb: "install-diopter-post-action",
                    description: "Adds a test post-action to your schemes that opens each run's snapshot failures in Diopter."
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "Adds a test post-action to your schemes that opens each run's snapshot failures in Diopter."),
                ]
            )
        ),
        .testTarget(
            name: "SnapshotTestingDiopterTests",
            dependencies: ["SnapshotTestingDiopter"]
        ),
    ]
)
