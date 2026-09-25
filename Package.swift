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
        .testTarget(
            name: "SnapshotTestingDiopterTests",
            dependencies: ["SnapshotTestingDiopter"]
        ),
    ]
)
