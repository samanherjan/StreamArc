// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StreamArcCore",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "StreamArcCore", targets: ["StreamArcCore"]),
    ],
    targets: [
        .target(
            name: "StreamArcCore",
            path: "Sources"
        ),
    ]
)
