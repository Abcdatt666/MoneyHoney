// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OutcomeCore",
    platforms: [
        .iOS("18.0"),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "OutcomeCore",
            targets: ["OutcomeCore"]
        ),
    ],
    targets: [
        .target(
            name: "OutcomeCore",
            path: "OutcomeCore"
        ),
        .testTarget(
            name: "OutcomeCoreTests",
            dependencies: ["OutcomeCore"],
            path: "OutcomeCoreTests"
        ),
    ]
)
