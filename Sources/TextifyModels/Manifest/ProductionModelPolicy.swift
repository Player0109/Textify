import Foundation

public enum ProductionModelPolicyError: Error, Equatable {
    case unsupportedManifestVersion(Int)
    case expectedSingleModel(count: Int)
    case wrongModelID(String)
    case expectedSingleFile(count: Int)
    case missingChecksum
    case invalidSize
    case languageNotEnglish
    case emptyCatalog
    case duplicateModelID(String)
    case modelHasNoFiles(String)
    case duplicateFilename(modelID: String, filename: String)
    case duplicateRelativePath(modelID: String, relativePath: String)
    case missingRelativePath(modelID: String, filename: String)
    case unexpectedRelativePath(modelID: String, filename: String)
    case invalidChecksum(modelID: String, filename: String)
    case invalidModelSize(modelID: String)
    case invalidCapabilities(modelID: String)
    case incompatibleRuntime(modelID: String)
    case invalidPresentation(modelID: String)
    case unsupportedTier(modelID: String, tier: String)
    case invalidMinimumAppVersion(modelID: String, version: String)
    case invalidRuntimeParameters(modelID: String)
    case invalidModelFileURL(modelID: String, url: String)
    case invalidGeneratedAt(String)
    case benchmarkNotAllowedInV1(modelID: String)
    case invalidBenchmark(modelID: String)
    case benchmarkArtifactMismatch(modelID: String)
    case invalidPresentationGraph(ModelCatalogGraphValidationError)
}

public enum ProductionModelPolicy {
    public static let requiredModelID = "ggml-small.en-q5_1"

    public static func validateV1_1ProductionManifest(_ manifest: ModelManifest) throws {
        guard ModelManifestSchemaVersion(rawValue: manifest.manifestVersion) == .v1 else {
            throw ProductionModelPolicyError.unsupportedManifestVersion(manifest.manifestVersion)
        }
        guard manifest.models.count == 1 else {
            throw ProductionModelPolicyError.expectedSingleModel(count: manifest.models.count)
        }
        let model = manifest.models[0]
        guard model.id == requiredModelID else {
            throw ProductionModelPolicyError.wrongModelID(model.id)
        }
        guard model.files.count == 1 else {
            throw ProductionModelPolicyError.expectedSingleFile(count: model.files.count)
        }
        let file = model.files[0]
        guard !file.sha256.isEmpty else {
            throw ProductionModelPolicyError.missingChecksum
        }
        guard file.sizeBytes > 0 else {
            throw ProductionModelPolicyError.invalidSize
        }
        guard model.runtimeParameters.language == "en" else {
            throw ProductionModelPolicyError.languageNotEnglish
        }
    }

    public static func validateProductionManifest(_ manifest: ModelManifest) throws {
        guard let schemaVersion = ModelManifestSchemaVersion(
            rawValue: manifest.manifestVersion
        ) else {
            throw ProductionModelPolicyError.unsupportedManifestVersion(manifest.manifestVersion)
        }
        guard ISO8601DateFormatter().date(from: manifest.generatedAt) != nil else {
            throw ProductionModelPolicyError.invalidGeneratedAt(manifest.generatedAt)
        }
        guard !manifest.models.isEmpty else {
            throw ProductionModelPolicyError.emptyCatalog
        }

        var modelIDs = Set<String>()
        for model in manifest.models {
            if schemaVersion == .v1, model.benchmark != nil {
                throw ProductionModelPolicyError.benchmarkNotAllowedInV1(modelID: model.id)
            }
            guard modelIDs.insert(model.id).inserted else {
                throw ProductionModelPolicyError.duplicateModelID(model.id)
            }
            guard !model.files.isEmpty else {
                throw ProductionModelPolicyError.modelHasNoFiles(model.id)
            }
            guard model.sizeBytes > 0 else {
                throw ProductionModelPolicyError.invalidModelSize(modelID: model.id)
            }
            guard !model.capabilities.languages.isEmpty,
                  model.capabilities.languages.allSatisfy({ !$0.isEmpty })
            else {
                throw ProductionModelPolicyError.invalidCapabilities(modelID: model.id)
            }
            let supportedTiers = [
                "recommended", "balanced", "fast", "accurate", "specialist", "experimental"
            ]
            guard supportedTiers.contains(model.tier.lowercased()) else {
                throw ProductionModelPolicyError.unsupportedTier(
                    modelID: model.id,
                    tier: model.tier
                )
            }
            if let presentation = model.presentation {
                guard !presentation.expectedFinalization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !presentation.accuracyTradeoff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !presentation.requirements.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw ProductionModelPolicyError.invalidPresentation(modelID: model.id)
                }
            }
            guard parsedVersion(model.minAppVersion) != nil else {
                throw ProductionModelPolicyError.invalidMinimumAppVersion(
                    modelID: model.id,
                    version: model.minAppVersion
                )
            }
            guard (1...60).contains(model.runtimeParameters.maxAudioSeconds) else {
                throw ProductionModelPolicyError.invalidRuntimeParameters(modelID: model.id)
            }
            if model.runtime.engine == .fluidAudioParaformer,
               model.runtimeParameters.maxAudioSeconds > 29 {
                throw ProductionModelPolicyError.invalidRuntimeParameters(modelID: model.id)
            }

            switch model.purpose {
            case .transcription:
                switch (model.runtime.engine, model.runtime.accelerator, model.runtime.artifactLayout) {
                case (.whisperCpp, .metalGPU, .singleFile),
                     (.fluidAudioParakeet, .coreMLNeuralEngine, .modelDirectory),
                     (.fluidAudioParaformer, .coreMLNeuralEngine, .modelDirectory),
                     (.sherpaOnnx, .cpu, .modelDirectory),
                     (.transcribeCpp, .metalGPU, .singleFile),
                     (.mlxAudio, .metalGPU, .modelDirectory),
                     (.liteRTLM, .metalGPU, .singleFile):
                    break
                default:
                    throw ProductionModelPolicyError.incompatibleRuntime(modelID: model.id)
                }
            case .voiceCleaning:
                guard model.runtime.engine == .mlxAudio,
                      model.runtime.accelerator == .metalGPU,
                      model.runtime.artifactLayout == .modelDirectory,
                      [
                        "mossformer2-se-fp32",
                        "mossformer2-se-fp16",
                        "mossformer2-se-int8",
                      ].contains(model.runtime.variant),
                      model.capabilities.languages == ["*"],
                      !model.capabilities.supportsTranslation,
                      !model.capabilities.supportsCustomVocabulary
                else {
                    throw ProductionModelPolicyError.incompatibleRuntime(modelID: model.id)
                }
            }

            var filenames = Set<String>()
            var relativePaths = Set<String>()
            var totalFileSize: Int64 = 0
            for file in model.files {
                guard let url = URL(string: file.url) else {
                    throw ProductionModelPolicyError.invalidModelFileURL(
                        modelID: model.id,
                        url: file.url
                    )
                }
                do {
                    try ModelDownloadURLPolicy.requireApprovedModelFile(url)
                } catch {
                    throw ProductionModelPolicyError.invalidModelFileURL(
                        modelID: model.id,
                        url: file.url
                    )
                }
                guard filenames.insert(file.filename).inserted else {
                    throw ProductionModelPolicyError.duplicateFilename(
                        modelID: model.id,
                        filename: file.filename
                    )
                }
                guard file.sizeBytes > 0 else {
                    throw ProductionModelPolicyError.invalidSize
                }
                let nextTotal = totalFileSize.addingReportingOverflow(file.sizeBytes)
                guard !nextTotal.overflow else {
                    throw ProductionModelPolicyError.invalidModelSize(modelID: model.id)
                }
                totalFileSize = nextTotal.partialValue
                guard file.sha256.count == 64,
                      file.sha256.unicodeScalars.allSatisfy({
                          CharacterSet(charactersIn: "0123456789abcdef").contains($0)
                      })
                else {
                    throw ProductionModelPolicyError.invalidChecksum(
                        modelID: model.id,
                        filename: file.filename
                    )
                }

                switch model.runtime.artifactLayout {
                case .singleFile:
                    if file.relativePath != nil {
                        throw ProductionModelPolicyError.unexpectedRelativePath(
                            modelID: model.id,
                            filename: file.filename
                        )
                    }
                case .modelDirectory:
                    guard let relativePath = file.relativePath else {
                        throw ProductionModelPolicyError.missingRelativePath(
                            modelID: model.id,
                            filename: file.filename
                        )
                    }
                    guard relativePaths.insert(relativePath).inserted else {
                        throw ProductionModelPolicyError.duplicateRelativePath(
                            modelID: model.id,
                            relativePath: relativePath
                        )
                    }
                }
            }

            guard totalFileSize == model.sizeBytes else {
                throw ProductionModelPolicyError.invalidModelSize(modelID: model.id)
            }

            if model.runtime.artifactLayout == .singleFile, model.files.count != 1 {
                throw ProductionModelPolicyError.expectedSingleFile(count: model.files.count)
            }

            if let benchmark = model.benchmark {
                try validateBenchmark(benchmark, for: model)
            }
        }

        if schemaVersion.requiresPresentationGraph {
            guard let presentationGraph = manifest.presentationGraph else {
                throw ProductionModelPolicyError.invalidPresentationGraph(
                    .missingPresentationGraph
                )
            }
            do {
                try presentationGraph.validate(operationalModels: manifest.models)
            } catch let error as ModelCatalogGraphValidationError {
                throw ProductionModelPolicyError.invalidPresentationGraph(error)
            }
        }
    }

    public static func appVersion(
        _ currentVersion: String,
        satisfiesMinimum minimumVersion: String
    ) -> Bool {
        guard let current = parsedVersion(currentVersion),
              let minimum = parsedVersion(minimumVersion) else {
            return false
        }
        return current.lexicographicallyPrecedes(minimum) == false
    }

    private static func parsedVersion(_ version: String) -> [Int]? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            return nil
        }
        let numbers = components.compactMap { component -> Int? in
            guard !component.isEmpty,
                  component.allSatisfy(\.isNumber) else {
                return nil
            }
            return Int(component)
        }
        return numbers.count == 3 ? numbers : nil
    }

    private static func validateBenchmark(
        _ benchmark: ModelBenchmarkRating,
        for model: ModelEntry
    ) throws {
        let frozenSuiteIndexSHA256 =
            "77637f85b4e3fde7b15f5481804e231d720c0337d11153dc5867dee2587ddde8"
        guard model.purpose == .transcription,
              benchmark.schemaVersion == 1,
              benchmark.policyID == "english-catalog-rating-v2",
              benchmark.suiteID == "english-catalog-rating-v1",
              benchmark.suiteIndexSHA256 == frozenSuiteIndexSHA256,
              benchmark.modelID == model.id,
              !benchmark.engine.isEmpty,
              !benchmark.engineVersion.isEmpty,
              !benchmark.modelLicense.isEmpty,
              !benchmark.computeBackend.isEmpty,
              isGitRevision(benchmark.sourceRevision),
              benchmark.language == "en",
              model.capabilities.languages.contains("en"),
              ISO8601DateFormatter().date(from: benchmark.measuredAt) != nil,
              benchmark.referenceHost.chip == "Apple M4 Max",
              benchmark.referenceHost.architecture == "arm64",
              !benchmark.referenceHost.operatingSystem.isEmpty,
              benchmark.runCount == 3,
              benchmark.quality.speechItems == 732,
              benchmark.quality.noSpeechItems == 200,
              (0 ... 1).contains(benchmark.quality.noSpeechFalsePositiveRate),
              benchmark.quality.components.map(\.id) == [
                  "open-asr-english-nightly-v1",
                  "edacc-english-nightly-v1",
                  "berst-english-nightly-v1",
              ],
              benchmark.quality.components.map(\.weight) == [0.5, 0.3, 0.2]
        else {
            throw ProductionModelPolicyError.invalidBenchmark(modelID: model.id)
        }
        guard benchmark.artifactFingerprint == model.artifactFingerprint() else {
            throw ProductionModelPolicyError.benchmarkArtifactMismatch(modelID: model.id)
        }

        let anchors: [(excellent: Double, unacceptable: Double)] = [
            (0.05, 0.40),
            (0.12, 0.55),
            (0.18, 0.70),
        ]
        for (component, anchor) in zip(benchmark.quality.components, anchors) {
            let expected = lowerIsBetterBenchmarkScore(
                value: component.wordErrorRate,
                excellent: anchor.excellent,
                unacceptable: anchor.unacceptable
            )
            guard component.wordErrorRate >= 0,
                  (0 ... 100).contains(component.score),
                  abs(component.score - expected) < 0.000_001
            else {
                throw ProductionModelPolicyError.invalidBenchmark(modelID: model.id)
            }
        }
        let expectedQualityScore = Int(
            benchmark.quality.components.reduce(0) {
                $0 + $1.score * $1.weight
            }.rounded()
        )
        let expectedQualityLevel = benchmarkLevel(for: expectedQualityScore)
        guard benchmark.quality.score == expectedQualityScore,
              benchmark.quality.level == expectedQualityLevel,
              benchmark.quality.label == qualityLabel(for: expectedQualityLevel)
        else {
            throw ProductionModelPolicyError.invalidBenchmark(modelID: model.id)
        }

        if let speed = benchmark.speed {
            let expectedSpeedScore = Int((
                lowerIsBetterBenchmarkScore(
                    value: Double(speed.p95ReleaseToFinalMs),
                    excellent: 150,
                    unacceptable: 1_200
                ) * 0.7
                    + lowerIsBetterBenchmarkScore(
                        value: speed.p95RealTimeFactor,
                        excellent: 0.02,
                        unacceptable: 0.25
                    ) * 0.3
            ).rounded())
            let expectedSpeedLevel = benchmarkLevel(for: expectedSpeedScore)
            guard benchmark.speedUnratedReason == nil,
                  speed.p50ReleaseToFinalMs >= 0,
                  speed.p95ReleaseToFinalMs >= speed.p50ReleaseToFinalMs,
                  speed.p95RealTimeFactor >= 0,
                  (0 ... 0.15).contains(speed.relativeP95Spread),
                  speed.score == expectedSpeedScore,
                  speed.level == expectedSpeedLevel,
                  speed.label == speedLabel(for: expectedSpeedLevel)
            else {
                throw ProductionModelPolicyError.invalidBenchmark(modelID: model.id)
            }
        } else {
            guard benchmark.speedUnratedReason == "unstable-p95" else {
                throw ProductionModelPolicyError.invalidBenchmark(modelID: model.id)
            }
        }
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.allSatisfy(Set("0123456789abcdef").contains)
    }

    private static func isGitRevision(_ value: String) -> Bool {
        (value.count == 40 || value.count == 64)
            && value.allSatisfy(Set("0123456789abcdef").contains)
    }

    private static func lowerIsBetterBenchmarkScore(
        value: Double,
        excellent: Double,
        unacceptable: Double
    ) -> Double {
        min(100, max(0, (unacceptable - value) / (unacceptable - excellent) * 100))
    }

    private static func benchmarkLevel(for score: Int) -> Int {
        switch score {
        case 90...:
            return 5
        case 75...:
            return 4
        case 60...:
            return 3
        case 40...:
            return 2
        default:
            return 1
        }
    }

    private static func qualityLabel(for level: Int) -> String {
        [1: "Limited", 2: "Basic", 3: "Balanced", 4: "High", 5: "Highest"][level]!
    }

    private static func speedLabel(for level: Int) -> String {
        [1: "Slow", 2: "Measured", 3: "Balanced", 4: "Fast", 5: "Fastest"][level]!
    }
}
