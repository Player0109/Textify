// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Textify",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TextifyCore", targets: ["TextifyCore"]),
        .library(name: "TextifyAudio", targets: ["TextifyAudio"]),
        .library(name: "TextifyTranscription", targets: ["TextifyTranscription"]),
        .library(name: "TextifyModels", targets: ["TextifyModels"]),
        .library(name: "TextifyInsertion", targets: ["TextifyInsertion"]),
        .library(name: "TextifyHotkeys", targets: ["TextifyHotkeys"]),
        .library(name: "TextifyDiagnostics", targets: ["TextifyDiagnostics"]),
        .library(name: "TextifySettings", targets: ["TextifySettings"]),
        .executable(name: "Textify", targets: ["Textify"])
    ],
    targets: [
        .target(name: "TextifyCore"),
        .target(name: "TextifyAudio"),
        .target(name: "TextifyTranscription", dependencies: ["TextifyCore"]),
        .target(name: "TextifyModels", dependencies: ["TextifyDiagnostics"]),
        .target(name: "TextifyInsertion", dependencies: ["TextifyCore", "TextifyDiagnostics"]),
        .target(name: "TextifyHotkeys", dependencies: ["TextifyCore", "TextifyDiagnostics"]),
        .target(name: "TextifyDiagnostics"),
        .target(name: "TextifySettings", dependencies: ["TextifyModels"]),
        .executableTarget(
            name: "Textify",
            dependencies: [
                "TextifyCore",
                "TextifyAudio",
                "TextifyTranscription",
                "TextifyModels",
                "TextifyInsertion",
                "TextifyHotkeys",
                "TextifyDiagnostics",
                "TextifySettings"
            ]
        ),
        .testTarget(name: "TextifyCoreTests", dependencies: ["TextifyCore"]),
        .testTarget(name: "TextifyAudioTests", dependencies: ["TextifyAudio"]),
        .testTarget(name: "TextifyTranscriptionTests", dependencies: ["TextifyTranscription"]),
        .testTarget(
            name: "TextifyModelsTests",
            dependencies: ["TextifyModels"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(name: "TextifyInsertionTests", dependencies: ["TextifyInsertion"]),
        .testTarget(name: "TextifyHotkeysTests", dependencies: ["TextifyHotkeys"]),
        .testTarget(name: "TextifyDiagnosticsTests", dependencies: ["TextifyDiagnostics"]),
        .testTarget(name: "TextifySettingsTests", dependencies: ["TextifySettings"])
    ]
)
