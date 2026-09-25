// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Textify",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "TextifyModelManifestVerifier",
            targets: ["TextifyModelManifestVerifier"]
        ),
        .executable(
            name: "TextifyModelRevocationVerifier",
            targets: ["TextifyModelRevocationVerifier"]
        )
    ],
    targets: [
        .target(name: "TextifyDiagnostics"),
        .target(name: "TextifyModels", dependencies: ["TextifyDiagnostics"]),
        .executableTarget(
            name: "TextifyModelManifestVerifier",
            dependencies: ["TextifyModels"]
        ),
        .executableTarget(
            name: "TextifyModelRevocationVerifier",
            dependencies: ["TextifyModels"]
        ),
        .testTarget(name: "TextifyDiagnosticsTests", dependencies: ["TextifyDiagnostics"]),
        .testTarget(
            name: "TextifyModelsTests",
            dependencies: ["TextifyModels"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
