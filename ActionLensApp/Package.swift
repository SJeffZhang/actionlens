// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ActionLensApp",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .executableTarget(
            name: "ActionLensApp",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]),
            ]
        ),
    ]
)
