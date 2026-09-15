// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PuraMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PuraMac", targets: ["PuraMacApp"]),
        .library(name: "PuraMacCore", targets: ["PuraMacCore"])
    ],
    targets: [
        .target(
            name: "PuraMacCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "PuraMacApp",
            dependencies: ["PuraMacCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PuraMacCoreTests",
            dependencies: ["PuraMacCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
