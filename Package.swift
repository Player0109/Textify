// swift-tools-version: 5.9
import PackageDescription

let whisperDefines: [CSetting] = [
    .define("GGML_USE_CPU"),
    .define("GGML_USE_ACCELERATE"),
    .define("GGML_USE_METAL"),
    .define("GGML_SCHED_MAX_COPIES", to: "4"),
    .define("_DARWIN_C_SOURCE"),
    .headerSearchPath("include"),
    .headerSearchPath("src"),
    .headerSearchPath("ggml/include"),
    .headerSearchPath("ggml/src"),
    .headerSearchPath("ggml/src/ggml-cpu"),
    .headerSearchPath("ggml/src/ggml-metal")
]

let whisperCXXDefines: [CXXSetting] = [
    .define("GGML_USE_CPU"),
    .define("GGML_USE_ACCELERATE"),
    .define("GGML_USE_METAL"),
    .define("GGML_SCHED_MAX_COPIES", to: "4"),
    .define("_DARWIN_C_SOURCE"),
    .headerSearchPath("include"),
    .headerSearchPath("src"),
    .headerSearchPath("ggml/include"),
    .headerSearchPath("ggml/src"),
    .headerSearchPath("ggml/src/ggml-cpu"),
    .headerSearchPath("ggml/src/ggml-metal")
]

let nativeWarningSuppressions = [
    "-Wno-shorten-64-to-32",
    "-Wno-ambiguous-macro",
    "-Wno-unused-function",
    "-Wno-unused-variable",
    "-Wno-unused-parameter"
]

let whisperCSettings = whisperDefines + [
    .unsafeFlags(nativeWarningSuppressions, .when(platforms: [.macOS]))
]

let whisperCXXSettings = whisperCXXDefines + [
    .unsafeFlags(nativeWarningSuppressions, .when(platforms: [.macOS]))
]

let whisperShimCSettings: [CSetting] = [
    .define("GGML_USE_METAL"),
    .headerSearchPath("include")
]

let whisperShimCXXSettings: [CXXSetting] = [
    .define("GGML_USE_METAL"),
    .headerSearchPath("include")
]

let whisperLinkerSettings: [LinkerSetting] = [
    .linkedFramework("Accelerate", .when(platforms: [.macOS])),
    .linkedFramework("Metal", .when(platforms: [.macOS])),
    .linkedFramework("Foundation", .when(platforms: [.macOS])),
    .linkedLibrary("compression", .when(platforms: [.macOS])),
    .linkedLibrary("c++", .when(platforms: [.macOS]))
]

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
        .library(name: "TextifyRuntime", targets: ["TextifyRuntime"]),
        .library(
            name: "TextifyReleaseVerification",
            targets: ["TextifyReleaseVerification"]
        ),
        .library(name: "TextifyWhisperShim", targets: ["TextifyWhisperShim"]),
        .executable(
            name: "TextifyModelManifestVerifier",
            targets: ["TextifyModelManifestVerifier"]
        ),
        .executable(
            name: "TextifyCatalogPublicationVerifier",
            targets: ["TextifyCatalogPublicationVerifier"]
        ),
        .executable(
            name: "TextifyModelFaultVerifier",
            targets: ["TextifyModelFaultVerifier"]
        ),
        .executable(
            name: "TextifyReleaseEvidenceVerifier",
            targets: ["TextifyReleaseEvidenceVerifier"]
        ),
        .executable(name: "Textify", targets: ["Textify"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.15.5"
        ),
        .package(
            url: "https://github.com/ml-explore/mlx-swift.git",
            exact: "0.31.3"
        ),
        .package(
            url: "https://github.com/Blaizzy/mlx-audio-swift.git",
            revision: "d302a5c6080d2bb97bae38c7418f82abb76013b6"
        )
    ],
    targets: [
        .binaryTarget(
            name: "CLiteRTLM_mac",
            url: "https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.14.0/CLiteRTLM_mac.xcframework.zip",
            checksum: "450615483509aaa6d34b321fdc6862e41a224b674468ab10aff64ebe113d21b7"
        ),
        .target(
            name: "WhisperCppVendor",
            path: "Vendor/whisper.cpp",
            sources: [
                "src/whisper.cpp",
                "ggml/src/ggml.c",
                "ggml/src/ggml.cpp",
                "ggml/src/ggml-alloc.c",
                "ggml/src/ggml-backend.cpp",
                "ggml/src/ggml-backend-reg.cpp",
                "ggml/src/ggml-opt.cpp",
                "ggml/src/ggml-threading.cpp",
                "ggml/src/ggml-quants.c",
                "ggml/src/gguf.cpp",
                "ggml/src/ggml-cpu/ggml-cpu.c",
                "ggml/src/ggml-cpu/ggml-cpu.cpp",
                "ggml/src/ggml-cpu/binary-ops.cpp",
                "ggml/src/ggml-cpu/unary-ops.cpp",
                "ggml/src/ggml-cpu/ops.cpp",
                "ggml/src/ggml-cpu/vec.cpp",
                "ggml/src/ggml-cpu/traits.cpp",
                "ggml/src/ggml-cpu/quants.c",
                "ggml/src/ggml-cpu/repack.cpp",
                "ggml/src/ggml-cpu/hbm.cpp",
                "ggml/src/ggml-cpu/arch/arm/quants.c",
                "ggml/src/ggml-cpu/arch/arm/repack.cpp",
                "ggml/src/ggml-metal/ggml-metal.m"
            ],
            resources: [
                .process("ggml/src/ggml-metal/ggml-metal.metal")
            ],
            publicHeadersPath: "spm/include",
            cSettings: whisperCSettings,
            cxxSettings: whisperCXXSettings,
            linkerSettings: whisperLinkerSettings
        ),
        .target(
            name: "TextifyWhisperShim",
            dependencies: ["WhisperCppVendor"],
            path: "Sources/TextifyWhisperShim",
            publicHeadersPath: "include",
            cSettings: whisperShimCSettings,
            cxxSettings: whisperShimCXXSettings,
            linkerSettings: whisperLinkerSettings
        ),
        .target(
            name: "TextifySherpaShim",
            path: "Sources/TextifySherpaShim",
            publicHeadersPath: "include"
        ),
        .target(
            name: "TextifyTranscribeCppShim",
            path: "Sources/TextifyTranscribeCppShim",
            publicHeadersPath: "include"
        ),
        .target(name: "TextifyCore"),
        .target(name: "TextifyAudio"),
        .target(
            name: "TextifyTranscription",
            dependencies: [
                "TextifyCore",
                "TextifyWhisperShim",
                "TextifySherpaShim",
                "TextifyTranscribeCppShim",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioSTS", package: "mlx-audio-swift"),
                .target(name: "CLiteRTLM_mac", condition: .when(platforms: [.macOS]))
            ]
        ),
        .target(name: "TextifyModels", dependencies: ["TextifyDiagnostics"]),
        .target(name: "TextifyInsertion", dependencies: ["TextifyCore", "TextifyDiagnostics"]),
        .target(name: "TextifyHotkeys", dependencies: ["TextifyCore", "TextifyDiagnostics"]),
        .target(name: "TextifyDiagnostics"),
        .target(name: "TextifySettings", dependencies: ["TextifyModels"]),
        .target(
            name: "TextifyReleaseVerification",
            dependencies: ["TextifyModels", "TextifyDiagnostics"]
        ),
        .executableTarget(
            name: "TextifyModelManifestVerifier",
            dependencies: ["TextifyModels"]
        ),
        .executableTarget(
            name: "TextifyCatalogPublicationVerifier",
            dependencies: ["TextifyModels"]
        ),
        .executableTarget(
            name: "TextifyModelFaultVerifier",
            dependencies: ["TextifyReleaseVerification"]
        ),
        .executableTarget(
            name: "TextifyReleaseEvidenceVerifier",
            dependencies: ["TextifyReleaseVerification"]
        ),
        .target(
            name: "TextifyRuntime",
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
                "TextifySettings",
                "TextifyRuntime"
            ]
        ),
        .testTarget(name: "TextifyCoreTests", dependencies: ["TextifyCore"]),
        .testTarget(name: "TextifyAudioTests", dependencies: ["TextifyAudio"]),
        .testTarget(name: "TextifyTranscriptionTests", dependencies: ["TextifyTranscription", "TextifyWhisperShim"]),
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
        .testTarget(name: "TextifySettingsTests", dependencies: ["TextifySettings"]),
        .testTarget(name: "TextifyRuntimeTests", dependencies: ["TextifyRuntime"]),
        .testTarget(
            name: "TextifyReleaseVerificationTests",
            dependencies: ["TextifyReleaseVerification"]
        ),
        .testTarget(
            name: "TextifyAppTests",
            dependencies: [
                "Textify",
                "TextifyAudio",
                "TextifyDiagnostics",
                "TextifyHotkeys",
                "TextifyInsertion",
                "TextifyModels",
                "TextifyRuntime",
                "TextifySettings",
                "TextifyTranscription"
            ]
        )
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx17
)
