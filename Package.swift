// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "MMMCataphote",
    platforms: [
		.iOS(.v11),
        .watchOS(.v2),
        .tvOS(.v9),
        .macOS(.v10_10)
    ],
    products: [
        .library(
            name: "MMMCataphote",
            targets: ["MMMCataphote"]
		)
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MMMCataphote",
            dependencies: [],
            path: "Sources"
		),
        .testTarget(
            name: "MMMCataphoteTests",
            dependencies: ["MMMCataphote"],
            path: "Tests"
		)
    ]
)
