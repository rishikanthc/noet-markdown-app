// swift-tools-version: 6.0

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .path

let package = Package(
    name: "MarkdownLabCLI",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "MarkdownLab", targets: ["MarkdownLab"]),
    ],
    targets: [
        .target(
            name: "CMdCore",
            path: "Sources/CMdCore",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MarkdownLabSupport",
            path: "Sources/MarkdownLabSupport"
        ),
        .executableTarget(
            name: "MarkdownLab",
            dependencies: ["CMdCore", "MarkdownLabSupport"],
            path: "Sources/MarkdownLab",
            linkerSettings: [
                .linkedFramework("AppKit", .when(platforms: [.macOS])),
                .unsafeFlags(
                    ["-L\(packageRoot)/.build/mdcore/lib"],
                    .when(platforms: [.macOS])
                ),
                .linkedLibrary("MdCore", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "MarkdownLabTests",
            dependencies: [
                "MarkdownLabSupport",
                .target(name: "MarkdownLab", condition: .when(platforms: [.macOS])),
            ],
            path: "Tests/MarkdownLabTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
