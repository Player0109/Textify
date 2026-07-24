import Foundation
import TextifyModels

enum ModelCatalogSort: String, CaseIterable, Identifiable {
    case catalog
    case quality
    case speed
    case downloadSize
    case installedSize

    var id: Self { self }

    var title: String {
        switch self {
        case .catalog: "Catalog"
        case .quality: "Quality"
        case .speed: "Speed"
        case .downloadSize: "Download Size"
        case .installedSize: "On Disk"
        }
    }
}

enum ModelCatalogSortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: Self { self }

    var title: String {
        switch self {
        case .ascending:
            "Ascending"
        case .descending:
            "Descending"
        }
    }

    var systemImage: String {
        switch self {
        case .ascending:
            "arrow.up"
        case .descending:
            "arrow.down"
        }
    }
}

enum ModelCatalogInstalledSizeStatus: Equatable {
    case calculating
    case measured
    case unavailable
}

enum ModelCatalogScope: String, CaseIterable, Identifiable {
    case all
    case installed

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            "All"
        case .installed:
            "Installed"
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

enum ModelCatalogCompatibilityFilter: String, CaseIterable, Identifiable {
    case compatible
    case requiresUpdate
    case incompatible
    case indeterminate

    var id: Self { self }

    var title: String {
        switch self {
        case .compatible:
            "Compatible"
        case .requiresUpdate:
            "Requires Update"
        case .incompatible:
            "Incompatible"
        case .indeterminate:
            "Indeterminate"
        }
    }
}

enum ModelCatalogStateFilter: String, CaseIterable, Identifiable {
    case notInstalled
    case installed
    case ready
    case active
    case needsRepair

    var id: Self { self }

    var title: String {
        switch self {
        case .notInstalled:
            "Not Installed"
        case .installed:
            "Installed"
        case .ready:
            "Ready"
        case .active:
            "Active"
        case .needsRepair:
            "Needs Repair"
        }
    }
}

enum ModelCatalogEvidenceFilter: String, CaseIterable, Identifiable {
    case quality
    case speed
    case qualityAndSpeed
    case unrated

    var id: Self { self }

    var title: String {
        switch self {
        case .quality:
            "Quality Rated"
        case .speed:
            "Speed Rated"
        case .qualityAndSpeed:
            "Quality + Speed Rated"
        case .unrated:
            "Unrated"
        }
    }
}

enum ModelCatalogQueryEmptyState: Equatable {
    case installed
    case search
    case filters
    case combined
    case validCatalog

    var title: String {
        switch self {
        case .installed:
            "No installed models"
        case .search:
            "No models match this search"
        case .filters:
            "No models match these filters"
        case .combined:
            "No models match this search and filters"
        case .validCatalog:
            "No curated models available"
        }
    }

    var detail: String {
        switch self {
        case .installed:
            "Installed shows only Exact Artifacts that currently consume storage on this Mac."
        case .search:
            "Try a different family, checkpoint, provider, language, format, or runtime term."
        case .filters:
            "Remove one or more filter tokens to broaden the catalog."
        case .combined:
            "Clear the search and filters to return to the full catalog."
        case .validCatalog:
            "Refresh the trusted catalog to check for newly curated models."
        }
    }

    var actionTitle: String {
        switch self {
        case .installed:
            "Show All Models"
        case .search:
            "Clear Search"
        case .filters:
            "Clear Filters"
        case .combined:
            "Clear Search and Filters"
        case .validCatalog:
            "Refresh Catalog"
        }
    }
}

enum ModelCatalogFilterTokenID: Equatable {
    case artifactFormat(ModelArtifactContainerFormat)
    case numericFormat(ModelNumericFormat)
    case runtime(TranscriptionEngine)
    case computeRoute(ModelComputeRoute)
    case language(String)
    case compatibility(ModelCatalogCompatibilityFilter)
    case state(ModelCatalogStateFilter)
    case evidence(ModelCatalogEvidenceFilter)
}

struct ModelCatalogFilterToken: Equatable {
    let id: ModelCatalogFilterTokenID
    let title: String
}

struct ModelCatalogQuery: Equatable {
    var scope: ModelCatalogScope = .all
    var searchText = ""
    var sort: ModelCatalogSort = .catalog
    var sortDirection: ModelCatalogSortDirection = .descending
    var artifactFormats: [ModelArtifactContainerFormat] = []
    var numericFormats: [ModelNumericFormat] = []
    var runtimes: [TranscriptionEngine] = []
    var computeRoutes: [ModelComputeRoute] = []
    var languages: [String] = []
    var compatibility: [ModelCatalogCompatibilityFilter] = []
    var states: [ModelCatalogStateFilter] = []
    var evidence: [ModelCatalogEvidenceFilter] = []
    var purpose: ModelPurpose?
    var revealedArtifactID: String?

    var hasUserFilters: Bool {
        hasSearch || hasAppliedFilters || scope == .installed
    }

    var hasSearch: Bool {
        !normalizedSearchTokens.isEmpty
    }

    var hasAppliedFilters: Bool {
        !artifactFormats.isEmpty
            || !numericFormats.isEmpty
            || !runtimes.isEmpty
            || !computeRoutes.isEmpty
            || !languages.isEmpty
            || !compatibility.isEmpty
            || !states.isEmpty
            || !evidence.isEmpty
    }

    var availableSorts: [ModelCatalogSort] {
        if scope == .installed {
            return [.catalog, .quality, .speed, .downloadSize, .installedSize]
        }
        return [.catalog, .quality, .speed, .downloadSize]
    }

    var emptyState: ModelCatalogQueryEmptyState {
        if hasSearch, hasAppliedFilters {
            return .combined
        }
        if hasSearch {
            return .search
        }
        if hasAppliedFilters {
            return .filters
        }
        if scope == .installed {
            return .installed
        }
        return .validCatalog
    }

    var ordinaryQuery: ModelCatalogQuery {
        var query = self
        query.revealedArtifactID = nil
        return query
    }

    var appliedFilterTokens: [ModelCatalogFilterToken] {
        artifactFormats.map {
            ModelCatalogFilterToken(
                id: .artifactFormat($0),
                title: ModelCatalogVariantTerminology.artifactFormat($0)
            )
        }
            + numericFormats.map {
                ModelCatalogFilterToken(
                    id: .numericFormat($0),
                    title: $0.rawValue
                )
            }
            + runtimes.map {
                ModelCatalogFilterToken(
                    id: .runtime($0),
                    title: ModelCatalogVariantTerminology.runtime($0)
                )
            }
            + computeRoutes.map {
                ModelCatalogFilterToken(
                    id: .computeRoute($0),
                    title: ModelCatalogVariantTerminology.computeRoute($0)
                )
            }
            + languages.map {
                ModelCatalogFilterToken(
                    id: .language($0),
                    title: Self.languageName($0)
                )
            }
            + compatibility.map {
                ModelCatalogFilterToken(id: .compatibility($0), title: $0.title)
            }
            + states.map {
                ModelCatalogFilterToken(id: .state($0), title: $0.title)
            }
            + evidence.map {
                ModelCatalogFilterToken(id: .evidence($0), title: $0.title)
            }
    }

    mutating func removeFilter(_ token: ModelCatalogFilterToken) {
        switch token.id {
        case let .artifactFormat(value):
            artifactFormats.removeAll { $0 == value }
        case let .numericFormat(value):
            numericFormats.removeAll { $0 == value }
        case let .runtime(value):
            runtimes.removeAll { $0 == value }
        case let .computeRoute(value):
            computeRoutes.removeAll { $0 == value }
        case let .language(value):
            languages.removeAll { $0 == value }
        case let .compatibility(value):
            compatibility.removeAll { $0 == value }
        case let .state(value):
            states.removeAll { $0 == value }
        case let .evidence(value):
            evidence.removeAll { $0 == value }
        }
    }

    mutating func clearSearch() {
        searchText = ""
    }

    mutating func clearFilters() {
        artifactFormats = []
        numericFormats = []
        runtimes = []
        computeRoutes = []
        languages = []
        compatibility = []
        states = []
        evidence = []
    }

    mutating func resetDiscovery() {
        scope = .all
        searchText = ""
        sort = .catalog
        sortDirection = .descending
        clearFilters()
        dismissReveal()
    }

    mutating func reveal(artifactID: String) {
        revealedArtifactID = artifactID
    }

    mutating func dismissReveal() {
        revealedArtifactID = nil
    }

    func matches(
        artifact: ModelCatalogExactArtifactPresentation,
        checkpoint: ModelCatalogCheckpointPresentation,
        family: ModelCatalogFamilyPresentation
    ) -> Bool {
        let row = artifact.row
        guard matchesCommon(row),
              artifactFormats.isEmpty
                || artifactFormats.contains(artifact.metadata.artifactFormat),
              numericFormats.isEmpty
                || numericFormats.contains(artifact.metadata.numericFormat),
              runtimes.isEmpty || runtimes.contains(artifact.metadata.runtime),
              computeRoutes.isEmpty
                || computeRoutes.contains(artifact.metadata.computeRoute),
              matchesSearch(searchTerms(
                artifact: artifact,
                checkpoint: checkpoint,
                family: family
              ))
        else {
            return false
        }
        return true
    }

    func matchesStandalone(_ row: ModelCatalogRowPresentation) -> Bool {
        matchesCommon(row)
            && artifactFormats.isEmpty
            && numericFormats.isEmpty
            && computeRoutes.isEmpty
            && (runtimes.isEmpty
                || row.operationalModel.map { runtimes.contains($0.runtime.engine) } == true)
            && matchesSearch([
                row.id,
                row.model.displayName,
                row.model.description,
                row.model.sourceName,
                row.model.languageDescription,
                row.model.engineName,
                row.model.artifactName,
            ])
    }

    func stableSort<T>(
        _ values: [(offset: Int, element: T)],
        value: (T) -> Int64?
    ) -> [T] {
        values.sorted { lhs, rhs in
            let left = value(lhs.element)
            let right = value(rhs.element)
            switch (left, right) {
            case (nil, nil):
                return lhs.offset < rhs.offset
            case (nil, _):
                return false
            case (_, nil):
                return true
            case let (left?, right?) where left != right:
                return sortDirection == .ascending ? left < right : left > right
            case (_?, _?):
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private var normalizedSearchTokens: [String] {
        Self.normalized(searchText)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private func matchesCommon(_ row: ModelCatalogRowPresentation) -> Bool {
        (purpose == nil || row.model.purpose == purpose)
            && (scope != .installed || row.isInstalled)
            && matchesLanguages(row)
            && matchesCompatibility(row.compatibility)
            && matchesState(row)
            && matchesEvidence(row.model)
    }

    private func matchesLanguages(_ row: ModelCatalogRowPresentation) -> Bool {
        guard !languages.isEmpty else {
            return true
        }
        guard let supported = row.operationalModel?.capabilities.languages else {
            return false
        }
        return languages.contains { language in
            supported.contains("*") || supported.contains {
                $0.caseInsensitiveCompare(language) == .orderedSame
            }
        }
    }

    private func matchesCompatibility(
        _ value: ModelCatalogCompatibility
    ) -> Bool {
        compatibility.isEmpty || compatibility.contains {
            switch ($0, value) {
            case (.compatible, .compatible),
                 (.requiresUpdate, .requiresAppUpdate),
                 (.requiresUpdate, .requiresMacOSUpdate),
                 (.incompatible, .incompatible),
                 (.indeterminate, .indeterminate):
                true
            default:
                false
            }
        }
    }

    private func matchesState(_ row: ModelCatalogRowPresentation) -> Bool {
        states.isEmpty || states.contains {
            switch $0 {
            case .notInstalled:
                !row.isInstalled
            case .installed:
                row.isInstalled
            case .ready:
                row.stateTokens.contains(.ready)
            case .active:
                row.isActive
            case .needsRepair:
                row.stateTokens.contains(.needsRepair)
            }
        }
    }

    private func matchesEvidence(_ model: ProductionModelPresentation) -> Bool {
        evidence.isEmpty || evidence.contains {
            switch $0 {
            case .quality:
                model.qualityScore != nil
            case .speed:
                model.speedScore != nil
            case .qualityAndSpeed:
                model.qualityScore != nil && model.speedScore != nil
            case .unrated:
                model.qualityScore == nil && model.speedScore == nil
            }
        }
    }

    private func matchesSearch(_ values: [String]) -> Bool {
        guard !normalizedSearchTokens.isEmpty else {
            return true
        }
        let haystack = Self.normalized(values.joined(separator: " "))
        return normalizedSearchTokens.allSatisfy(haystack.contains)
    }

    private func searchTerms(
        artifact: ModelCatalogExactArtifactPresentation,
        checkpoint: ModelCatalogCheckpointPresentation,
        family: ModelCatalogFamilyPresentation
    ) -> [String] {
        let model = artifact.row.operationalModel
        let languages = model?.capabilities.languages ?? []
        return [
            family.id,
            family.metadata.presentation.displayName,
            family.metadata.presentation.description,
            family.metadata.presentation.provider.id,
            family.metadata.presentation.provider.displayName,
            checkpoint.id,
            checkpoint.metadata.presentation.displayName,
            checkpoint.metadata.presentation.description,
            artifact.id,
            artifact.metadata.presentation.displayName,
            artifact.metadata.artifactFormat.rawValue,
            ModelCatalogVariantTerminology.artifactFormat(
                artifact.metadata.artifactFormat
            ),
            artifact.metadata.numericFormat.rawValue,
            artifact.metadata.runtime.rawValue,
            ModelCatalogVariantTerminology.runtime(artifact.metadata.runtime),
            artifact.metadata.computeRoute.rawValue,
            ModelCatalogVariantTerminology.computeRoute(
                artifact.metadata.computeRoute
            ),
            artifact.row.model.displayName,
            artifact.row.model.description,
            model?.provenance.sourceName ?? "",
            model?.provenance.originalModelName ?? "",
        ] + languages + languages.map(Self.languageName)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func languageName(_ code: String) -> String {
        if code == "*" {
            return "All Languages"
        }
        return Locale(identifier: "en_US").localizedString(
            forLanguageCode: code
        )?.capitalized ?? code.uppercased()
    }
}

extension ModelCatalogCompatibilityResolver {
    static func current(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> ModelCatalogCompatibilityResolver {
        let operatingSystem = processInfo.operatingSystemVersion
        return ModelCatalogCompatibilityResolver(
            context: ModelCatalogCompatibilityContext(
                appVersion: bundle.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? "1.1.0",
                macOSVersion: [
                    operatingSystem.majorVersion,
                    operatingSystem.minorVersion,
                    operatingSystem.patchVersion,
                ].map(String.init).joined(separator: "."),
                architecture: .arm64,
                physicalMemoryBytes: Int64(clamping: processInfo.physicalMemory)
            )
        )
    }
}

enum ModelCatalogPurposeDestination: Equatable {
    case transcription
    case voiceCleaning

    var purpose: ModelPurpose {
        switch self {
        case .transcription:
            return .transcription
        case .voiceCleaning:
            return .voiceCleaning
        }
    }

    var title: String {
        switch self {
        case .transcription:
            return "Transcription Models"
        case .voiceCleaning:
            return "Voice Cleaning"
        }
    }

    var subtitle: String {
        switch self {
        case .transcription:
            return "Choose the local model that turns speech into text."
        case .voiceCleaning:
            return "Optionally reduce background noise before transcription."
        }
    }

    var emptyTitle: String {
        switch self {
        case .transcription:
            return "No transcription models are available"
        case .voiceCleaning:
            return "No voice-cleaning models are available"
        }
    }

    var emptyDetail: String {
        switch self {
        case .transcription:
            return "Refresh the signed catalog or update Textify to find a compatible transcription model."
        case .voiceCleaning:
            return "Voice cleaning is optional. Refresh the signed catalog or continue dictating with raw audio."
        }
    }

    var unavailableTitle: String {
        switch self {
        case .transcription:
            return "Transcription catalog unavailable"
        case .voiceCleaning:
            return "Voice-cleaning catalog unavailable"
        }
    }

    var unavailableDetail: String {
        switch self {
        case .transcription:
            return "Textify could not load the trusted catalog. Installed transcription models remain available offline."
        case .voiceCleaning:
            return "Textify could not load the trusted catalog. Voice cleaning is optional, and installed cleaners remain available offline."
        }
    }

    var unavailableActionTitle: String {
        "Refresh Catalog"
    }
}

enum OnboardingModelAction: Equatable {
    case install
    case reinstall
    case cancelInstall
    case retryInstall
    case activate
    case active
    case unavailable
}

struct OnboardingModelCatalog: Equatable {
    let choices: [ModelCatalogRowPresentation]
    let selectedModelID: String?
    let selectionNotice: String?

    init(
        experience: ModelCatalogExperience,
        selectedModelID: String? = nil
    ) {
        choices = experience.rows
        if let selectedModelID,
           choices.contains(where: { $0.id == selectedModelID }) {
            self.selectedModelID = selectedModelID
        } else if let activeModelID = choices.first(where: \.isActive)?.id {
            self.selectedModelID = activeModelID
        } else {
            self.selectedModelID = experience.families
                .flatMap(\.checkpoints)
                .compactMap(\.defaultInstallArtifact)
                .first?
                .id
                ?? choices.first(where: {
                    !$0.isRevoked
                        && $0.compatibility.allowsModelOperations
                })?.id
                ?? choices.first(where: { !$0.isRevoked })?.id
                ?? choices.first?.id
        }
        selectionNotice = Self.selectionNotice(
            for: self.selectedModelID,
            in: experience
        )
    }

    func action(for modelID: String) -> OnboardingModelAction? {
        guard let row = choices.first(where: { $0.id == modelID }) else {
            return nil
        }
        if row.isRevoked {
            return .unavailable
        }
        if row.actions.contains(.cancelInstall) {
            return .cancelInstall
        }
        if row.isActive {
            return .active
        }
        guard row.compatibility.allowsModelOperations else {
            return .unavailable
        }
        if row.actions.contains(.retryInstall) {
            return .retryInstall
        }
        if row.isInstalled {
            return row.actions.contains(.use) ? .activate : .reinstall
        }
        return .install
    }

    func transferState(for modelID: String?) -> DownloadState? {
        guard let modelID else {
            return nil
        }
        return choices.first { $0.id == modelID }?.installState
    }

    private static func selectionNotice(
        for selectedModelID: String?,
        in experience: ModelCatalogExperience
    ) -> String? {
        guard let selectedModelID else {
            return nil
        }
        for checkpoint in experience.families.flatMap(\.checkpoints) {
            if let resolution = checkpoint.resolution,
               let fallback = resolution.fallback,
               fallback.fallbackArtifactID == selectedModelID,
               let recommended = checkpoint.referenceArtifact,
               let selected = checkpoint.defaultInstallArtifact {
                return "Recommended \(recommended.metadata.presentation.displayName) "
                    + "(\(recommended.id)) is incompatible: "
                    + resolution.recommendedCompatibility.catalogExplanation
                    + " Textify will install signed fallback "
                    + "\(selected.metadata.presentation.displayName) (\(selected.id)), using "
                    + ModelCatalogVariantTerminology.runtime(selected.metadata.runtime)
                    + " with "
                    + ModelCatalogVariantTerminology.computeRoute(
                        selected.metadata.computeRoute
                    )
                    + "."
            }
        }
        guard let selected = experience.rows.first(
            where: { $0.id == selectedModelID }
        ),
              !selected.compatibility.allowsModelOperations
        else {
            return nil
        }
        return selected.compatibility.catalogExplanation
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

enum ModelCatalogManagedReadiness: Equatable {
    case installed
    case ready
    case needsRepair
    case verificationRequired
}

enum ModelCatalogStateToken: Equatable {
    case revoked
    case installed
    case ready
    case active
    case incompatible
    case needsRepair
    case verificationRequired

    var title: String {
        switch self {
        case .revoked:
            return "Revoked"
        case .installed:
            return "Installed"
        case .ready:
            return "Ready"
        case .active:
            return "Active"
        case .incompatible:
            return "Incompatible"
        case .needsRepair:
            return "Needs Repair"
        case .verificationRequired:
            return "Verify Required"
        }
    }
}

struct ModelCatalogRowPresentation: Equatable, Identifiable {
    let model: ProductionModelPresentation
    let operationalModel: ModelEntry?
    let installedRecord: InstalledModelRecord?
    let storageInventory: ModelStorageArtifactInventory?
    let installedSizeStatus: ModelCatalogInstalledSizeStatus
    let onDiskBytes: Int64?
    let sizeLabel: String
    let sizeDescription: String
    let compatibility: ModelCatalogCompatibility
    let placement: ModelArtifactPlacement?
    let isRevoked: Bool
    let isInstalled: Bool
    let isActive: Bool
    let install: ModelCatalogInstallPresentation?
    let stateTokens: [ModelCatalogStateToken]
    let actions: Set<ModelCatalogRowAction>

    var id: String {
        model.id
    }

    var installState: DownloadState? {
        install?.state
    }
}

struct ModelCatalogFilterOptions: Equatable {
    let artifactFormats: [ModelArtifactContainerFormat]
    let numericFormats: [ModelNumericFormat]
    let runtimes: [TranscriptionEngine]
    let computeRoutes: [ModelComputeRoute]
    let languages: [String]

    static let empty = ModelCatalogFilterOptions(
        artifactFormats: [],
        numericFormats: [],
        runtimes: [],
        computeRoutes: [],
        languages: []
    )
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
    let defaultInstallArtifact: ModelCatalogExactArtifactPresentation?
    let resolution: ModelCatalogCheckpointResolution?
    let installedOnDiskBytes: Int64?

    var id: String {
        metadata.id
    }

    static func aggregateInstalledOnDiskBytes(
        _ artifacts: [ModelCatalogExactArtifactPresentation]
    ) -> Int64? {
        let installedArtifacts = artifacts.filter(\.row.isInstalled)
        guard !installedArtifacts.isEmpty,
              installedArtifacts.allSatisfy({ $0.row.onDiskBytes != nil })
        else {
            return nil
        }
        return installedArtifacts.compactMap(\.row.onDiskBytes).reduce(0, +)
    }
}

extension ModelCatalogCheckpointPresentation {
    var presentedReferenceArtifact: ModelCatalogExactArtifactPresentation? {
        referenceArtifact.flatMap {
            $0.row.isRevoked ? nil : $0
        }
    }

    func presentsRecommendation(
        _ artifact: ModelCatalogExactArtifactPresentation
    ) -> Bool {
        !artifact.row.isRevoked
            && metadata.recommendedArtifactID == artifact.id
    }

    func presentsFallback(
        _ artifact: ModelCatalogExactArtifactPresentation
    ) -> Bool {
        !artifact.row.isRevoked
            && resolution?.fallback?.fallbackArtifactID == artifact.id
    }
}

struct ModelCatalogExactArtifactPresentation: Equatable, Identifiable {
    let metadata: ModelExactArtifactPresentationNode
    let row: ModelCatalogRowPresentation

    var id: String {
        metadata.id
    }
}

enum ModelCatalogPinnedRevealPresentation: Equatable {
    case catalogArtifact(
        family: ModelCatalogFamilyPresentation,
        checkpoint: ModelCatalogCheckpointPresentation,
        artifact: ModelCatalogExactArtifactPresentation
    )
    case standaloneArtifact(ModelCatalogRowPresentation)
    case unavailableArtifact(String)

    var artifactID: String {
        switch self {
        case let .catalogArtifact(_, _, artifact):
            return artifact.id
        case let .standaloneArtifact(row):
            return row.id
        case let .unavailableArtifact(artifactID):
            return artifactID
        }
    }
}

enum ModelCatalogHierarchyRowID: Equatable, Hashable {
    case family(String)
    case checkpoint(String)
    case exactArtifact(String)
    case standaloneArtifact(String)
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
        case standaloneArtifact(ModelCatalogRowPresentation)
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
        case let .standaloneArtifact(row):
            .standaloneArtifact(row.id)
        }
    }
}

struct ModelCatalogHierarchyState: Equatable {
    private(set) var selection: ModelCatalogHierarchySelection?
    private(set) var expandedCheckpointIDs: Set<String>
    private(set) var focusedRowID: ModelCatalogHierarchyRowID?
    private(set) var scrollAnchorID: ModelCatalogHierarchyRowID?

    init(
        selection: ModelCatalogHierarchySelection? = nil,
        expandedCheckpointIDs: Set<String> = [],
        focusedRowID: ModelCatalogHierarchyRowID? = nil,
        scrollAnchorID: ModelCatalogHierarchyRowID? = nil
    ) {
        self.selection = selection
        self.expandedCheckpointIDs = expandedCheckpointIDs
        self.focusedRowID = focusedRowID
        self.scrollAnchorID = scrollAnchorID
    }

    mutating func select(_ selection: ModelCatalogHierarchySelection) {
        self.selection = selection
    }

    mutating func focus(_ rowID: ModelCatalogHierarchyRowID?) {
        focusedRowID = rowID
    }

    mutating func scroll(to rowID: ModelCatalogHierarchyRowID?) {
        scrollAnchorID = rowID
    }

    mutating func toggleExpansion(of checkpoint: ModelCatalogCheckpointPresentation) {
        if expandedCheckpointIDs.remove(checkpoint.id) != nil {
            if case let .exactArtifact(selectedArtifactID) = selection,
               checkpoint.artifacts.contains(where: { $0.id == selectedArtifactID }) {
                selection = .checkpoint(checkpoint.id)
            }
            let childRowIDs = Set(
                checkpoint.artifacts.map {
                    ModelCatalogHierarchyRowID.exactArtifact($0.id)
                }
            )
            if let focusedRowID, childRowIDs.contains(focusedRowID) {
                self.focusedRowID = .checkpoint(checkpoint.id)
            }
            if let scrollAnchorID, childRowIDs.contains(scrollAnchorID) {
                self.scrollAnchorID = .checkpoint(checkpoint.id)
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

        let visibleRowIDs = Set(visibleRows(in: experience).map(\.id))
        if let focusedRowID, !visibleRowIDs.contains(focusedRowID) {
            self.focusedRowID = nil
        }
        if let scrollAnchorID, !visibleRowIDs.contains(scrollAnchorID) {
            self.scrollAnchorID = nil
        }
    }

    func visibleRows(in experience: ModelCatalogExperience) -> [ModelCatalogHierarchyRow] {
        let hierarchyRows = experience.families.flatMap { family in
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
        let representedModelIDs = Set(
            experience.families
                .flatMap(\.checkpoints)
                .flatMap(\.artifacts)
                .map(\.id)
        )
        let standaloneRows = experience.rows
            .filter { !representedModelIDs.contains($0.id) }
            .map {
                ModelCatalogHierarchyRow(
                    content: .standaloneArtifact($0),
                    isExpanded: false
                )
            }
        return hierarchyRows + standaloneRows
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

struct ModelDownloadAttemptPresentation: Equatable, Identifiable {
    let attempt: ModelInstallQueueAttempt
    private let retainedDataRemovalIsBlocked: Bool

    init(
        attempt: ModelInstallQueueAttempt,
        retainedDataRemovalIsBlocked: Bool = false
    ) {
        self.attempt = attempt
        self.retainedDataRemovalIsBlocked =
            retainedDataRemovalIsBlocked
    }

    var id: String {
        attempt.id
    }

    var artifactID: String {
        attempt.artifactID
    }

    var state: DownloadState {
        attempt.state
    }

    var statusTitle: String {
        ModelInstallProgressPresentation.title(for: state)
    }

    var detailText: String {
        if let retainedData = attempt.resumableData,
           state.phase == .revoked {
            let size = ByteCountFormatter.string(
                fromByteCount: retainedData.validatedBytes,
                countStyle: .file
            )
            return "\(size) of retained partial data is not resumable and can be removed."
        }
        return ModelInstallProgressPresentation.detailText(for: state)
    }

    var progressValue: Double {
        ModelInstallProgressPresentation.progressValue(for: state)
    }

    var percentText: String? {
        ModelInstallProgressPresentation.percentText(for: state)
    }

    var revealRequest: ModelCatalogRevealRequest {
        ModelCatalogRevealRequest(
            artifactID: attempt.artifactID,
            purpose: attempt.purpose
        )
    }

    var canCancel: Bool {
        ModelInstallRowPresentation.offersCancel(for: state)
    }

    var canPause: Bool {
        state.phase == .downloading
    }

    var canResume: Bool {
        state.phase == .paused
    }

    var canRetry: Bool {
        ModelInstallRowPresentation.offersRetry(for: state)
    }

    var canRemoveRetainedData: Bool {
        state.phase == .revoked
            && attempt.resumableData != nil
            && !retainedDataRemovalIsBlocked
    }
}

struct ModelDownloadsPresentation: Equatable {
    let active: [ModelDownloadAttemptPresentation]
    let pending: [ModelDownloadAttemptPresentation]
    let history: [ModelDownloadAttemptPresentation]

    init(attempts: [ModelInstallQueueAttempt]) {
        let nonterminalArtifactIDs = Set(
            attempts.lazy.filter {
                !$0.state.phase.isTerminal
            }.map(\.artifactID)
        )
        let rows = attempts.map {
            ModelDownloadAttemptPresentation(
                attempt: $0,
                retainedDataRemovalIsBlocked:
                    nonterminalArtifactIDs.contains($0.artifactID)
            )
        }
        active = rows.filter { $0.state.phase.isPipelineActive }
        pending = rows.filter {
            !$0.state.phase.isTerminal && !$0.state.phase.isPipelineActive
        }
        history = rows.filter { $0.state.phase.isTerminal }
    }

    var nonterminalCount: Int {
        active.count + pending.count
    }
}

struct ModelCatalogStorageSummaryPresentation: Equatable {
    struct Fact: Equatable {
        let label: String
        let value: String
    }

    let facts: [Fact]

    init(
        state: ModelStorageInventoryLoadState,
        installedCount: Int
    ) {
        facts = [
            Fact(
                label: "Installed",
                value: Self.installedCount(
                    for: state,
                    fallback: installedCount
                )
            ),
            Fact(
                label: "Installed Model Storage",
                value: Self.value(
                    for: state,
                    bytes: { $0.installedModelStorageBytes }
                )
            ),
            Fact(
                label: "Download Storage",
                value: Self.value(
                    for: state,
                    bytes: { $0.downloadStorageBytes }
                )
            ),
            Fact(
                label: "Other Model Data",
                value: Self.value(
                    for: state,
                    bytes: { $0.otherModelDataBytes }
                )
            ),
            Fact(
                label: "Total Managed Storage",
                value: Self.value(
                    for: state,
                    bytes: { $0.totalManagedStorageBytes }
                )
            ),
            Fact(
                label: "Available Space",
                value: Self.value(
                    for: state,
                    bytes: { $0.availableSpaceBytes }
                )
            ),
        ]
    }

    private static func installedCount(
        for state: ModelStorageInventoryLoadState,
        fallback: Int
    ) -> String {
        guard case let .available(_, snapshot) = state else {
            return String(fallback)
        }
        return String(snapshot.summary.installedArtifactCount)
    }

    private static func value(
        for state: ModelStorageInventoryLoadState,
        bytes: (ModelStorageInventorySummary) -> Int64?
    ) -> String {
        switch state {
        case .calculating:
            return "Calculating"
        case .unavailable:
            return "Size Unavailable"
        case let .available(_, snapshot):
            guard let byteCount = bytes(snapshot.summary) else {
                return "Size Unavailable"
            }
            return "About " + ByteCountFormatter.string(
                fromByteCount: byteCount,
                countStyle: .file
            )
        }
    }
}

struct ModelCatalogExperience: Equatable {
    let rows: [ModelCatalogRowPresentation]
    let families: [ModelCatalogFamilyPresentation]
    let filterOptions: ModelCatalogFilterOptions
    let pinnedReveal: ModelCatalogPinnedRevealPresentation?
    let sizeLabel: String
    private let inspectorFamilies: [ModelCatalogFamilyPresentation]
    private let inspectorRowsByID: [String: ModelCatalogRowPresentation]

    init(
        trustedModels: [ModelEntry],
        installedRecords: [InstalledModelRecord],
        activePreferences: ModelCatalogActivePreferences,
        transferState: DownloadState?,
        revocationOverlay: ModelRevocationOverlay = .init(),
        managedReadinessByModelID: [String: ModelCatalogManagedReadiness] = [:],
        onDiskBytesByModelID: [String: Int64] = [:],
        storageInventoryByModelID: [String: ModelStorageArtifactInventory] = [:],
        installedSizeStatus: ModelCatalogInstalledSizeStatus = .measured,
        query: ModelCatalogQuery = ModelCatalogQuery()
    ) {
        self.init(
            trustedModels: trustedModels,
            presentationGraph: nil,
            artifactAliases: [],
            installedRecords: installedRecords,
            activePreferences: activePreferences,
            transferStatesByModelID: Self.transferStatesByModelID(
                from: transferState
            ),
            revocationOverlay: revocationOverlay,
            managedReadinessByModelID: managedReadinessByModelID,
            onDiskBytesByModelID: onDiskBytesByModelID,
            storageInventoryByModelID: storageInventoryByModelID,
            installedSizeStatus: installedSizeStatus,
            query: query
        )
    }

    init(
        trustedManifest: ModelManifest?,
        compatibilityResolver: ModelCatalogCompatibilityResolver? = nil,
        installedRecords: [InstalledModelRecord],
        activePreferences: ModelCatalogActivePreferences,
        transferState: DownloadState?,
        revocationOverlay: ModelRevocationOverlay = .init(),
        managedReadinessByModelID: [String: ModelCatalogManagedReadiness] = [:],
        onDiskBytesByModelID: [String: Int64] = [:],
        storageInventoryByModelID: [String: ModelStorageArtifactInventory] = [:],
        installedSizeStatus: ModelCatalogInstalledSizeStatus = .measured,
        query: ModelCatalogQuery = ModelCatalogQuery()
    ) {
        let compatibilityByModelID = compatibilityResolver?
            .compatibilityByModelID(in: trustedManifest) ?? [:]
        let checkpointResolutions = compatibilityResolver?
            .checkpointResolutions(in: trustedManifest) ?? [:]
        self.init(
            trustedModels: trustedManifest?.models ?? [],
            presentationGraph: trustedManifest?.presentationGraph,
            artifactAliases: trustedManifest?.artifactAliases ?? [],
            compatibilityByModelID: compatibilityByModelID,
            checkpointResolutions: checkpointResolutions,
            installedRecords: installedRecords,
            activePreferences: activePreferences,
            transferStatesByModelID: Self.transferStatesByModelID(
                from: transferState
            ),
            revocationOverlay: revocationOverlay,
            managedReadinessByModelID: managedReadinessByModelID,
            onDiskBytesByModelID: onDiskBytesByModelID,
            storageInventoryByModelID: storageInventoryByModelID,
            installedSizeStatus: installedSizeStatus,
            query: query
        )
    }

    init(
        trustedManifest: ModelManifest?,
        compatibilityResolver: ModelCatalogCompatibilityResolver? = nil,
        installedRecords: [InstalledModelRecord],
        activePreferences: ModelCatalogActivePreferences,
        transferStatesByModelID: [String: DownloadState],
        revocationOverlay: ModelRevocationOverlay = .init(),
        managedReadinessByModelID: [String: ModelCatalogManagedReadiness] = [:],
        onDiskBytesByModelID: [String: Int64] = [:],
        storageInventoryByModelID: [String: ModelStorageArtifactInventory] = [:],
        installedSizeStatus: ModelCatalogInstalledSizeStatus = .measured,
        query: ModelCatalogQuery = ModelCatalogQuery()
    ) {
        let compatibilityByModelID = compatibilityResolver?
            .compatibilityByModelID(in: trustedManifest) ?? [:]
        let checkpointResolutions = compatibilityResolver?
            .checkpointResolutions(in: trustedManifest) ?? [:]
        self.init(
            trustedModels: trustedManifest?.models ?? [],
            presentationGraph: trustedManifest?.presentationGraph,
            artifactAliases: trustedManifest?.artifactAliases ?? [],
            compatibilityByModelID: compatibilityByModelID,
            checkpointResolutions: checkpointResolutions,
            installedRecords: installedRecords,
            activePreferences: activePreferences,
            transferStatesByModelID: transferStatesByModelID,
            revocationOverlay: revocationOverlay,
            managedReadinessByModelID: managedReadinessByModelID,
            onDiskBytesByModelID: onDiskBytesByModelID,
            storageInventoryByModelID: storageInventoryByModelID,
            installedSizeStatus: installedSizeStatus,
            query: query
        )
    }

    private init(
        trustedModels: [ModelEntry],
        presentationGraph: ModelCatalogPresentationGraph?,
        artifactAliases: [ModelArtifactAlias],
        compatibilityByModelID: [String: ModelCatalogCompatibility] = [:],
        checkpointResolutions: [String: ModelCatalogCheckpointResolution] = [:],
        installedRecords: [InstalledModelRecord],
        activePreferences: ModelCatalogActivePreferences,
        transferStatesByModelID: [String: DownloadState],
        revocationOverlay: ModelRevocationOverlay,
        managedReadinessByModelID: [String: ModelCatalogManagedReadiness],
        onDiskBytesByModelID: [String: Int64],
        storageInventoryByModelID: [String: ModelStorageArtifactInventory],
        installedSizeStatus: ModelCatalogInstalledSizeStatus,
        query: ModelCatalogQuery
    ) {
        let trustedManifest = ModelManifest(
            manifestVersion: presentationGraph == nil ? 1 : 3,
            generatedAt: "1970-01-01T00:00:00Z",
            models: trustedModels,
            presentationGraph: presentationGraph,
            artifactAliases: artifactAliases
        )
        let placementSnapshot = ModelArtifactPlacementResolver().reconcile(
            records: installedRecords,
            trustedManifest: trustedManifest
        )
        let installedRecords = placementSnapshot.records
        let sizeLabel = query.scope == .installed ? "On Disk" : "Download Size"
        self.sizeLabel = sizeLabel
        let signedArtifactsByID = presentationGraph?.artifacts.reduce(
            into: [String: ModelExactArtifactPresentationNode]()
        ) {
            $0[$1.id] = $1
        } ?? [:]
        let trustedCatalog = trustedModels.map {
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

        let orderedCatalog = trustedCatalog + localCatalog
        let allRows = orderedCatalog.map { model in
            let installedModel = installedByID[model.id]
            let installedRecord = installedRecordsByID[model.id]
            let isInstalled = installedIDs.contains(model.id)
            let isRevoked = installedRecord.map {
                revocationOverlay.isRevoked(
                    record: $0,
                    trustedManifest: trustedManifest
                )
            } ?? trustedModelsByID[model.id].map {
                revocationOverlay.isRevoked(
                    model: $0,
                    trustedManifest: trustedManifest
                )
            } ?? false
            let managedReadiness = isInstalled
                ? managedReadinessByModelID[model.id] ?? .ready
                : nil
            let activePurpose = installedModel?.purpose ?? model.purpose
            let isActive = isInstalled
                && activePreferences.contains(modelID: model.id, purpose: activePurpose)
            let installState = ModelInstallRowPresentation.state(
                for: model.id,
                from: transferStatesByModelID
            )
            return ModelCatalogRowPresentation(
                model: model,
                operationalModel: trustedModelsByID[model.id] ?? installedModel,
                installedRecord: installedRecord,
                storageInventory: storageInventoryByModelID[model.id],
                installedSizeStatus: installedSizeStatus,
                onDiskBytes: isInstalled ? onDiskBytesByModelID[model.id] : nil,
                sizeLabel: query.scope == .installed && isInstalled
                    ? "On Disk"
                    : "Download Size",
                sizeDescription: Self.sizeDescription(
                    model: model,
                    isInstalled: isInstalled,
                    onDiskBytes: onDiskBytesByModelID[model.id],
                    installedSizeStatus: installedSizeStatus,
                    scope: query.scope
                ),
                compatibility: compatibilityByModelID[model.id] ?? .compatible,
                placement: placementSnapshot.placement(
                    forArtifactID: model.id
                ),
                isRevoked: isRevoked,
                isInstalled: isInstalled,
                isActive: isActive,
                install: installState.map(ModelCatalogInstallPresentation.init),
                stateTokens: Self.stateTokens(
                    isRevoked: isRevoked,
                    isInstalled: isInstalled,
                    isActive: isActive,
                    managedReadiness: managedReadiness,
                    compatibility: compatibilityByModelID[model.id] ?? .compatible
                ),
                actions: Self.actions(
                    for: model,
                    isRevoked: isRevoked,
                    isInstalled: isInstalled,
                    isActive: isActive,
                    managedReadiness: managedReadiness,
                    installState: installState
                )
            )
        }
        let allFamilies = presentationGraph.map {
            Self.makeFamilyPresentations(
                graph: $0,
                rows: allRows,
                referenceRows: allRows,
                checkpointResolutions: checkpointResolutions
            )
        } ?? []
        inspectorFamilies = allFamilies
        inspectorRowsByID = allRows.reduce(
            into: [String: ModelCatalogRowPresentation]()
        ) {
            $0[$1.id] = $1
        }
        filterOptions = Self.makeFilterOptions(
            families: allFamilies,
            rows: allRows,
            purpose: query.purpose
        )
        pinnedReveal = Self.makePinnedReveal(
            artifactID: query.revealedArtifactID,
            families: allFamilies,
            rows: allRows
        )

        if presentationGraph != nil {
            let queriedFamilies = Self.queryFamilies(
                allFamilies,
                query: query
            )
            families = queriedFamilies
            let representedIDs = Set(
                allFamilies
                    .flatMap(\.checkpoints)
                    .flatMap(\.artifacts)
                    .map(\.id)
            )
            let standaloneRows = Self.queryStandaloneRows(
                allRows.filter { !representedIDs.contains($0.id) },
                query: query
            )
            rows = queriedFamilies
                .flatMap(\.checkpoints)
                .flatMap(\.artifacts)
                .map(\.row)
                + standaloneRows
        } else {
            families = []
            rows = Self.queryStandaloneRows(allRows, query: query)
        }
    }

    private static func transferStatesByModelID(
        from state: DownloadState?
    ) -> [String: DownloadState] {
        guard let state else {
            return [:]
        }
        return [state.modelID: state]
    }

    private static func sizeDescription(
        model: ProductionModelPresentation,
        isInstalled: Bool,
        onDiskBytes: Int64?,
        installedSizeStatus: ModelCatalogInstalledSizeStatus,
        scope: ModelCatalogScope
    ) -> String {
        guard scope == .installed, isInstalled else {
            return model.sizeDescription
        }
        switch installedSizeStatus {
        case .calculating:
            return "Calculating"
        case .unavailable:
            return "Size Unavailable"
        case .measured:
            guard let onDiskBytes else {
                return "Size Unavailable"
            }
            return "About " + ByteCountFormatter.string(
                fromByteCount: onDiskBytes,
                countStyle: .file
            )
        }
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
            guard let row = inspectorRowsByID[artifactID] else {
                return nil
            }
            return .exactArtifact(Self.standaloneArtifactInspector(row))
        }
    }

    private static func standaloneArtifactInspector(
        _ row: ModelCatalogRowPresentation
    ) -> ModelCatalogExactArtifactInspectorPresentation {
        let model = row.operationalModel
        return artifactInspector(
            row: row,
            identity: ArtifactInspectorIdentity(
                checkpointName: row.placement?.title ?? "Standalone Artifact",
                displayName: row.model.displayName,
                description: row.model.description,
                artifactFormat: row.model.artifactFormat.title,
                numericFormat: row.model.artifactPrecision.title,
                runtime: row.model.engineName,
                computeRoute: row.model.acceleratorName,
                compatibility: model.map {
                    "Textify \($0.minAppVersion)+ • \(row.model.requirements)"
                } ?? row.model.requirements,
                provenanceFallback: "Artifact provenance unavailable"
            )
        )
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
            referenceCompatibility: referenceArtifact.row.compatibility.catalogTitle,
            referenceCompatibilityExplanation: referenceArtifact.row.compatibility
                .catalogExplanation,
            defaultInstallArtifactID: checkpoint.defaultInstallArtifact?.id,
            defaultInstallArtifactName: checkpoint.defaultInstallArtifact?
                .metadata.presentation.displayName,
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

        return artifactInspector(
            row: artifact.row,
            identity: ArtifactInspectorIdentity(
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
                provenanceFallback: "Catalog provenance unavailable"
            )
        )
    }

    private static func artifactInspector(
        row: ModelCatalogRowPresentation,
        identity: ArtifactInspectorIdentity
    ) -> ModelCatalogExactArtifactInspectorPresentation {
        let model = row.operationalModel
        let provenance = model.map {
            "\($0.provenance.sourceName) • \($0.provenance.originalModelName) • "
                + "revision \($0.provenance.sourceRevision.prefix(12)) • "
                + $0.provenance.sourceFile
        } ?? identity.provenanceFallback
        let license = model.map {
            $0.licenses.map {
                "\($0.spdxId) — \($0.name) (\($0.scope))"
            }.joined(separator: " • ")
        } ?? "License metadata unavailable"
        return ModelCatalogExactArtifactInspectorPresentation(
            id: row.id,
            checkpointName: identity.checkpointName,
            displayName: identity.displayName,
            description: identity.description,
            artifactFormat: identity.artifactFormat,
            numericFormat: identity.numericFormat,
            runtime: identity.runtime,
            computeRoute: identity.computeRoute,
            compatibility: identity.compatibility,
            compatibilityStatus: row.compatibility.catalogTitle,
            compatibilityExplanation: row.compatibility.catalogExplanation,
            qualityEvidence: row.model.qualityEvidenceDescription ?? "Unrated",
            speedEvidence: row.model.speedEvidenceDescription ?? "Unrated",
            transferSize: model.map {
                ByteCountFormatter.string(
                    fromByteCount: $0.sizeBytes,
                    countStyle: .file
                )
            } ?? row.model.sizeDescription,
            localState: localState(for: row),
            provenance: provenance,
            license: license,
            sourceURL: row.model.sourceURL,
            canVerify: row.isInstalled,
            localDetails: row.storageInventory.map {
                ModelCatalogArtifactLocalDetails(inventory: $0)
            },
            localDetailsStatus: row.installedSizeStatus,
            verificationRequest: makeVerificationRequest(
                artifactID: row.id,
                model: model,
                installedRecord: row.installedRecord
            )
        )
    }

    private struct ArtifactInspectorIdentity {
        let checkpointName: String
        let displayName: String
        let description: String
        let artifactFormat: String
        let numericFormat: String
        let runtime: String
        let computeRoute: String
        let compatibility: String
        let provenanceFallback: String
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
        var titles = row.stateTokens.map(\.title)
        if let install = row.install {
            titles.append(install.title)
        }
        return titles.isEmpty
            ? "Not installed"
            : titles.joined(separator: " • ")
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
        return languageCodes.map(ModelCatalogQuery.languageName).joined(separator: ", ")
    }

    private static func queryFamilies(
        _ source: [ModelCatalogFamilyPresentation],
        query: ModelCatalogQuery
    ) -> [ModelCatalogFamilyPresentation] {
        let filtered: [ModelCatalogFamilyPresentation] = source.compactMap { family in
            guard query.purpose == nil || family.metadata.purpose == query.purpose else {
                return nil
            }
            let checkpoints: [ModelCatalogCheckpointPresentation] = family.checkpoints
                .compactMap { checkpoint in
                let artifacts = checkpoint.artifacts.filter {
                    query.matches(
                        artifact: $0,
                        checkpoint: checkpoint,
                        family: family
                    )
                }
                guard !artifacts.isEmpty else {
                    return nil
                }
                return ModelCatalogCheckpointPresentation(
                    metadata: checkpoint.metadata,
                    artifacts: artifacts,
                    referenceArtifact: checkpoint.referenceArtifact,
                    defaultInstallArtifact: checkpoint.defaultInstallArtifact,
                    resolution: checkpoint.resolution,
                    installedOnDiskBytes: checkpoint.installedOnDiskBytes
                )
                }
            guard !checkpoints.isEmpty else {
                return nil
            }
            return ModelCatalogFamilyPresentation(
                metadata: family.metadata,
                checkpoints: sortCheckpoints(checkpoints, query: query)
            )
        }

        guard query.sort != .catalog else {
            return filtered
        }
        return query.stableSort(Array(filtered.enumerated())) { family in
            family.checkpoints.first.flatMap {
                checkpointSortValue($0, sort: query.sort)
            }
        }
    }

    private static func sortCheckpoints(
        _ checkpoints: [ModelCatalogCheckpointPresentation],
        query: ModelCatalogQuery
    ) -> [ModelCatalogCheckpointPresentation] {
        guard query.sort != .catalog else {
            return checkpoints
        }
        return query.stableSort(Array(checkpoints.enumerated())) {
            checkpointSortValue($0, sort: query.sort)
        }
    }

    private static func checkpointSortValue(
        _ checkpoint: ModelCatalogCheckpointPresentation,
        sort: ModelCatalogSort
    ) -> Int64? {
        switch sort {
        case .catalog:
            return nil
        case .quality:
            return checkpoint.referenceArtifact?.row.model.qualityScore.map(
                Int64.init
            )
        case .speed:
            return checkpoint.referenceArtifact?.row.model.speedScore.map(
                Int64.init
            )
        case .downloadSize:
            return checkpoint.referenceArtifact?.row.operationalModel?.sizeBytes
        case .installedSize:
            return checkpoint.installedOnDiskBytes
        }
    }

    private static func queryStandaloneRows(
        _ source: [ModelCatalogRowPresentation],
        query: ModelCatalogQuery
    ) -> [ModelCatalogRowPresentation] {
        let filtered = source.enumerated().filter {
            query.matchesStandalone($0.element)
        }
        switch query.sort {
        case .catalog:
            return filtered.map(\.element)
        case .quality:
            return query.stableSort(filtered) {
                $0.model.qualityScore.map(Int64.init)
            }
        case .speed:
            return query.stableSort(filtered) {
                $0.model.speedScore.map(Int64.init)
            }
        case .downloadSize:
            return query.stableSort(filtered) {
                $0.operationalModel?.sizeBytes
            }
        case .installedSize:
            return query.stableSort(filtered) {
                $0.onDiskBytes
            }
        }
    }

    private static func makeFilterOptions(
        families: [ModelCatalogFamilyPresentation],
        rows: [ModelCatalogRowPresentation],
        purpose: ModelPurpose?
    ) -> ModelCatalogFilterOptions {
        let artifacts = families
            .filter { purpose == nil || $0.metadata.purpose == purpose }
            .flatMap(\.checkpoints)
            .flatMap(\.artifacts)
        let scopedRows = rows.filter {
            purpose == nil || $0.model.purpose == purpose
        }
        return ModelCatalogFilterOptions(
            artifactFormats: orderedUnique(
                artifacts.map(\.metadata.artifactFormat)
            ),
            numericFormats: orderedUnique(
                artifacts.map(\.metadata.numericFormat)
            ),
            runtimes: orderedUnique(artifacts.map(\.metadata.runtime)),
            computeRoutes: orderedUnique(
                artifacts.map(\.metadata.computeRoute)
            ),
            languages: orderedUnique(
                scopedRows
                    .compactMap(\.operationalModel)
                    .flatMap(\.capabilities.languages)
            )
        )
    }

    private static func orderedUnique<Value: Equatable>(
        _ values: [Value]
    ) -> [Value] {
        values.reduce(into: []) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
    }

    private static func makePinnedReveal(
        artifactID: String?,
        families: [ModelCatalogFamilyPresentation],
        rows: [ModelCatalogRowPresentation]
    ) -> ModelCatalogPinnedRevealPresentation? {
        guard let artifactID else {
            return nil
        }
        for family in families {
            for checkpoint in family.checkpoints {
                guard let artifact = checkpoint.artifacts.first(
                    where: { $0.id == artifactID }
                ) else {
                    continue
                }
                return .catalogArtifact(
                    family: family,
                    checkpoint: checkpoint,
                    artifact: artifact
                )
            }
        }
        if let row = rows.first(where: { $0.id == artifactID }) {
            return .standaloneArtifact(row)
        }
        return .unavailableArtifact(artifactID)
    }

    private static func actions(
        for model: ProductionModelPresentation,
        isRevoked: Bool,
        isInstalled: Bool,
        isActive: Bool,
        managedReadiness: ModelCatalogManagedReadiness?,
        installState: DownloadState?
    ) -> Set<ModelCatalogRowAction> {
        var actions: Set<ModelCatalogRowAction> = [.details]
        if isRevoked {
            if isInstalled {
                actions.insert(.delete)
            }
            return actions
        }

        if isActive {
            if model.purpose == .voiceCleaning {
                actions.insert(.disable)
            }
        } else if isInstalled, managedReadiness == .ready {
            actions.insert(.use)
        }

        if installState == nil {
            actions.insert(isInstalled ? .reinstall : .install)
        } else if let installState {
            if installState.phase == .revoked {
                actions.insert(isInstalled ? .reinstall : .install)
            }
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

    private static func stateTokens(
        isRevoked: Bool,
        isInstalled: Bool,
        isActive: Bool,
        managedReadiness: ModelCatalogManagedReadiness?,
        compatibility: ModelCatalogCompatibility
    ) -> [ModelCatalogStateToken] {
        var tokens: [ModelCatalogStateToken] = []
        if isRevoked {
            tokens.append(.revoked)
        }
        if isInstalled {
            tokens.append(.installed)
        }
        switch managedReadiness {
        case .ready:
            tokens.append(.ready)
        case .needsRepair:
            tokens.append(.needsRepair)
        case .verificationRequired:
            tokens.append(.verificationRequired)
        case .installed, nil:
            break
        }
        if isActive {
            tokens.append(.active)
        }
        if case .incompatible = compatibility {
            tokens.append(.incompatible)
        }
        return tokens
    }

    private static func makeFamilyPresentations(
        graph: ModelCatalogPresentationGraph,
        rows: [ModelCatalogRowPresentation],
        referenceRows: [ModelCatalogRowPresentation],
        checkpointResolutions: [String: ModelCatalogCheckpointResolution]
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
                        .sorted {
                            $0.metadata.presentation.curatedRank
                                < $1.metadata.presentation.curatedRank
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
                    let resolution = checkpointResolutions[checkpoint.id]
                    let resolvedDefaultArtifact = resolution?.installArtifactID
                        .flatMap { artifactID in
                            if let visible = artifacts.first(
                                where: { $0.id == artifactID }
                            ) {
                                return visible
                            }
                            guard let metadata = artifactsByID[artifactID],
                                  let row = referenceRowsByID[artifactID]
                            else {
                                return nil
                            }
                            return ModelCatalogExactArtifactPresentation(
                                metadata: metadata,
                                row: row
                            )
                        }
                    let defaultInstallArtifact =
                        resolvedDefaultArtifact?.row.isRevoked == false
                            ? resolvedDefaultArtifact
                            : nil
                    return ModelCatalogCheckpointPresentation(
                        metadata: checkpoint,
                        artifacts: artifacts,
                        referenceArtifact: referenceArtifact,
                        defaultInstallArtifact: defaultInstallArtifact,
                        resolution: resolution,
                        installedOnDiskBytes: ModelCatalogCheckpointPresentation
                            .aggregateInstalledOnDiskBytes(artifacts)
                    )
                }
                .sorted {
                    $0.metadata.presentation.curatedRank
                        < $1.metadata.presentation.curatedRank
                }
            guard !checkpoints.isEmpty else {
                return nil
            }
            return ModelCatalogFamilyPresentation(
                metadata: family,
                checkpoints: checkpoints
            )
        }
        .sorted {
            $0.metadata.presentation.curatedRank
                < $1.metadata.presentation.curatedRank
        }
    }
}

extension ModelCatalogCompatibility {
    var catalogTitle: String {
        switch self {
        case .compatible:
            return "Compatible"
        case .requiresAppUpdate:
            return "Requires Textify Update"
        case .requiresMacOSUpdate:
            return "Requires macOS Update"
        case .incompatible:
            return "Incompatible"
        case .indeterminate:
            return "Compatibility Indeterminate"
        }
    }

    var catalogExplanation: String {
        switch self {
        case .compatible:
            return "Compatible with this Mac and Textify build."
        case let .requiresAppUpdate(minimumVersion):
            return "Requires Textify \(minimumVersion) or later."
        case let .requiresMacOSUpdate(minimumVersion):
            return "Requires macOS \(minimumVersion) or later."
        case let .incompatible(reason):
            switch reason {
            case let .unsupportedArchitecture(current, supported):
                let currentName = current?.rawValue ?? "unsupported architecture"
                return "This Mac uses \(currentName); requires "
                    + supported.map(\.rawValue).joined(separator: ", ")
                    + "."
            case let .insufficientMemory(requiredBytes, availableBytes):
                return "Requires "
                    + ByteCountFormatter.string(
                        fromByteCount: requiredBytes,
                        countStyle: .memory
                    )
                    + " memory; this Mac reports "
                    + ByteCountFormatter.string(
                        fromByteCount: availableBytes,
                        countStyle: .memory
                    )
                    + "."
            case let .unsupportedRuntime(runtime):
                return "\(ModelCatalogVariantTerminology.runtime(runtime)) is unavailable in this build."
            case let .unsupportedArtifactLayout(layout):
                return "The signed \(layout.rawValue) layout is unavailable in this build."
            case let .unsupportedComputeRoute(route):
                return "\(ModelCatalogVariantTerminology.computeRoute(route)) is unavailable on this Mac."
            }
        case let .indeterminate(reason):
            switch reason {
            case .trustedManifestUnavailable:
                return "The trusted signed catalog is unavailable."
            case let .signedPresentationUnavailable(modelID):
                return "Signed compatibility metadata is unavailable for \(modelID)."
            case let .operationalModelUnavailable(modelID):
                return "Operational metadata is unavailable for \(modelID)."
            case let .exactArtifactUnavailable(modelID):
                return "Exact Artifact metadata is unavailable for \(modelID)."
            case let .inconsistentSignedMetadata(modelID):
                return "Signed runtime metadata is inconsistent for \(modelID)."
            case .invalidCurrentAppVersion:
                return "Textify could not determine the current app version."
            case .invalidCurrentMacOSVersion:
                return "Textify could not determine the current macOS version."
            case let .invalidSignedRequirements(modelID):
                return "Signed compatibility requirements are invalid for \(modelID)."
            case .physicalMemoryUnavailable:
                return "Textify could not determine this Mac's memory."
            }
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

    static func state(
        for modelID: String,
        from statesByModelID: [String: DownloadState]
    ) -> DownloadState? {
        state(for: modelID, from: statesByModelID[modelID])
    }

    static func offersCancel(for state: DownloadState) -> Bool {
        !state.phase.isTerminal && state.phase != .installing
    }

    static func offersRetry(for state: DownloadState) -> Bool {
        switch state.phase {
        case .waitingForCatalogCheck, .interrupted, .failed, .cancelled:
            return true
        case .queued, .paused, .waitingForNetwork, .checkingSpace,
             .downloading, .verifying, .installing, .installed, .revoked:
            return false
        }
    }
}

enum ModelInstallProgressPresentation {
    static func title(for state: DownloadState) -> String {
        switch state.phase {
        case .queued:
            return "Queued"
        case .paused:
            return "Download paused"
        case .waitingForNetwork:
            return "Waiting for network"
        case .waitingForCatalogCheck:
            return "Waiting for catalog check"
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
        case .revoked:
            return "Install revoked"
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
            ? "\(displayName) is enabled for future dictation."
            : "\(displayName) is active and ready."
    }

    var activeLabel: String {
        purpose == .voiceCleaning ? "Cleaning Enabled" : "Active"
    }

    var useLabel: String {
        purpose == .voiceCleaning ? "Enable" : "Use Model"
    }

    var installLabel: String {
        "Install"
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
