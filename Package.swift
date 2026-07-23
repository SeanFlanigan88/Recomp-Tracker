// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RecompCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "RecompCore",
            targets: ["RecompCore"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            .upToNextMajor(from: "6.0.0")
        ),
    ],
    targets: [
        .target(
            name: "RecompCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "shared/Sources/RecompCore"
        ),
        .testTarget(
            name: "RecompCoreTests",
            dependencies: ["RecompCore"],
            path: "shared/Tests/RecompCoreTests"
        ),
    ]
)
