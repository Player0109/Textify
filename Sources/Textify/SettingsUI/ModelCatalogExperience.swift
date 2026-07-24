import Foundation
import TextifyModels

enum ModelCatalogSort: String, CaseIterable, Identifiable {
    case catalog
    case quality
    case speed

    var id: Self { self }

    var title: String {
        switch self {
        case .catalog: "Catalog"
        case .quality: "Quality"
        case .speed: "Speed"
        }
    }
}

enum ModelArtifactFormat: String, CaseIterable, Identifiable {
    case mlx
    case gguf
    case other

    static let filterOptions: [ModelArtifactFormat] = [.mlx, .gguf]

    var id: Self { self }

    var title: String {
        switch self {
        case .mlx: "MLX"
        case .gguf: "GGUF"
        case .other: "Other"
        }
    }
}

enum ModelArtifactPrecision: String, CaseIterable, Identifiable {
    case thirtyTwoBit
    case sixteenBit
    case eightBit
    case fiveBit
    case fourBit
    case other

    static let filterOptions: [ModelArtifactPrecision] = [
        .thirtyTwoBit,
        .sixteenBit,
        .eightBit,
        .fiveBit,
        .fourBit,
    ]

    var id: Self { self }

    var title: String {
        switch self {
        case .thirtyTwoBit: "32-bit"
        case .sixteenBit: "16-bit"
        case .eightBit: "8-bit"
        case .fiveBit: "5-bit"
        case .fourBit: "4-bit"
        case .other: "Other"
        }
    }
}

struct ModelCatalogQuery: Equatable {
    var sort: ModelCatalogSort = .catalog
    var format: ModelArtifactFormat?
    var precision: ModelArtifactPrecision?

    func apply(to models: [ProductionModelPresentation]) -> [ProductionModelPresentation] {
        let matches = models.enumerated().filter { _, model in
            (format == nil || model.artifactFormat == format)
                && (precision == nil || model.artifactPrecision == precision)
        }

        switch sort {
        case .catalog:
            return matches.map(\.element)
        case .quality:
            return matches.sorted { lhs, rhs in
                if lhs.element.qualityScore != rhs.element.qualityScore {
                    return (lhs.element.qualityScore ?? -1)
                        > (rhs.element.qualityScore ?? -1)
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        case .speed:
            return matches.sorted { lhs, rhs in
                if lhs.element.speedScore != rhs.element.speedScore {
                    return (lhs.element.speedScore ?? -1)
                        > (rhs.element.speedScore ?? -1)
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        }
    }
}

enum ModelProviderIdentity: String, Equatable {
    case openAI
    case nvidia
    case cohere
    case qwen
    case alibaba
    case apple
    case mlx
    case reazon
    case mossFormer
    case community

    static func resolve(from components: String...) -> ModelProviderIdentity {
        let identity = components.joined(separator: " ").lowercased()
        if identity.contains("cohere") {
            return .cohere
        }
        if identity.contains("nvidia")
            || identity.contains("parakeet")
            || identity.contains("canary")
            || identity.contains("nemotron") {
            return .nvidia
        }
        if identity.contains("openai") || identity.contains("whisper") {
            return .openAI
        }
        if identity.contains("qwen") {
            return .qwen
        }
        if identity.contains("alibaba")
            || identity.contains("paraformer")
            || identity.contains("sensevoice")
            || identity.contains("mossformer") {
            return .alibaba
        }
        if identity.contains("reazon") {
            return .reazon
        }
        if identity.contains("apple") {
            return .apple
        }
        if identity.contains("mlx") {
            return .mlx
        }
        return .community
    }

    var name: String {
        switch self {
        case .openAI: "OpenAI"
        case .nvidia: "NVIDIA"
        case .cohere: "Cohere"
        case .qwen: "Qwen by Alibaba Cloud"
        case .alibaba: "Alibaba Cloud"
        case .apple: "Apple"
        case .mlx: "Apple MLX"
        case .reazon: "Reazon Human Interaction Lab"
        case .mossFormer: "Alibaba Speech Lab"
        case .community: "Open model"
        }
    }
}

struct ModelCatalogActivePreferences: Equatable {
    let transcriptionModelID: String?
    let voiceCleaningModelID: String?

    init(
        transcriptionModelID: String? = nil,
        voiceCleaningModelID: String? = nil
    ) {
        self.transcriptionModelID = transcriptionModelID
        self.voiceCleaningModelID = voiceCleaningModelID
    }

    var orderedModelIDs: [String] {
        [transcriptionModelID, voiceCleaningModelID].compactMap { $0 }
    }

    func contains(modelID: String, purpose: ModelPurpose) -> Bool {
        switch purpose {
        case .transcription:
            transcriptionModelID == modelID
        case .voiceCleaning:
            voiceCleaningModelID == modelID
        }
    }
}

enum ModelCatalogRowAction: Equatable, Hashable {
    case use
    case disable
    case install
    case reinstall
    case delete
    case cancelInstall
    case retryInstall
    case details
}

struct ModelCatalogRowPresentation: Equatable, Identifiable {
    let model: ProductionModelPresentation
    let operationalModel: ModelEntry?
    let installedRecord: InstalledModelRecord?
    let isInstalled: Bool
    let isActive: Bool
    let install: ModelCatalogInstallPresentation?
    let actions: Set<ModelCatalogRowAction>

    var id: String {
        model.id
    }

    var installState: DownloadState? {
        install?.state
    }
}

struct ModelCatalogFamilyPresentation: Equatable, Identifiable {
    let metadata: ModelFamilyPresentationNode
    let checkpoints: [ModelCatalogCheckpointPresentation]

    var id: String {
        metadata.id
    }
}

struct ModelCatalogCheckpointPresentation: Equatable, Identifiable {
    let metadata: ModelCheckpointPresentationNode
    let artifacts: [ModelCatalogExactArtifactPresentation]
    let referenceArtifact: ModelCatalogExactArtifactPresentation?

    var id: String {
        metadata.id
    }
}

struct ModelCatalogExactArtifactPresentation: Equatable, Identifiable {
    let metadata: ModelExactArtifactPresentationNode
    let row: ModelCatalogRowPresentation

    var id: String {
        metadata.id
    }
}

enum ModelCatalogHierarchyRowID: Equatable, Hashable {
    case family(String)
    case checkpoint(String)
    case exactArtifact(String)
}

enum ModelCatalogHierarchySelection: Equatable, Hashable {
    case checkpoint(String)
    case exactArtifact(String)
}

struct ModelCatalogHierarchyRow: Equatable, Identifiable {
    enum Content: Equatable {
        case family(ModelCatalogFamilyPresentation)
        case checkpoint(ModelCatalogCheckpointPresentation)
        case exactArtifact(
            checkpoint: ModelCatalogCheckpointPresentation,
            artifact: ModelCatalogExactArtifactPresentation,
            isSingleVariant: Bool
        )
    }

    let content: Content
    let isExpanded: Bool

    var id: ModelCatalogHierarchyRowID {
        switch content {
        case let .family(family):
            .family(family.id)
        case let .checkpoint(checkpoint):
            .checkpoint(checkpoint.id)
        case let .exactArtifact(_, artifact, _):
            .exactArtifact(artifact.id)
        }
    }
}

struct ModelCatalogHierarchyState: Equatable {
    private(set) var selection: ModelCatalogHierarchySelection?
    private(set) var expandedCheckpointIDs: Set<String>

    init(
        selection: ModelCatalogHierarchySelection? = nil,
        expandedCheckpointIDs: Set<String> = []
    ) {
        self.selection = selection
        self.expandedCheckpointIDs = expandedCheckpointIDs
    }

    mutating func select(_ selection: ModelCatalogHierarchySelection) {
        self.selection = selection
    }

    mutating func toggleExpansion(of checkpoint: ModelCatalogCheckpointPresentation) {
        if expandedCheckpointIDs.remove(checkpoint.id) != nil {
            if case let .exactArtifact(selectedArtifactID) = selection,
               checkpoint.artifacts.contains(where: { $0.id == selectedArtifactID }) {
                selection = .checkpoint(checkpoint.id)
            }
        } else {
            expandedCheckpointIDs.insert(checkpoint.id)
        }
    }

    mutating func reconcile(with experience: ModelCatalogExperience) {
        let checkpoints = experience.families.flatMap(\.checkpoints)
        let validCheckpointIDs = Set(checkpoints.map(\.id))
        let validArtifactIDs = Set(checkpoints.flatMap(\.artifacts).map(\.id))

        expandedCheckpointIDs.formIntersection(
            checkpoints
                .filter { $0.metadata.artifactIDs.count > 1 }
                .map(\.id)
        )

        switch selection {
        case let .checkpoint(id) where !validCheckpointIDs.contains(id),
             let .exactArtifact(id) where !validArtifactIDs.contains(id):
            selection = nil
        case .checkpoint, .exactArtifact, nil:
            break
        }
    }

    func visibleRows(in experience: ModelCatalogExperience) -> [ModelCatalogHierarchyRow] {
        experience.families.flatMap { family in
            var rows = [
                ModelCatalogHierarchyRow(
                    content: .family(family),
                    isExpanded: true
                ),
            ]

            for checkpoint in family.checkpoints {
                if checkpoint.metadata.artifactIDs.count == 1,
                   let artifact = checkpoint.artifacts.first {
                    rows.append(
                        ModelCatalogHierarchyRow(
                            content: .exactArtifact(
                                checkpoint: checkpoint,
                                artifact: artifact,
                                isSingleVariant: true
                            ),
                            isExpanded: false
                        )
                    )
                    continue
                }

                let isExpanded = expandedCheckpointIDs.contains(checkpoint.id)
                rows.append(
                    ModelCatalogHierarchyRow(
                        content: .checkpoint(checkpoint),
                        isExpanded: isExpanded
                    )
                )
                guard isExpanded else {
                    continue
                }
                rows.append(
                    contentsOf: checkpoint.artifacts.map {
                        ModelCatalogHierarchyRow(
                            content: .exactArtifact(
                                checkpoint: checkpoint,
                                artifact: $0,
                                isSingleVariant: false
                            ),
                            isExpanded: false
                        )
                    }
                )
            }
            return rows
        }
    }
}

struct ModelCatalogInstallPresentation: Equatable {
    let state: DownloadState
    let title: String
    let percentText: String?
    let progressValue: Double
    let detailText: String

    init(state: DownloadState) {
        self.state = state
        title = ModelInstallProgressPresentation.title(for: state)
        percentText = ModelInstallProgressPresentation.percentText(for: state)
        progressValue = ModelInstallProgressPresentation.progressValue(for: state)
        detailText = ModelInstallProgressPresentation.detailText(for: state)
    }
}

struct ModelCatalogExperience: Equatable {
    let rows: [ModelCatalogRowPresentation]
    let families: [ModelCatalogFamilyPresentation]
    private let inspectorFamilies: [ModelCatalogFamilyPresentation]

    init(
        trustedModels: [ModelEntry],
        installedRecords: [InstalledModelRecord],
        activePreferences: ModelCatalogActivePreferences,
        transferState: DownloadState?,
        query: ModelCatalogQuery = ModelCatalogQuery()
    ) {
        self.init(
            trustedModels: trustedModels,
            presentationGraph: nil,
            installedRecords: installedRecords,
            activePreferences: activePreferences,
            transferState: transferState,
            query: query
        )
    }

    init(
        trustedManifest: ModelManifest?,
        installedRecords: [InstalledModelRecord],
        activePreferences: ModelCatalogActivePreferences,
        transferState: DownloadState?,
        query: ModelCatalogQuery = ModelCatalogQuery()
    ) {
        self.init(
            trustedModels: trustedManifest?.models ?? [],
            presentationGraph: trustedManifest?.presentationGraph,
            installedRecords: installedRecords,
            activePreferences: activePreferences,
            transferState: transferState,
            query: query
        )
    }

    private init(
        trustedModels: [ModelEntry],
        presentationGraph: ModelCatalogPresentationGraph?,
        installedRecords: [InstalledModelRecord],
        activePreferences: ModelCatalogActivePreferences,
        transferState: DownloadState?,
        query: ModelCatalogQuery
    ) {
        let signedArtifactsByID = presentationGraph?.artifacts.reduce(
            into: [String: ModelExactArtifactPresentationNode]()
        ) {
            $0[$1.id] = $1
        } ?? [:]
        let trustedCatalog = trustedModels.isEmpty
            ? ProductionModelPresentation.visibleCatalog
            : trustedModels.map {
                ProductionModelPresentation(
                    model: $0,
                    signedArtifact: signedArtifactsByID[$0.id]
                )
            }
        let trustedIDs = Set(trustedCatalog.map(\.id))
        let trustedModelsByID = trustedModels.reduce(into: [String: ModelEntry]()) {
            $0[$1.id] = $1
        }
        let installedByID = installedRecords.reduce(into: [String: ModelEntry]()) {
            $0[$1.model.id] = $1.model
        }
        let installedRecordsByID = installedRecords.reduce(
            into: [String: InstalledModelRecord]()
        ) {
            $0[$1.model.id] = $1
        }
        let installedIDs = Set(installedByID.keys)
        let localCatalog = installedRecords
            .map(\.model)
            .filter { !trustedIDs.contains($0.id) }
            .map { ProductionModelPresentation(model: $0, isCurated: false) }

        var orderedCatalog = trustedCatalog + localCatalog
        for activeID in activePreferences.orderedModelIDs.reversed() {
            guard let activeIndex = orderedCatalog.firstIndex(where: { $0.id == activeID }) else {
                continue
            }
            let activeModel = orderedCatalog.remove(at: activeIndex)
            orderedCatalog.insert(activeModel, at: 0)
        }

        let allRows = orderedCatalog.map { model in
            let installedModel = installedByID[model.id]
            let isInstalled = installedIDs.contains(model.id)
            let activePurpose = installedModel?.purpose ?? model.purpose
            let isActive = isInstalled
                && activePreferences.contains(modelID: model.id, purpose: activePurpose)
            let installState = ModelInstallRowPresentation.state(
                for: model.id,
                from: transferState
            )
            return ModelCatalogRowPresentation(
                model: model,
                operationalModel: trustedModelsByID[model.id] ?? installedModel,
                installedRecord: installedRecordsByID[model.id],
                isInstalled: isInstalled,
                isActive: isActive,
                install: installState.map(ModelCatalogInstallPresentation.init),
                actions: Self.actions(
                    for: model,
                    isInstalled: isInstalled,
                    isActive: isActive,
                    installState: installState
                )
            )
        }
        let allRowsByID = allRows.reduce(into: [String: ModelCatalogRowPresentation]()) {
            $0[$1.id] = $1
        }
        let derivedRows = query.apply(to: orderedCatalog).compactMap {
            allRowsByID[$0.id]
        }
        rows = derivedRows
        families = presentationGraph.map {
            Self.makeFamilyPresentations(
                graph: $0,
                rows: derivedRows,
                referenceRows: allRows
            )
        } ?? []
        inspectorFamilies = presentationGraph.map {
            Self.makeFamilyPresentations(
                graph: $0,
                rows: allRows,
                referenceRows: allRows
            )
        } ?? []
    }

    func inspectorPresentation(
        for selection: ModelCatalogHierarchySelection
    ) -> ModelCatalogInspectorPresentation? {
        switch selection {
        case let .checkpoint(checkpointID):
            guard let checkpoint = inspectorFamilies
                .flatMap(\.checkpoints)
                .first(where: { $0.id == checkpointID })
            else {
                return nil
            }
            return Self.checkpointInspector(checkpoint).map {
                .checkpoint($0)
            }
        case let .exactArtifact(artifactID):
            for checkpoint in inspectorFamilies.flatMap(\.checkpoints) {
                guard let artifact = checkpoint.artifacts.first(
                    where: { $0.id == artifactID }
                ) else {
                    continue
                }
                return .exactArtifact(
                    Self.exactArtifactInspector(
                        checkpoint: checkpoint,
                        artifact: artifact
                    )
                )
            }
            return nil
        }
    }

    private static func checkpointInspector(
        _ checkpoint: ModelCatalogCheckpointPresentation
    ) -> ModelCatalogCheckpointInspectorPresentation? {
        guard let referenceArtifact = checkpoint.artifacts.first(
            where: { $0.id == checkpoint.metadata.recommendedArtifactID }
        ) ?? checkpoint.artifacts.first else {
            return nil
        }

        let installedCount = checkpoint.artifacts.filter(\.row.isInstalled).count
        var aggregateState = installedCount == 0
            ? "No variants installed"
            : "\(installedCount) of \(checkpoint.metadata.artifactIDs.count) variants installed"
        if let activeArtifact = checkpoint.artifacts.first(where: \.row.isActive) {
            aggregateState += " • \(activeArtifact.metadata.presentation.displayName) active"
        } else if let install = checkpoint.artifacts.compactMap(\.row.install).first {
            aggregateState += " • \(install.title)"
        }

        var capabilities = [
            checkpoint.metadata.purpose == .voiceCleaning
                ? "Voice cleaning"
                : "Speech recognition",
        ]
        let operationalModels = checkpoint.artifacts.compactMap(\.row.operationalModel)
        if operationalModels.contains(where: \.capabilities.supportsTranslation) {
            capabilities.append("Translation")
        }
        if operationalModels.contains(where: \.capabilities.supportsCustomVocabulary) {
            capabilities.append("Custom vocabulary")
        }

        return ModelCatalogCheckpointInspectorPresentation(
            id: checkpoint.id,
            displayName: checkpoint.metadata.presentation.displayName,
            description: checkpoint.metadata.presentation.description,
            referenceArtifactID: referenceArtifact.id,
            referenceArtifactName: referenceArtifact.metadata.presentation.displayName,
            referenceQuality: referenceArtifact.row.model.qualityLabel,
            referenceSpeed: referenceArtifact.row.model.speedLabel,
            referenceQualityEvidence: referenceArtifact.row.model
                .qualityEvidenceDescription
                ?? "No signed comparable quality evidence",
            referenceSpeedEvidence: referenceArtifact.row.model
                .speedEvidenceDescription
                ?? "No signed stable speed evidence",
            aggregateState: aggregateState,
            languages: checkpointLanguageDescription(checkpoint.artifacts),
            capabilities: capabilities.joined(separator: " • ")
        )
    }

    private static func exactArtifactInspector(
        checkpoint: ModelCatalogCheckpointPresentation,
        artifact: ModelCatalogExactArtifactPresentation
    ) -> ModelCatalogExactArtifactInspectorPresentation {
        let model = artifact.row.operationalModel
        let metadata = artifact.metadata
        let compatibility = metadata.compatibility
        var compatibilityParts = [
            "Textify \(compatibility.minimumAppVersion)+",
            "macOS \(compatibility.minimumMacOSVersion)+",
            compatibility.supportedArchitectures.map(\.rawValue).joined(separator: ", "),
        ]
        if let minimumMemoryBytes = compatibility.minimumMemoryBytes {
            let minimumMemory = ByteCountFormatter.string(
                fromByteCount: minimumMemoryBytes,
                countStyle: .memory
            )
            compatibilityParts.append("\(minimumMemory) memory")
        }

        let provenance = model.map {
            "\($0.provenance.sourceName) • \($0.provenance.originalModelName) • "
                + "revision \($0.provenance.sourceRevision.prefix(12)) • "
                + $0.provenance.sourceFile
        } ?? "Catalog provenance unavailable"
        let license = model.map {
            $0.licenses.map {
                "\($0.spdxId) — \($0.name) (\($0.scope))"
            }.joined(separator: " • ")
        } ?? "License metadata unavailable"
        let localInspectionRequest = makeLocalInspectionRequest(
            artifactID: artifact.id,
            model: model,
            installedRecord: artifact.row.installedRecord
        )
        let verificationRequest = makeVerificationRequest(
            artifactID: artifact.id,
            model: model,
            installedRecord: artifact.row.installedRecord
        )

        return ModelCatalogExactArtifactInspectorPresentation(
            id: artifact.id,
            checkpointName: checkpoint.metadata.presentation.displayName,
            displayName: metadata.presentation.displayName,
            description: model?.description ?? artifact.row.model.description,
            artifactFormat: ModelCatalogVariantTerminology.artifactFormat(
                metadata.artifactFormat
            ),
            numericFormat: metadata.numericFormat.rawValue,
            runtime: ModelCatalogVariantTerminology.runtime(metadata.runtime),
            computeRoute: ModelCatalogVariantTerminology.computeRoute(
                metadata.computeRoute
            ),
            compatibility: compatibilityParts.joined(separator: " • "),
            qualityEvidence: artifact.row.model.qualityEvidenceDescription ?? "Unrated",
            speedEvidence: artifact.row.model.speedEvidenceDescription ?? "Unrated",
            transferSize: ByteCountFormatter.string(
                fromByteCount: model?.sizeBytes ?? 0,
                countStyle: .file
            ),
            localState: localState(for: artifact.row),
            provenance: provenance,
            license: license,
            sourceURL: artifact.row.model.sourceURL,
            canVerify: artifact.row.isInstalled,
            localInspectionRequest: localInspectionRequest,
            verificationRequest: verificationRequest
        )
    }

    private static func makeLocalInspectionRequest(
        artifactID: String,
        model: ModelEntry?,
        installedRecord: InstalledModelRecord?
    ) -> ModelCatalogArtifactInspectionRequest? {
        guard let model, let installedRecord else {
            return nil
        }
        return ModelCatalogArtifactInspectionRequest(
            artifactID: artifactID,
            expectedFiles: model.files.map {
                ModelCatalogArtifactInspectionRequest.ExpectedFile(
                    relativePath: $0.relativePath ?? $0.filename,
                    expectedSizeBytes: $0.sizeBytes,
                    localPath: installedRecord.localFilesByManifestFilename[$0.filename]
                )
            }
        )
    }

    private static func makeVerificationRequest(
        artifactID: String,
        model: ModelEntry?,
        installedRecord: InstalledModelRecord?
    ) -> ModelCatalogArtifactVerificationRequest? {
        guard let model, let installedRecord else {
            return nil
        }
        return ModelCatalogArtifactVerificationRequest(
            artifactID: artifactID,
            expectedFiles: model.files.map {
                ModelCatalogArtifactVerificationRequest.ExpectedFile(
                    relativePath: $0.relativePath ?? $0.filename,
                    expectedSizeBytes: $0.sizeBytes,
                    expectedSHA256: $0.sha256,
                    localPath: installedRecord.localFilesByManifestFilename[$0.filename]
                )
            }
        )
    }

    private static func localState(for row: ModelCatalogRowPresentation) -> String {
        if row.isActive {
            return "Active • Installed"
        }
        if row.isInstalled {
            return "Installed"
        }
        if let install = row.install {
            return install.title
        }
        return "Not installed"
    }

    private static func checkpointLanguageDescription(
        _ artifacts: [ModelCatalogExactArtifactPresentation]
    ) -> String {
        let languageCodes = orderedUnique(
            artifacts
                .compactMap(\.row.operationalModel)
                .flatMap(\.capabilities.languages)
        )
        guard !languageCodes.isEmpty else {
            return "Capabilities unavailable"
        }
        if languageCodes.contains("*") {
            return "Language agnostic"
        }
        if languageCodes.count > 5 {
            return "\(languageCodes.count) languages"
        }
        return languageCodes.map(languageName).joined(separator: ", ")
    }

    private static func languageName(_ code: String) -> String {
        Locale(identifier: "en_US").localizedString(forLanguageCode: code)?
            .capitalized
            ?? code.uppercased()
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func actions(
        for model: ProductionModelPresentation,
        isInstalled: Bool,
        isActive: Bool,
        installState: DownloadState?
    ) -> Set<ModelCatalogRowAction> {
        var actions: Set<ModelCatalogRowAction> = [.details]

        if isActive {
            if model.purpose == .voiceCleaning {
                actions.insert(.disable)
            }
        } else if isInstalled {
            actions.insert(.use)
        }

        if installState == nil {
            actions.insert(isInstalled ? .reinstall : .install)
        } else if let installState {
            if ModelInstallRowPresentation.offersCancel(for: installState) {
                actions.insert(.cancelInstall)
            }
            if ModelInstallRowPresentation.offersRetry(for: installState) {
                actions.insert(.retryInstall)
            }
        }

        if isInstalled {
            actions.insert(.delete)
        }

        return actions
    }

    private static func makeFamilyPresentations(
        graph: ModelCatalogPresentationGraph,
        rows: [ModelCatalogRowPresentation],
        referenceRows: [ModelCatalogRowPresentation]
    ) -> [ModelCatalogFamilyPresentation] {
        let checkpointsByID = graph.checkpoints.reduce(
            into: [String: ModelCheckpointPresentationNode]()
        ) {
            $0[$1.id] = $1
        }
        let artifactsByID = graph.artifacts.reduce(
            into: [String: ModelExactArtifactPresentationNode]()
        ) {
            $0[$1.id] = $1
        }
        let rowsByID = rows.reduce(into: [String: ModelCatalogRowPresentation]()) {
            $0[$1.id] = $1
        }
        let referenceRowsByID = referenceRows.reduce(
            into: [String: ModelCatalogRowPresentation]()
        ) {
            $0[$1.id] = $1
        }

        return graph.families.compactMap { family in
            let checkpoints: [ModelCatalogCheckpointPresentation] = family.checkpointIDs
                .compactMap { checkpointID in
                    guard let checkpoint = checkpointsByID[checkpointID] else {
                        return nil
                    }
                    let artifacts: [ModelCatalogExactArtifactPresentation] =
                        checkpoint.artifactIDs.compactMap { artifactID in
                            guard let artifact = artifactsByID[artifactID],
                                  let row = rowsByID[artifactID] else {
                                return nil
                            }
                            return ModelCatalogExactArtifactPresentation(
                                metadata: artifact,
                                row: row
                            )
                        }
                    guard !artifacts.isEmpty else {
                        return nil
                    }
                    var referenceArtifact = artifacts.first {
                        $0.id == checkpoint.recommendedArtifactID
                    }
                    if referenceArtifact == nil,
                       let metadata = artifactsByID[
                           checkpoint.recommendedArtifactID
                       ],
                       let row = referenceRowsByID[
                           checkpoint.recommendedArtifactID
                       ] {
                        referenceArtifact = ModelCatalogExactArtifactPresentation(
                            metadata: metadata,
                            row: row
                        )
                    }
                    return ModelCatalogCheckpointPresentation(
                        metadata: checkpoint,
                        artifacts: artifacts,
                        referenceArtifact: referenceArtifact
                    )
                }
            guard !checkpoints.isEmpty else {
                return nil
            }
            return ModelCatalogFamilyPresentation(
                metadata: family,
                checkpoints: checkpoints
            )
        }
    }
}

enum ModelInstallRowPresentation {
    static func state(for modelID: String, from state: DownloadState?) -> DownloadState? {
        guard let state, state.modelID == modelID, state.phase != .installed else {
            return nil
        }
        return state
    }

    static func offersCancel(for state: DownloadState) -> Bool {
        state.isActive
    }

    static func offersRetry(for state: DownloadState) -> Bool {
        switch state.phase {
        case .interrupted, .failed, .cancelled:
            return true
        case .checkingSpace, .downloading, .verifying, .installing, .installed:
            return false
        }
    }
}

enum ModelInstallProgressPresentation {
    static func title(for state: DownloadState) -> String {
        switch state.phase {
        case .checkingSpace:
            return "Preparing download"
        case .downloading:
            return "Downloading model"
        case .interrupted:
            return "Download interrupted"
        case .verifying:
            return "Verifying model"
        case .installing:
            return "Installing model"
        case .installed:
            return "Model installed"
        case .failed:
            return "Install failed"
        case .cancelled:
            return "Install cancelled"
        }
    }

    static func percentText(for state: DownloadState) -> String? {
        guard state.totalBytes > 0 else {
            return nil
        }

        return "\(Int((state.progressFraction * 100).rounded()))%"
    }

    static func progressValue(for state: DownloadState) -> Double {
        state.progressFraction
    }

    static func detailText(for state: DownloadState) -> String {
        if state.phase == .failed, let message = state.message {
            return message
        }

        if state.totalBytes > 0 {
            return "\(bytes(state.bytesDownloaded)) of \(bytes(state.totalBytes))"
        }

        if state.bytesDownloaded > 0 {
            return bytes(state.bytesDownloaded)
        }

        return state.message ?? "Starting..."
    }

    private static func bytes(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

struct ProductionModelPresentation: Equatable, Identifiable {
    let id: String
    let displayName: String
    let description: String
    let details: String?
    let isCurated: Bool
    let supportTier: String
    let expectedFinalization: String
    let accuracyTradeoff: String
    let requirements: String
    let artifactFormat: ModelArtifactFormat
    let artifactPrecision: ModelArtifactPrecision
    let engineName: String
    let engineIcon: String
    let acceleratorName: String
    let sizeDescription: String
    let languageDescription: String
    let licenseDescription: String
    let sourceName: String
    let sourceURL: URL?
    let artifactName: String
    let checksum: String?
    let purpose: ModelPurpose
    let benchmark: ModelBenchmarkRating?

    init(
        id: String,
        displayName: String,
        description: String,
        details: String?,
        isCurated: Bool = true,
        supportTier: String = "Custom",
        expectedFinalization: String = "Varies by model",
        accuracyTradeoff: String = "See model description",
        requirements: String = "Apple Silicon",
        artifactFormat: ModelArtifactFormat = .other,
        artifactPrecision: ModelArtifactPrecision = .other,
        engineName: String = "Local runtime",
        engineIcon: String = "waveform.circle",
        acceleratorName: String = "Apple Silicon",
        sizeDescription: String = "Local",
        languageDescription: String = "Varies",
        licenseDescription: String = "See source",
        sourceName: String = "Model source",
        sourceURL: URL? = nil,
        artifactName: String = "Local model",
        checksum: String? = nil,
        purpose: ModelPurpose = .transcription,
        benchmark: ModelBenchmarkRating? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.details = details
        self.isCurated = isCurated
        self.supportTier = supportTier
        self.expectedFinalization = expectedFinalization
        self.accuracyTradeoff = accuracyTradeoff
        self.requirements = requirements
        self.artifactFormat = artifactFormat
        self.artifactPrecision = artifactPrecision
        self.engineName = engineName
        self.engineIcon = engineIcon
        self.acceleratorName = acceleratorName
        self.sizeDescription = sizeDescription
        self.languageDescription = languageDescription
        self.licenseDescription = licenseDescription
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.artifactName = artifactName
        self.checksum = checksum
        self.purpose = purpose
        self.benchmark = benchmark
    }

    static let v1_1 = ProductionModelPresentation(
        id: ProductionModelPolicy.requiredModelID,
        displayName: "Balanced - Whisper small.en q5_1",
        description: "Local English dictation model for Textify V1.1.",
        details: "Whisper.cpp • Metal GPU • English",
        supportTier: "Recommended",
        expectedFinalization: "Near-instant after release",
        accuracyTradeoff: "Balanced English speed and accuracy",
        requirements: "Apple Silicon • about 182 MB download",
        artifactPrecision: .fiveBit,
        engineName: "Whisper.cpp",
        engineIcon: "waveform.circle",
        acceleratorName: "Metal GPU",
        sizeDescription: "182 MB",
        languageDescription: "English",
        licenseDescription: "MIT",
        sourceName: "ggerganov/whisper.cpp",
        artifactName: "ggml-small.en-q5_1.bin"
    )

    static let visibleCatalog: [ProductionModelPresentation] = [v1_1]

    init(
        model: ModelEntry,
        isCurated: Bool = true,
        signedArtifact: ModelExactArtifactPresentationNode? = nil
    ) {
        id = model.id
        displayName = model.displayName
        description = model.description
        purpose = model.purpose
        self.isCurated = isCurated
        artifactFormat = signedArtifact.map {
            Self.artifactFormat(for: $0.artifactFormat)
        } ?? Self.artifactFormat(for: model)
        artifactPrecision = signedArtifact.map {
            Self.artifactPrecision(for: $0.numericFormat)
        } ?? Self.artifactPrecision(for: model)
        let enginePresentation = switch model.runtime.engine {
        case .whisperCpp: ("Whisper.cpp", "waveform.circle")
        case .fluidAudioParakeet: ("Parakeet", "bolt.horizontal.circle")
        case .fluidAudioParaformer: ("Paraformer", "character.waveform")
        case .sherpaOnnx: ("sherpa-onnx", "point.3.connected.trianglepath.dotted")
        case .transcribeCpp: ("transcribe.cpp", "cpu")
        case .mlxAudio: ("MLX Audio", "sparkles.rectangle.stack")
        case .liteRTLM: ("LiteRT-LM", "cube.transparent")
        }
        engineName = enginePresentation.0
        engineIcon = enginePresentation.1
        acceleratorName = switch model.runtime.accelerator {
        case .metalGPU: "Metal GPU"
        case .coreMLNeuralEngine: "Core ML / Neural Engine"
        case .cpu: "Apple Silicon CPU"
        }
        languageDescription = Self.languageDescription(for: model.capabilities.languages)
        sizeDescription = ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)
        let license = model.licenses.first?.name ?? "License metadata unavailable"
        details = "\(engineName) • \(acceleratorName) • \(languageDescription) • \(sizeDescription) • \(license)"
        licenseDescription = model.licenses.map(\.spdxId).joined(separator: " + ")
        sourceName = model.provenance.sourceName
        sourceURL = Self.publicSourceURL(from: model.provenance.sourceUrl)
        artifactName = model.files.count == 1
            ? (model.files.first?.filename ?? "Model artifact")
            : "\(model.files.count) signed files"
        checksum = model.files.first?.sha256
        supportTier = Self.supportTier(for: model.tier)
        expectedFinalization = model.presentation?.expectedFinalization
            ?? Self.fallbackFinalization(for: model.tier)
        accuracyTradeoff = model.presentation?.accuracyTradeoff ?? model.description
        requirements = model.presentation?.requirements ?? "Apple Silicon • \(acceleratorName)"
        benchmark = model.benchmark
    }

    var qualitySignalLevel: Int {
        benchmark?.quality.level ?? 0
    }

    var catalogDisplayName: String {
        let parts = displayName.split(separator: "-", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let tierPrefixes = ["Accurate", "Balanced", "Experimental", "Fast", "Recommended", "Specialist"]
        guard parts.count == 2, tierPrefixes.contains(parts[0]) else {
            return displayName
        }
        return parts[1]
    }

    var provider: ModelProviderIdentity {
        .resolve(from: displayName, sourceName, engineName)
    }

    var activationMessage: String {
        purpose == .voiceCleaning
            ? "\(displayName) is enabled before dictation."
            : "\(displayName) is active and ready."
    }

    var activeLabel: String {
        purpose == .voiceCleaning ? "Cleaning Enabled" : "Active"
    }

    var useLabel: String {
        purpose == .voiceCleaning ? "Use Cleaner" : "Use Model"
    }

    var installLabel: String {
        purpose == .voiceCleaning ? "Install & Enable" : "Install"
    }

    var speedSignalLevel: Int {
        benchmark?.speed?.level ?? 0
    }

    var qualityLabel: String {
        benchmark?.quality.label ?? "Unrated"
    }

    var speedLabel: String {
        benchmark?.speed?.label ?? "Unrated"
    }

    var qualityScore: Int? {
        benchmark?.quality.score
    }

    var speedScore: Int? {
        benchmark?.speed?.score
    }

    var qualityEvidenceDescription: String? {
        guard let quality = benchmark?.quality else {
            return nil
        }
        return "\(quality.score)/100 • \(quality.label) • \(quality.speechItems) speech cases"
    }

    var wordErrorRateDescription: String {
        benchmark?.quality.components.map {
            "\(Self.benchmarkComponentName($0.id)) \(Self.percent($0.wordErrorRate))"
        }.joined(separator: " • ") ?? "Unrated"
    }

    var noSpeechEvidenceDescription: String {
        guard let quality = benchmark?.quality else {
            return "Unrated"
        }
        return "\(quality.noSpeechItems) cases • \(Self.percent(quality.noSpeechFalsePositiveRate)) false positives"
    }

    var speedEvidenceDescription: String? {
        guard let speed = benchmark?.speed else {
            if benchmark?.speedUnratedReason != nil {
                return "Unrated — repeated-run p95 was unstable"
            }
            return nil
        }
        return "\(speed.score)/100 • p50 \(speed.p50ReleaseToFinalMs) ms • p95 \(speed.p95ReleaseToFinalMs) ms • p95 RTF \(String(format: "%.3f", speed.p95RealTimeFactor))"
    }

    var benchmarkProvenanceDescription: String? {
        guard let benchmark else {
            return nil
        }
        return "\(benchmark.measuredAt) • \(benchmark.referenceHost.chip) • \(benchmark.referenceHost.operatingSystem)"
    }

    var benchmarkPolicyDescription: String {
        guard let benchmark else {
            return "Unrated"
        }
        return "\(benchmark.policyID) • \(benchmark.runCount) runs • suite \(benchmark.suiteIndexSHA256.prefix(12)) • source \(benchmark.sourceRevision.prefix(12))"
    }

    var benchmarkRuntimeDescription: String {
        guard let benchmark else {
            return "Unrated"
        }
        return "\(benchmark.engine) • \(benchmark.engineVersion) • \(benchmark.computeBackend)"
    }

    private static func supportTier(for tier: String) -> String {
        switch tier.lowercased() {
        case "balanced", "recommended": "Recommended"
        case "fast": "Fast"
        case "accurate": "Accurate"
        case "specialist": "Specialist"
        case "experimental": "Experimental"
        case "custom": "Custom"
        default: "Experimental"
        }
    }

    private static func benchmarkComponentName(_ id: String) -> String {
        switch id {
        case "open-asr-english-nightly-v1": "Open ASR"
        case "edacc-english-nightly-v1": "EdAcc"
        case "berst-english-nightly-v1": "BERSt"
        default: id
        }
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private static func fallbackFinalization(for tier: String) -> String {
        switch tier.lowercased() {
        case "fast": "Fastest available tier"
        case "balanced", "recommended": "Near-instant after release"
        case "accurate": "May take longer for higher accuracy"
        case "specialist": "Varies by specialist model"
        default: "Experimental; benchmark data incomplete"
        }
    }

    private static func artifactFormat(for model: ModelEntry) -> ModelArtifactFormat {
        if model.runtime.engine == .mlxAudio {
            return .mlx
        }
        if model.files.contains(where: { $0.filename.lowercased().hasSuffix(".gguf") }) {
            return .gguf
        }
        return .other
    }

    private static func artifactFormat(
        for format: ModelArtifactContainerFormat
    ) -> ModelArtifactFormat {
        switch format {
        case .mlx:
            .mlx
        case .gguf:
            .gguf
        case .ggml, .coreML, .onnx:
            .other
        }
    }

    private static func artifactPrecision(for model: ModelEntry) -> ModelArtifactPrecision {
        let searchableMetadata = ([
            model.id,
            model.displayName,
            model.description,
            model.runtime.variant,
            model.provenance.sourceFile,
        ] + model.files.map(\.filename))
            .joined(separator: " ")
            .lowercased()

        let precisionPatterns: [(ModelArtifactPrecision, [String])] = [
            (.thirtyTwoBit, ["fp32", "f32", "32-bit", "32bit"]),
            (.sixteenBit, ["fp16", "bf16", "f16", "16-bit", "16bit"]),
            (.eightBit, ["q8", "int8", "8-bit", "8bit"]),
            (.fiveBit, ["q5", "5-bit", "5bit"]),
            (.fourBit, ["q4", "int4", "4-bit", "4bit"]),
        ]

        return precisionPatterns.first { _, patterns in
            patterns.contains(where: searchableMetadata.contains)
        }?.0 ?? .other
    }

    private static func artifactPrecision(
        for format: ModelNumericFormat
    ) -> ModelArtifactPrecision {
        switch format {
        case .fp32, .f32:
            .thirtyTwoBit
        case .fp16, .f16, .bf16:
            .sixteenBit
        case .int8, .eightBit, .q8_0:
            .eightBit
        case .q5_k_m, .q5_1, .q5_0:
            .fiveBit
        case .q4_k_m:
            .fourBit
        }
    }

    private static func languageDescription(for languageCodes: [String]) -> String {
        if languageCodes == ["*"] {
            return "Language agnostic"
        }
        guard languageCodes.count == 1, let code = languageCodes.first else {
            return "\(languageCodes.count) languages"
        }
        return switch code.lowercased() {
        case "en": "English"
        case "ja": "Japanese"
        case "zh": "Chinese"
        default: code.uppercased()
        }
    }

    private static func publicSourceURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        return url
    }
}
