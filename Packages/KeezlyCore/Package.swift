// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeezlyCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // Pure game model + rules + AI. Contains NO SwiftUI, NO GameKit,
        // NO persistence framework. See docs/ARCHITECTURE.md.
        .library(name: "KeezlyCore", targets: ["KeezlyCore"]),
    ],
    targets: [
        .target(
            name: "KeezlyCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "KeezlyCoreTests",
            dependencies: ["KeezlyCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
