import Foundation
import TextifyModels

enum ModelCatalogVariantComparisonMetric: Equatable {
    case reference(label: String)
    case compared(label: String, scoreDelta: Int)
    case unrated
    case noBaseline
    case notComparable

    var title: String {
        switch self {
        case let .reference(label), let .compared(label, _):
            label
        case .unrated:
            "Unrated"
        case .noBaseline:
            "No Baseline"
        case .notComparable:
            "Not Comparable"
        }
    }

    var detail: String? {
        switch self {
        case .reference:
            "Reference"
        case let .compared(_, scoreDelta):
            if scoreDelta == 0 {
                "Same score as reference"
            } else if scoreDelta > 0 {
                "+\(scoreDelta) vs reference"
            } else {
                "\(scoreDelta) vs reference"
            }
        case .noBaseline:
            "Reference is Unrated"
        case .unrated, .notComparable:
            nil
        }
    }
}

enum ModelCatalogVariantPrimaryAction: Equatable {
    case use
    case disable
    case install
    case reinstall
    case cancelInstall
    case retryInstall
    case none
}

struct ModelCatalogVariantComparisonPresentation: Equatable, Identifiable {
    let id: String
    let variant: String
    let isRecommended: Bool
    let isFallback: Bool
    let artifactFormat: String
    let numericFormat: String
    let runtime: String
    let quality: ModelCatalogVariantComparisonMetric
    let speed: ModelCatalogVariantComparisonMetric
    let sizeLabel: String
    let size: String
    let computeRoute: String
    let state: String
    let compatibilityExplanation: String
    let isActionable: Bool
    let isActive: Bool
    let primaryAction: ModelCatalogVariantPrimaryAction
}

enum ModelCatalogVariantComparisonColumn: Equatable, Hashable {
    case artifactFormat
    case numericFormat
    case quality
    case speed
    case size
    case computeRoute
    case state
}

enum ModelCatalogVariantComparisonLayout: Equatable {
    case wide
    case medium
    case narrow

    static let wideMinimumWidth: CGFloat = 980
    static let mediumMinimumWidth: CGFloat = 680

    var showsInlineState: Bool {
        switch self {
        case .wide, .medium:
            true
        case .narrow:
            false
        }
    }

    var labeledFields: [ModelCatalogVariantComparisonColumn] {
        switch self {
        case .wide:
            []
        case .medium:
            [
                .artifactFormat,
                .numericFormat,
                .quality,
                .speed,
                .size,
                .computeRoute,
            ]
        case .narrow:
            [
                .artifactFormat,
                .numericFormat,
                .quality,
                .speed,
                .size,
                .computeRoute,
                .state,
            ]
        }
    }
}

enum ModelCatalogVariantTerminology {
    static let artifactFormatExplanation =
        "Artifact Format describes packaging model files for a compatible runtime."
    static let numericFormatExplanation =
        "Numeric Format is the exact signed code for the model’s weight representation."
    static let tradeoffExplanation =
        "Numeric representation can affect storage, memory, speed, and accuracy. "
        + "Textify compares signed results only when their evidence groups match."

    static func artifactFormat(_ format: ModelArtifactContainerFormat) -> String {
        switch format {
        case .ggml:
            "GGML"
        case .gguf:
            "GGUF"
        case .mlx:
            "MLX"
        case .coreML:
            "Core ML"
        case .onnx:
            "ONNX"
        }
    }

    static func runtime(_ runtime: TranscriptionEngine) -> String {
        switch runtime {
        case .whisperCpp:
            "Whisper.cpp"
        case .fluidAudioParakeet:
            "FluidAudio Parakeet"
        case .fluidAudioParaformer:
            "FluidAudio Paraformer"
        case .sherpaOnnx:
            "sherpa-onnx"
        case .transcribeCpp:
            "transcribe.cpp"
        case .mlxAudio:
            "MLX Audio"
        case .liteRTLM:
            "LiteRT-LM"
        }
    }

    static func computeRoute(_ route: ModelComputeRoute) -> String {
        switch route {
        case .gpuViaMetal:
            "GPU via Metal"
        case .coreMLNeuralEngine:
            "Core ML / Neural Engine"
        case .cpuOnly:
            "CPU only"
        }
    }
}

extension ModelCatalogCheckpointPresentation {
    var variantComparisons: [ModelCatalogVariantComparisonPresentation] {
        guard let reference = referenceArtifact else {
            return []
        }

        return artifacts.map { artifact in
            ModelCatalogVariantComparisonPresentation(
                id: artifact.id,
                variant: artifact.metadata.presentation.displayName,
                isRecommended: presentsRecommendation(artifact),
                isFallback: presentsFallback(artifact),
                artifactFormat: ModelCatalogVariantTerminology.artifactFormat(
                    artifact.metadata.artifactFormat
                ),
                numericFormat: artifact.metadata.numericFormat.rawValue,
                runtime: ModelCatalogVariantTerminology.runtime(
                    artifact.metadata.runtime
                ),
                quality: Self.metric(
                    artifact: artifact,
                    reference: reference,
                    rating: {
                        $0.row.model.benchmark.map {
                            ($0.quality.label, $0.quality.score)
                        }
                    }
                ),
                speed: Self.metric(
                    artifact: artifact,
                    reference: reference,
                    rating: {
                        $0.row.model.benchmark?.speed.map {
                            ($0.label, $0.score)
                        }
                    }
                ),
                sizeLabel: artifact.row.sizeLabel,
                size: artifact.row.sizeDescription,
                computeRoute: ModelCatalogVariantTerminology.computeRoute(
                    artifact.metadata.computeRoute
                ),
                state: Self.state(for: artifact.row),
                compatibilityExplanation: artifact.row.compatibility.catalogExplanation,
                isActionable: !artifact.row.isRevoked
                    && artifact.row.compatibility.allowsModelOperations,
                isActive: artifact.row.isActive,
                primaryAction: Self.primaryAction(for: artifact.row.actions)
            )
        }
    }

    private static func metric(
        artifact: ModelCatalogExactArtifactPresentation,
        reference: ModelCatalogExactArtifactPresentation,
        rating: (ModelCatalogExactArtifactPresentation) -> (String, Int)?
    ) -> ModelCatalogVariantComparisonMetric {
        let artifactRating = rating(artifact)
        let referenceRating = rating(reference)
        if artifact.id == reference.id {
            return referenceRating.map {
                .reference(label: $0.0)
            } ?? .noBaseline
        }

        let artifactGroup = artifact.metadata.presentation.comparisonGroupID
        let referenceGroup = reference.metadata.presentation.comparisonGroupID
        guard let artifactGroup,
              let referenceGroup,
              !artifactGroup.isEmpty,
              artifactGroup == referenceGroup
        else {
            return .notComparable
        }
        guard let referenceRating else {
            return .noBaseline
        }
        guard let artifactRating else {
            return .unrated
        }
        return .compared(
            label: artifactRating.0,
            scoreDelta: artifactRating.1 - referenceRating.1
        )
    }

    private static func state(for row: ModelCatalogRowPresentation) -> String {
        var titles = row.stateTokens.map(\.title)
        if row.compatibility != .compatible,
           !row.stateTokens.contains(.incompatible) {
            titles.append(row.compatibility.catalogTitle)
        }
        if let install = row.install {
            titles.append(install.title)
        }
        return titles.isEmpty
            ? "Not installed"
            : titles.joined(separator: " • ")
    }

    private static func primaryAction(
        for actions: Set<ModelCatalogRowAction>
    ) -> ModelCatalogVariantPrimaryAction {
        if actions.contains(.cancelInstall) {
            return .cancelInstall
        }
        if actions.contains(.retryInstall) {
            return .retryInstall
        }
        if actions.contains(.disable) {
            return .disable
        }
        if actions.contains(.use) {
            return .use
        }
        if actions.contains(.install) {
            return .install
        }
        if actions.contains(.reinstall) {
            return .reinstall
        }
        return .none
    }
}
