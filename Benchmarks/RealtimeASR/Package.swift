// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TextifyRealtimeBenchmark",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../.."),
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.15.5"
        )
    ],
    targets: [
        .target(
            name: "BenchmarkMetrics"
        ),
        .executableTarget(
            name: "TextifyRealtimeBenchmark",
            dependencies: [
                "BenchmarkMetrics",
                .product(name: "TextifyCore", package: "Textify"),
                .product(name: "TextifyTranscription", package: "Textify"),
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        .executableTarget(
            name: "TextifyEvaluationTool",
            dependencies: ["BenchmarkMetrics"]
        ),
        .testTarget(
            name: "TextifyRealtimeBenchmarkTests",
            dependencies: ["BenchmarkMetrics", "TextifyRealtimeBenchmark"]
        )
    ]
)
