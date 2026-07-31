import Foundation
import Observation
import TextifyModels

struct ModelCatalogScreenRequest: Equatable, Sendable {
    let purpose: ModelPurpose
    let selectedLanguage: String?
    let browseAllLanguages: Bool
    let artifactOverrides: [String: String]
    let stableCheckpointOrder: [String]
    let includesRichTransferState: Bool

    init(
        purpose: ModelPurpose,
        selectedLanguage: String? = nil,
        browseAllLanguages: Bool = false,
        artifactOverrides: [String: String] = [:],
        stableCheckpointOrder: [String] = [],
        includesRichTransferState: Bool = false
    ) {
        self.purpose = purpose
        self.selectedLanguage = selectedLanguage
        self.browseAllLanguages = browseAllLanguages
        self.artifactOverrides = artifactOverrides
        self.stableCheckpointOrder = stableCheckpointOrder
        self.includesRichTransferState = includesRichTransferState
    }
}

struct ModelCatalogOverrideResolution: Equatable, Sendable {
    let legalArtifactIDsByCheckpoint: [String: String]
    let invalidArtifactIDsByCheckpoint: [String: String]

    init(
        experience: ModelCatalogExperience,
        purpose: ModelPurpose,
        artifactOverrides: [String: String],
        validationAvailable: Bool
    ) {
        guard validationAvailable else {
            legalArtifactIDsByCheckpoint = artifactOverrides
            invalidArtifactIDsByCheckpoint = [:]
            return
        }
        let legalArtifactIDsByCheckpoint =
            experience.legalArtifactIDsByCheckpoint(
                for: purpose
            )
        var accepted: [String: String] = [:]
        var rejected: [String: String] = [:]
        for (checkpointID, artifactID) in artifactOverrides {
            if legalArtifactIDsByCheckpoint[checkpointID]?
                .contains(artifactID) == true
            {
                accepted[checkpointID] = artifactID
            } else {
                rejected[checkpointID] = artifactID
            }
        }
        self.legalArtifactIDsByCheckpoint = accepted
        invalidArtifactIDsByCheckpoint = rejected
    }
}

enum ModelProviderLogoKey: Equatable, Sendable {
    case asset(String)
    case system(String)
    case monogram(String)
}

extension ModelProviderIdentity {
    var logoKey: ModelProviderLogoKey? {
        if let logoAssetName {
            return .asset(logoAssetName)
        }
        if let systemImage {
            return .system(systemImage)
        }
        return mark.isEmpty ? nil : .monogram(mark)
    }
}

struct ModelCatalogScreenVersionOption: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let runtime: String
    let downloadSize: String
    let state: String
    let accuracyTradeoff: String
    let expectedFinalization: String
    let requirements: String
    let quality: ModelCatalogVariantComparisonMetric
    let speed: ModelCatalogVariantComparisonMetric
    let comparisonGroupID: String?
    let compatibility: String
    let supportedLanguageCodes: [String]
    let isActionable: Bool
    let isSelected: Bool
    let isRecommended: Bool
    let isInstalled: Bool
    let measuredLocalBytes: Int64?
    let allowsDeletion: Bool
    let outlineLevel: Int
    let logicalPosition: Int
    let logicalCount: Int

    init(
        _ option: ModelCheckpointVersionOption,
        outlineLevel: Int,
        logicalPosition: Int,
        logicalCount: Int
    ) {
        id = option.id
        displayName = option.displayName
        runtime = option.runtime
        downloadSize = option.downloadSize
        state = option.state
        accuracyTradeoff = option.accuracyTradeoff
        expectedFinalization = option.expectedFinalization
        requirements = option.requirements
        quality = option.quality
        speed = option.speed
        comparisonGroupID = option.comparisonGroupID
        compatibility = option.compatibility
        supportedLanguageCodes =
            option.artifact.row.operationalModel?.capabilities.languages ?? []
        isActionable = option.isActionable
        isSelected = option.isSelected
        isRecommended = option.isRecommended
        isInstalled = option.artifact.row.isInstalled
        measuredLocalBytes = option.artifact.row.measuredLocalBytes
        allowsDeletion = option.artifact.row.actions.contains(.delete)
        self.outlineLevel = outlineLevel
        self.logicalPosition = logicalPosition
        self.logicalCount = logicalCount
    }

    var accessibilitySummary: String {
        [
            displayName,
            String(localized: "Exact Artifact, level \(outlineLevel)"),
            state,
            String(
                localized:
                    "Row \(logicalPosition) of \(logicalCount)"
            ),
        ].joined(separator: ", ")
    }
}

struct ModelCatalogScreenRow: Equatable, Identifiable, Sendable {
    let checkpointID: String
    let familyName: String
    let provider: ModelProviderIdentity
    let providerLogoKey: ModelProviderLogoKey?
    let title: String
    let description: String
    let selectedArtifactID: String
    let selectedArtifactName: String
    let selectedArtifactSupportedLanguageCodes: [String]
    let annotation: ModelCheckpointAnnotation
    let lifecycleState: String?
    let primaryAction: ModelCheckpointPrimaryAction
    let qualityLabel: String
    let qualityLevel: Int
    let speedLabel: String
    let speedLevel: Int
    let downloadSize: String
    let languageCompatibilityNote: String?
    let selectedLanguage: String?
    let versionRoute: ModelCheckpointVersionRoute
    let versionOptions: [ModelCatalogScreenVersionOption]
    let transferAttemptID: String?
    let isActive: Bool
    let isInstalled: Bool
    let installOnlyAvailable: Bool
    let selectedArtifactIsRevoked: Bool
    let selectedArtifactAllowsOperations: Bool
    let outlineLevel: Int
    let logicalPosition: Int
    let logicalCount: Int
    let accessibilitySummary: String

    var id: String {
        checkpointID
    }

    var versionCount: Int {
        versionOptions.count
    }

    var hasMultipleComparisonGroups: Bool {
        Set(versionOptions.compactMap(\.comparisonGroupID)).count > 1
    }

    init(
        _ row: ModelCheckpointRowPresentation,
        outlineLevel: Int = 2,
        logicalPosition: Int = 1,
        logicalCount: Int = 1
    ) {
        checkpointID = row.checkpointID
        familyName = row.familyName
        let resolvedProvider = ModelProviderIdentity.resolve(
            from: row.familyName,
            row.providerName
        )
        provider = resolvedProvider
        providerLogoKey = resolvedProvider.logoKey
        title = row.title
        description = row.description
        selectedArtifactID = row.selectedArtifactID
        selectedArtifactName =
            row.selectedArtifact.metadata.presentation.displayName
        selectedArtifactSupportedLanguageCodes =
            row.selectedArtifact.row.operationalModel?.capabilities.languages
            ?? []
        annotation = row.annotation
        lifecycleState = row.lifecycleState
        primaryAction = row.primaryAction
        qualityLabel = row.qualityLabel
        qualityLevel = row.qualityLevel
        speedLabel = row.speedLabel
        speedLevel = row.speedLevel
        downloadSize = row.downloadSize
        languageCompatibilityNote = row.languageCompatibilityNote
        selectedLanguage = row.selectedLanguage
        versionRoute = row.versionRoute
        let options = row.versionOptions
        versionOptions = options.enumerated().map { index, option in
            ModelCatalogScreenVersionOption(
                option,
                outlineLevel: outlineLevel + 1,
                logicalPosition: index + 1,
                logicalCount: options.count
            )
        }
        transferAttemptID = row.selectedArtifact.row.install?.state.attemptID
        isActive = row.isActive
        isInstalled = row.isInstalled
        installOnlyAvailable = row.installOnlyAvailable
        selectedArtifactIsRevoked = row.selectedArtifact.row.isRevoked
        selectedArtifactAllowsOperations =
            row.selectedArtifact.row.compatibility.allowsModelOperations
        self.outlineLevel = outlineLevel
        self.logicalPosition = logicalPosition
        self.logicalCount = logicalCount
        accessibilitySummary = [
            String(localized: "\(row.familyName), Family, level 1"),
            row.accessibilityLabel(for: .wide),
            String(localized: "Checkpoint, level \(outlineLevel)"),
            String(localized: "Quality \(row.qualityLabel)"),
            String(localized: "Speed \(row.speedLabel)"),
            String(
                localized:
                    "Row \(logicalPosition) of \(logicalCount)"
            ),
        ].joined(separator: ", ")
    }

    func languageMismatch(
        forArtifactID artifactID: String
    ) -> ModelCheckpointLanguageMismatch? {
        let supportedLanguages =
            artifactID == selectedArtifactID
            ? selectedArtifactSupportedLanguageCodes
            : versionOptions.first { $0.id == artifactID }?
                .supportedLanguageCodes ?? []
        return modelCheckpointLanguageMismatch(
            selectedLanguage: selectedLanguage,
            supportedLanguageCodes: supportedLanguages
        )
    }

    var deletionCandidates: [ModelCheckpointDeletionCandidate] {
        versionOptions.map {
            ModelCheckpointDeletionCandidate(
                checkpointID: checkpointID,
                artifactID: $0.id,
                isInstalled: $0.isInstalled,
                hasMeasuredLocalSize: $0.measuredLocalBytes != nil,
                allowsDeletion: $0.allowsDeletion
            )
        }
    }

    func deletionArtifactID(
        explicitlySelectedArtifactID: String?
    ) -> String? {
        ModelCheckpointDeletionPolicy.artifactID(
            explicitlySelectedArtifactID:
                explicitlySelectedArtifactID,
            focusedCheckpointID: checkpointID,
            candidates: deletionCandidates
        )
    }

    func containsArtifact(_ artifactID: String?) -> Bool {
        guard let artifactID else {
            return false
        }
        return versionOptions.contains { $0.id == artifactID }
    }
}

struct ModelCatalogScreenSection: Equatable, Identifiable, Sendable {
    let id: String
    let title: String?
    let providerName: String?
    let rows: [ModelCatalogScreenRow]
}

struct ModelCatalogScreenProjection: Equatable, Sendable {
    let sections: [ModelCatalogScreenSection]

    static let empty = ModelCatalogScreenProjection(sections: [])

    var rows: [ModelCatalogScreenRow] {
        sections.flatMap(\.rows)
    }

    init(sections: [ModelCatalogScreenSection]) {
        self.sections = sections
    }

    init(_ presentation: ModelCheckpointListPresentation) {
        let logicalCount = presentation.rows.count
        var logicalPosition = 0
        sections = presentation.sections.map { section in
            ModelCatalogScreenSection(
                id: section.id,
                title: section.title,
                providerName: section.providerName,
                rows: section.rows.map { row in
                    logicalPosition += 1
                    return ModelCatalogScreenRow(
                        row,
                        outlineLevel: 2,
                        logicalPosition: logicalPosition,
                        logicalCount: logicalCount
                    )
                }
            )
        }
    }
}

enum ModelCatalogScreenCommand: Equatable, Sendable {
    case inspect(checkpointID: String)
    case selectArtifact(checkpointID: String, artifactID: String)
    case inspectArtifact(artifactID: String)
    case setVersionDisclosure(checkpointID: String, isExpanded: Bool)
    case use(checkpointID: String, artifactID: String)
    case installOnly(checkpointID: String, artifactID: String)
    case cancel(attemptID: String)
    case retry(attemptID: String)
    case verify(artifactID: String)
    case reveal(artifactID: String)
    case remove(artifactID: String)
}

struct ModelCatalogTransferCellSnapshot: Equatable, Sendable {
    let phase: DownloadPhase
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let percent: Int?
    let attemptID: String?
    let message: String?

    init(_ state: DownloadState) {
        phase = state.phase
        bytesDownloaded = state.bytesDownloaded
        totalBytes = state.totalBytes
        percent =
            state.totalBytes > 0
            ? Int((state.progressFraction * 100).rounded())
            : nil
        attemptID = state.attemptID
        message = state.message
    }

    private var downloadState: DownloadState {
        DownloadState(
            modelID: "",
            phase: phase,
            bytesDownloaded: bytesDownloaded,
            totalBytes: totalBytes,
            message: message,
            attemptID: attemptID
        )
    }

    var visualValue: String {
        let title = ModelInstallProgressPresentation.title(
            for: downloadState
        )
        guard let percent else {
            return title
        }
        return "\(title), \(percent)%"
    }

    var accessibilityValue: String {
        let title = ModelInstallProgressPresentation.title(
            for: downloadState
        )
        let progress = ModelInstallProgressPresentation.percentText(
            for: downloadState
        ).map { ", \($0)" } ?? ""
        let detail = ModelInstallProgressPresentation.detailText(
            for: downloadState
        )
        return "\(title)\(progress). \(detail)"
    }
}

@MainActor
@Observable
final class ModelCatalogTransferStateCell {
    private(set) var snapshot: ModelCatalogTransferCellSnapshot

    init(snapshot: ModelCatalogTransferCellSnapshot) {
        self.snapshot = snapshot
    }

    func publish(_ next: ModelCatalogTransferCellSnapshot) {
        guard next != snapshot else {
            return
        }
        snapshot = next
    }
}

@MainActor
final class ModelCatalogTransferStateRegistry {
    private let capacity: Int
    private var cellsByArtifactID:
        [String: ModelCatalogTransferStateCell] = [:]

    init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    func cellIfPresent(
        for artifactID: String
    ) -> ModelCatalogTransferStateCell? {
        cellsByArtifactID[artifactID]
    }

    @discardableResult
    func reconcile(
        statesByArtifactID: [String: DownloadState]
    ) -> Bool {
        var topologyChanged = false
        let liveStates = statesByArtifactID.filter {
            !$0.value.phase.isTerminal
        }
        let admitted = liveStates.sorted { lhs, rhs in
            if lhs.value.isActive != rhs.value.isActive {
                return lhs.value.isActive
            }
            return lhs.key < rhs.key
        }.prefix(capacity)
        let admittedIDs = Set(admitted.map(\.key))
        for artifactID in cellsByArtifactID.keys
        where !admittedIDs.contains(artifactID) {
            cellsByArtifactID[artifactID] = nil
            topologyChanged = true
        }
        for (artifactID, state) in admitted {
            let snapshot = ModelCatalogTransferCellSnapshot(state)
            if let cell = cellsByArtifactID[artifactID] {
                cell.publish(snapshot)
            } else {
                cellsByArtifactID[artifactID] =
                    ModelCatalogTransferStateCell(snapshot: snapshot)
                topologyChanged = true
            }
        }
        return topologyChanged
    }
}
