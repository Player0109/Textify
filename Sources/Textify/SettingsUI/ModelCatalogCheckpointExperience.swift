import AppKit
import Foundation
import TextifyModels

enum ModelCheckpointLayoutMode: Equatable {
    case wide
    case stacked
}

struct ModelCheckpointAccessibilityVisualPolicy: Equatable, Sendable {
    let usesOpaqueSurfaces: Bool
    let emphasizesSelectionBoundaries: Bool
    let emphasizesControlBoundaries: Bool

    init(
        increaseContrast: Bool,
        differentiateWithoutColor: Bool,
        reduceTransparency: Bool
    ) {
        usesOpaqueSurfaces = reduceTransparency
        emphasizesSelectionBoundaries =
            increaseContrast || differentiateWithoutColor
        emphasizesControlBoundaries =
            increaseContrast || differentiateWithoutColor
    }
}

struct ModelCheckpointInspectorSourceLicensePresentation: Equatable {
    let sourceAndLicense: ModelSourceLicensePresentation
    let upstreamSourceURL: URL?

    init?(artifact: ModelCatalogExactArtifactPresentation) {
        guard let model = artifact.row.operationalModel else {
            return nil
        }
        let sourceAndLicense = ModelSourceLicensePresentation(model: model)
        self.sourceAndLicense = sourceAndLicense
        upstreamSourceURL = sourceAndLicense.sourceURL
    }
}

struct ModelCheckpointLayoutMetrics: Equatable {
    let modelColumnFloor: CGFloat
    let qualityColumnFloor: CGFloat
    let speedColumnFloor: CGFloat
    let stateColumnFloor: CGFloat
    let actionColumnFloor: CGFloat
    let columnSpacing: CGFloat
    let horizontalPadding: CGFloat
    let scrollbarAllowance: CGFloat

    static let current: ModelCheckpointLayoutMetrics = measured {
        sample in
        ceil(
            (sample as NSString).size(
                withAttributes: [
                    .font: NSFont.systemFont(
                        ofSize: NSFont.smallSystemFontSize
                    )
                ]
            ).width
        )
    }

    static func measured(
        measureText: (String) -> CGFloat
    ) -> ModelCheckpointLayoutMetrics {
        ModelCheckpointLayoutMetrics(
            modelColumnFloor: max(
                180,
                measureText("Whisper large-v3-turbo") + 20
            ),
            qualityColumnFloor: max(
                86,
                measureText("Not Comparable") + 8
            ),
            speedColumnFloor: max(
                86,
                measureText("Not Comparable") + 8
            ),
            stateColumnFloor: max(
                104,
                measureText("Unavailable") + 8
            ),
            actionColumnFloor: max(
                124,
                measureText("Use") + measureText("•••") + 24
            ),
            columnSpacing: 12,
            horizontalPadding: 28,
            scrollbarAllowance: NSScroller.scrollerWidth(
                for: .regular,
                scrollerStyle: .legacy
            )
        )
    }
}

extension ModelCatalogExactArtifactPresentation {
    fileprivate var supportedLanguageCodes: [String] {
        guard let languages = row.operationalModel?.capabilities.languages,
            !languages.contains("*")
        else {
            return []
        }
        return languages
    }

    fileprivate func supports(language: String) -> Bool {
        guard let languages = row.operationalModel?.capabilities.languages
        else {
            return false
        }
        return languages.contains("*")
            || languages.contains {
                $0.caseInsensitiveCompare(language) == .orderedSame
            }
    }
}

func modelCheckpointIsSpecificLanguage(
    _ language: String
) -> Bool {
    language != "*" && language != "auto"
}

func modelCheckpointLanguageName(_ language: String) -> String {
    Locale.current.localizedString(forLanguageCode: language)?.capitalized
        ?? language.uppercased()
}

func modelCheckpointPreferEnglish(
    _ lhs: String,
    _ rhs: String
) -> Bool {
    if lhs == "en" {
        return true
    }
    if rhs == "en" {
        return false
    }
    return lhs < rhs
}

func modelCheckpointLanguageMismatch(
    selectedLanguage: String?,
    supportedLanguageCodes: [String]
) -> ModelCheckpointLanguageMismatch? {
    guard let selectedLanguage,
        modelCheckpointIsSpecificLanguage(selectedLanguage),
        !supportedLanguageCodes.contains("*"),
        !supportedLanguageCodes.contains(where: {
            $0.caseInsensitiveCompare(selectedLanguage) == .orderedSame
        }),
        let supportedLanguage = supportedLanguageCodes
            .filter(modelCheckpointIsSpecificLanguage)
            .sorted(by: modelCheckpointPreferEnglish)
            .first
    else {
        return nil
    }
    return ModelCheckpointLanguageMismatch(
        requestedLanguageCode: selectedLanguage,
        requestedLanguageName:
            modelCheckpointLanguageName(selectedLanguage),
        supportedLanguageCode: supportedLanguage,
        supportedLanguageName:
            modelCheckpointLanguageName(supportedLanguage)
    )
}

struct ModelCheckpointLayoutPolicy: Equatable {
    let metrics: ModelCheckpointLayoutMetrics
    let hysteresis: CGFloat

    init(
        metrics: ModelCheckpointLayoutMetrics = .current,
        hysteresis: CGFloat = 24
    ) {
        self.metrics = metrics
        self.hysteresis = hysteresis
    }

    var requiredWideWidth: CGFloat {
        metrics.modelColumnFloor
            + metrics.qualityColumnFloor
            + metrics.speedColumnFloor
            + metrics.stateColumnFloor
            + metrics.actionColumnFloor
            + (metrics.columnSpacing * 4)
            + metrics.horizontalPadding
            + metrics.scrollbarAllowance
    }

    func mode(
        availableWidth: CGFloat,
        previous: ModelCheckpointLayoutMode
    ) -> ModelCheckpointLayoutMode {
        switch previous {
        case .wide:
            availableWidth < requiredWideWidth ? .stacked : .wide
        case .stacked:
            availableWidth >= requiredWideWidth + hysteresis
                ? .wide
                : .stacked
        }
    }
}

struct ModelCheckpointInspectorLayoutPolicy: Equatable {
    let catalogLayoutPolicy: ModelCheckpointLayoutPolicy
    let sidebarWidth: CGFloat
    let inspectorWidth: CGFloat
    let separation: CGFloat

    init(
        catalogLayoutPolicy: ModelCheckpointLayoutPolicy = .init(),
        sidebarWidth: CGFloat = TextifyWindowMetrics.sidebarWidth,
        inspectorWidth: CGFloat = 320,
        separation: CGFloat = 24
    ) {
        self.catalogLayoutPolicy = catalogLayoutPolicy
        self.sidebarWidth = sidebarWidth
        self.inspectorWidth = inspectorWidth
        self.separation = separation
    }

    var requiredTrailingWindowWidth: CGFloat {
        sidebarWidth
            + catalogLayoutPolicy.requiredWideWidth
            + inspectorWidth
            + separation
    }

    func usesTrailingInspector(windowWidth: CGFloat) -> Bool {
        windowWidth >= requiredTrailingWindowWidth
    }
}

enum ModelCheckpointAnnotation: Equatable, Sendable {
    case inUse
    case recommended
    case none

    var title: String? {
        switch self {
        case .inUse:
            String(localized: "In Use")
        case .recommended:
            String(localized: "Recommended")
        case .none:
            nil
        }
    }
}

enum ModelCheckpointPrimaryAction: Equatable, Sendable {
    case use
    case cancel
    case retry
    case none

    var title: String? {
        switch self {
        case .use:
            String(localized: "Use")
        case .cancel:
            String(localized: "Cancel")
        case .retry:
            String(localized: "Retry")
        case .none:
            nil
        }
    }
}

enum ModelCheckpointVersionRoute: Equatable, Sendable {
    case none
    case popover
    case comparisonSheet
}

enum ModelCheckpointKeyboardResult: Equatable {
    case ignored
    case focus(String)
    case inspect(String)
    case inspectArtifact(String)
    case expand(String)
    case collapse(String)
    case deleteArtifact(String)
}

struct ModelCheckpointDeletionCandidate: Equatable, Sendable {
    let checkpointID: String
    let artifactID: String
    let isInstalled: Bool
    let hasMeasuredLocalSize: Bool
    let allowsDeletion: Bool

    var isEligible: Bool {
        isInstalled && hasMeasuredLocalSize && allowsDeletion
    }
}

enum ModelCheckpointDeletionPolicy {
    static func artifactID(
        explicitlySelectedArtifactID: String?,
        focusedCheckpointID: String?,
        candidates: [ModelCheckpointDeletionCandidate]
    ) -> String? {
        guard let explicitlySelectedArtifactID,
            let focusedCheckpointID,
            let candidate = candidates.first(where: {
                $0.checkpointID == focusedCheckpointID
                    && $0.artifactID == explicitlySelectedArtifactID
            }),
            candidate.isEligible
        else {
            return nil
        }
        return candidate.artifactID
    }
}

enum ModelCheckpointKeyboardNavigation {
    static func result(
        for command: ModelCatalogKeyboardCommand,
        focusedCheckpointID: String?,
        checkpointIDs: [String],
        expandedCheckpointID: String? = nil,
        expandableCheckpointIDs: Set<String> = [],
        inspectionArtifactID: String? = nil,
        deletionArtifactID: String? = nil,
        pageSize: Int = 8
    ) -> ModelCheckpointKeyboardResult {
        guard !checkpointIDs.isEmpty else {
            return .ignored
        }
        let currentIndex =
            focusedCheckpointID.flatMap {
                checkpointIDs.firstIndex(of: $0)
            } ?? 0
        let destination: Int
        switch command {
        case .moveUp:
            destination = max(0, currentIndex - 1)
        case .moveDown:
            destination = min(checkpointIDs.count - 1, currentIndex + 1)
        case .pageUp:
            destination = max(0, currentIndex - max(1, pageSize))
        case .pageDown:
            destination = min(
                checkpointIDs.count - 1,
                currentIndex + max(1, pageSize)
            )
        case .home:
            destination = 0
        case .end:
            destination = checkpointIDs.count - 1
        case .activate:
            if let inspectionArtifactID {
                return .inspectArtifact(inspectionArtifactID)
            }
            return .inspect(checkpointIDs[currentIndex])
        case .deleteSelection:
            return deletionArtifactID.map(
                ModelCheckpointKeyboardResult.deleteArtifact
            ) ?? .ignored
        case .collapse:
            let checkpointID = checkpointIDs[currentIndex]
            return expandedCheckpointID == checkpointID
                ? .collapse(checkpointID)
                : .ignored
        case .expand:
            let checkpointID = checkpointIDs[currentIndex]
            return expandableCheckpointIDs.contains(checkpointID)
                ? .expand(checkpointID)
                : .ignored
        }
        return .focus(checkpointIDs[destination])
    }
}

struct ModelCheckpointField: Equatable {
    let label: String
    let value: String
}

struct ModelCheckpointVersionOption: Equatable, Identifiable {
    let artifact: ModelCatalogExactArtifactPresentation
    let comparison: ModelCatalogVariantComparisonPresentation?
    let isSelected: Bool
    let isRecommended: Bool

    var id: String {
        artifact.id
    }

    var displayName: String {
        artifact.metadata.presentation.displayName
    }

    var runtime: String {
        ModelCatalogVariantTerminology.runtime(
            artifact.metadata.runtime
        )
    }

    var downloadSize: String {
        artifact.row.sizeDescription
    }

    var state: String {
        if artifact.row.isRevoked {
            return String(localized: "Revoked")
        }
        if let install = artifact.row.install {
            return install.title
        }
        if artifact.row.isActive {
            return String(localized: "In Use")
        }
        if artifact.row.isInstalled {
            return String(localized: "Installed")
        }
        if artifact.row.compatibility != .compatible {
            return artifact.row.compatibility.catalogTitle
        }
        return String(localized: "Not installed")
    }

    var accuracyTradeoff: String {
        artifact.row.model.accuracyTradeoff
    }

    var expectedFinalization: String {
        artifact.row.model.expectedFinalization
    }

    var requirements: String {
        artifact.row.model.requirements
    }

    var quality: ModelCatalogVariantComparisonMetric {
        guard comparisonGroupID != nil else {
            return .notComparable
        }
        return comparison?.quality ?? .unrated
    }

    var speed: ModelCatalogVariantComparisonMetric {
        guard comparisonGroupID != nil else {
            return .notComparable
        }
        return comparison?.speed ?? .unrated
    }

    var comparisonGroupID: String? {
        artifact.metadata.presentation.comparisonGroupID
    }

    var compatibility: String {
        artifact.row.compatibility.catalogExplanation
    }

    var isActionable: Bool {
        !artifact.row.isRevoked
            && artifact.row.compatibility.allowsModelOperations
    }
}

struct ModelCheckpointRowPresentation: Equatable, Identifiable {
    let familyID: String
    let familyName: String
    let providerName: String
    let checkpoint: ModelCatalogCheckpointPresentation
    let selectedArtifact: ModelCatalogExactArtifactPresentation
    let annotation: ModelCheckpointAnnotation
    let lifecycleState: String?
    let primaryAction: ModelCheckpointPrimaryAction
    let selectedLanguage: String?

    var id: String {
        checkpoint.id
    }

    var checkpointID: String {
        checkpoint.id
    }

    var selectedArtifactID: String {
        selectedArtifact.id
    }

    var title: String {
        checkpoint.metadata.presentation.displayName
    }

    var description: String {
        checkpoint.metadata.presentation.description
    }

    var qualityLabel: String {
        selectedArtifact.row.model.qualityLabel
    }

    var qualityLevel: Int {
        selectedArtifact.row.model.qualitySignalLevel
    }

    var speedLabel: String {
        selectedArtifact.row.model.speedLabel
    }

    var speedLevel: Int {
        selectedArtifact.row.model.speedSignalLevel
    }

    var versionCount: Int {
        checkpoint.artifacts.count
    }

    var versionRoute: ModelCheckpointVersionRoute {
        switch versionCount {
        case 0, 1:
            .none
        case 2, 3:
            .popover
        default:
            .comparisonSheet
        }
    }

    var versionOptions: [ModelCheckpointVersionOption] {
        let comparisons = Dictionary(
            uniqueKeysWithValues: checkpoint.variantComparisons.map {
                ($0.id, $0)
            }
        )
        return checkpoint.artifacts.enumerated().sorted { lhs, rhs in
            let leftRecommended =
                checkpoint.metadata.recommendedArtifactID == lhs.element.id
            let rightRecommended =
                checkpoint.metadata.recommendedArtifactID == rhs.element.id
            if leftRecommended != rightRecommended {
                return leftRecommended
            }
            return lhs.offset < rhs.offset
        }.map { _, artifact in
            ModelCheckpointVersionOption(
                artifact: artifact,
                comparison: comparisons[artifact.id],
                isSelected: artifact.id == selectedArtifact.id,
                isRecommended:
                    checkpoint.metadata.recommendedArtifactID == artifact.id
                    && !artifact.row.isRevoked
            )
        }
    }

    var hasMultipleComparisonGroups: Bool {
        Set(versionOptions.compactMap(\.comparisonGroupID)).count > 1
    }

    var isActive: Bool {
        checkpoint.artifacts.contains { $0.row.isActive }
    }

    var isInstalled: Bool {
        selectedArtifact.row.isInstalled
    }

    var installOnlyAvailable: Bool {
        !selectedArtifact.row.isInstalled
            && primaryAction == .use
    }

    var downloadSize: String {
        selectedArtifact.row.sizeDescription
    }

    var compatibilityExplanation: String {
        selectedArtifact.row.compatibility.catalogExplanation
    }

    var languageCompatibilityNote: String? {
        guard let selectedLanguage,
            modelCheckpointIsSpecificLanguage(selectedLanguage),
            !selectedArtifact.supports(language: selectedLanguage)
        else {
            return nil
        }
        return String(
            localized:
                "Does not support \(modelCheckpointLanguageName(selectedLanguage))"
        )
    }

    func supports(language: String) -> Bool {
        checkpoint.artifacts.contains {
            $0.supports(language: language)
        }
    }

    func languageMismatch(
        for artifact: ModelCatalogExactArtifactPresentation
    ) -> ModelCheckpointLanguageMismatch? {
        modelCheckpointLanguageMismatch(
            selectedLanguage: selectedLanguage,
            supportedLanguageCodes: artifact.supportedLanguageCodes
        )
    }

    func fields(
        for _: ModelCheckpointLayoutMode
    ) -> [ModelCheckpointField] {
        [
            ModelCheckpointField(
                label: String(localized: "Model"),
                value: title
            ),
            ModelCheckpointField(
                label: String(localized: "Quality"),
                value: qualityLabel
            ),
            ModelCheckpointField(
                label: String(localized: "Speed"),
                value: speedLabel
            ),
            ModelCheckpointField(
                label: String(localized: "State"),
                value: accessibilityLifecycleState
            ),
            ModelCheckpointField(
                label: String(localized: "Action"),
                value:
                    primaryAction.title
                    ?? String(localized: "No action")
            ),
        ]
    }

    func accessibilityLabel(
        for _: ModelCheckpointLayoutMode
    ) -> String {
        var parts = [
            title,
            selectedArtifact.row.model.supportTier,
            providerName,
        ]
        if let annotation = annotation.title {
            parts.append(annotation)
        }
        parts.append(accessibilityLifecycleState)
        if let languageCompatibilityNote {
            parts.append(languageCompatibilityNote)
        }
        if versionCount > 1 {
            parts.append(String(localized: "\(versionCount) versions"))
        }
        parts.append(
            primaryAction.title.map {
                String(localized: "Action \($0)")
            } ?? String(localized: "No action")
        )
        return parts.joined(separator: ", ")
    }

    private var accessibilityLifecycleState: String {
        if let lifecycleState {
            return lifecycleState
        }
        if selectedArtifact.row.isActive {
            return String(localized: "Installed")
        }
        return String(localized: "Not installed")
    }
}

struct ModelCheckpointLanguageMismatch: Equatable, Sendable {
    let requestedLanguageCode: String
    let requestedLanguageName: String
    let supportedLanguageCode: String
    let supportedLanguageName: String
}

struct ModelCheckpointSectionPresentation: Equatable, Identifiable {
    let id: String
    let title: String?
    let providerName: String?
    let rows: [ModelCheckpointRowPresentation]
}

struct ModelCheckpointListPresentation: Equatable {
    let sections: [ModelCheckpointSectionPresentation]

    var rows: [ModelCheckpointRowPresentation] {
        sections.flatMap(\.rows)
    }

    static func standaloneInstalledRows(
        in experience: ModelCatalogExperience
    ) -> [ModelCatalogRowPresentation] {
        let representedArtifactIDs = Set(
            experience.families
                .flatMap(\.checkpoints)
                .flatMap(\.artifacts)
                .map(\.id)
        )
        return experience.rows.filter {
            $0.isInstalled && !representedArtifactIDs.contains($0.id)
        }
    }

    init(
        experience: ModelCatalogExperience,
        purpose: ModelPurpose,
        selectedLanguage: String?,
        browseAllLanguages: Bool,
        searchText: String,
        artifactOverrides: [String: String],
        stableCheckpointOrder: [String] = []
    ) {
        let normalizedSearchText = searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        let isSearching = !normalizedSearchText.isEmpty
        let candidates = experience.families.flatMap { family in
            family.checkpoints.compactMap {
                checkpoint
                    -> ModelCheckpointRowPresentation? in
                guard
                    checkpoint.artifacts.contains(where: {
                        $0.row.model.purpose == purpose
                    })
                else {
                    return nil
                }

                let activeArtifact = checkpoint.artifacts.first {
                    $0.row.isActive
                }
                let selectedArtifact = Self.selectedArtifact(
                    in: checkpoint,
                    activeArtifact: activeArtifact,
                    overrideArtifactID: artifactOverrides[checkpoint.id],
                    selectedLanguage: selectedLanguage
                )
                guard let selectedArtifact else {
                    return nil
                }
                return ModelCheckpointRowPresentation(
                    familyID: family.id,
                    familyName:
                        family.metadata.presentation.displayName,
                    providerName:
                        family.metadata.presentation.provider.displayName,
                    checkpoint: checkpoint,
                    selectedArtifact: selectedArtifact,
                    annotation: .none,
                    lifecycleState: Self.lifecycleState(
                        for: selectedArtifact.row
                    ),
                    primaryAction: Self.primaryAction(
                        for: selectedArtifact.row,
                        checkpointIsActive: activeArtifact != nil
                    ),
                    selectedLanguage: selectedLanguage
                )
            }
        }

        let visible = candidates.filter { row in
            guard !browseAllLanguages,
                !isSearching,
                let selectedLanguage,
                selectedLanguage != "*",
                selectedLanguage != "auto"
            else {
                return true
            }
            return row.isActive || row.supports(language: selectedLanguage)
        }

        let activeCheckpointID = visible.first(where: \.isActive)?.id
        let recommendedCheckpointID: String? = {
            if let activeCheckpointID,
                visible.first(where: {
                    $0.id == activeCheckpointID
                        && Self.isCatalogRecommendation($0)
                }) != nil
            {
                return activeCheckpointID
            }
            return visible.first(where: Self.isCatalogRecommendation)?.id
                ?? visible.first(where: {
                    $0.selectedArtifact.row.compatibility == .compatible
                        && !$0.selectedArtifact.row.isRevoked
                })?.id
        }()

        let annotated = visible.map { row in
            ModelCheckpointRowPresentation(
                familyID: row.familyID,
                familyName: row.familyName,
                providerName: row.providerName,
                checkpoint: row.checkpoint,
                selectedArtifact: row.selectedArtifact,
                annotation:
                    row.id == activeCheckpointID
                    ? .inUse
                    : row.id == recommendedCheckpointID
                        ? .recommended
                        : .none,
                lifecycleState: row.lifecycleState,
                primaryAction: row.primaryAction,
                selectedLanguage: selectedLanguage
            )
        }
        let livePrioritized = annotated.enumerated().sorted { lhs, rhs in
            if isSearching {
                let left = Self.searchRank(
                    lhs.element,
                    normalizedQuery: normalizedSearchText
                )
                let right = Self.searchRank(
                    rhs.element,
                    normalizedQuery: normalizedSearchText
                )
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            let left = Self.priority(
                lhs.element,
                activeCheckpointID: activeCheckpointID,
                recommendedCheckpointID: recommendedCheckpointID
            )
            let right = Self.priority(
                rhs.element,
                activeCheckpointID: activeCheckpointID,
                recommendedCheckpointID: recommendedCheckpointID
            )
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
        let stableRanks = Dictionary(
            uniqueKeysWithValues: stableCheckpointOrder.enumerated().map {
                ($0.element, $0.offset)
            }
        )
        let prioritized: [ModelCheckpointRowPresentation]
        if stableRanks.isEmpty {
            prioritized = livePrioritized
        } else {
            prioritized = livePrioritized.enumerated().sorted { lhs, rhs in
                let left = stableRanks[lhs.element.id] ?? Int.max
                let right = stableRanks[rhs.element.id] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map(\.element)
        }

        if isSearching {
            sections = [
                ModelCheckpointSectionPresentation(
                    id: "search-results",
                    title: nil,
                    providerName: nil,
                    rows: prioritized
                )
            ]
            return
        }

        var grouped: [[ModelCheckpointRowPresentation]] = []
        for row in prioritized {
            if grouped.last?.last?.familyID == row.familyID {
                grouped[grouped.count - 1].append(row)
            } else {
                grouped.append([row])
            }
        }
        sections = grouped.enumerated().map { index, rows in
            let showsHeading = rows.count >= 2
            return ModelCheckpointSectionPresentation(
                id: "\(rows[0].familyID)-\(index)",
                title: showsHeading ? rows[0].familyName : nil,
                providerName:
                    showsHeading ? rows[0].providerName : nil,
                rows: rows
            )
        }
    }

    private static func selectedArtifact(
        in checkpoint: ModelCatalogCheckpointPresentation,
        activeArtifact: ModelCatalogExactArtifactPresentation?,
        overrideArtifactID: String?,
        selectedLanguage: String?
    ) -> ModelCatalogExactArtifactPresentation? {
        if let activeArtifact {
            return activeArtifact
        }
        if let overrideArtifactID,
            let artifact = checkpoint.artifacts.first(
                where: { $0.id == overrideArtifactID }
            ),
            !artifact.row.isRevoked,
            artifact.row.compatibility.allowsModelOperations
        {
            return artifact
        }
        let preferred =
            [
                checkpoint.defaultInstallArtifact,
                checkpoint.presentedReferenceArtifact,
            ].compactMap { $0 } + checkpoint.artifacts
        if let selectedLanguage,
            modelCheckpointIsSpecificLanguage(selectedLanguage),
            let languageCompatible = preferred.first(where: {
                !$0.row.isRevoked
                    && $0.row.compatibility.allowsModelOperations
                    && $0.supports(language: selectedLanguage)
            })
        {
            return languageCompatible
        }
        return preferred.first
    }

    private static func lifecycleState(
        for row: ModelCatalogRowPresentation
    ) -> String? {
        if row.isRevoked {
            return String(localized: "Revoked")
        }
        if let install = row.install {
            if install.state.phase == .failed {
                return String(localized: "Failed: \(install.detailText)")
            }
            return install.title
        }
        if row.isActive {
            return nil
        }
        if row.isInstalled {
            return String(localized: "Installed")
        }
        if row.compatibility != .compatible {
            return row.compatibility.catalogTitle
        }
        return nil
    }

    private static func primaryAction(
        for row: ModelCatalogRowPresentation,
        checkpointIsActive: Bool
    ) -> ModelCheckpointPrimaryAction {
        if checkpointIsActive {
            return .none
        }
        if row.actions.contains(.cancelInstall) {
            return .cancel
        }
        if row.actions.contains(.retryInstall) {
            return .retry
        }
        if !row.isRevoked,
            row.compatibility.allowsModelOperations,
            row.actions.contains(.use)
                || row.actions.contains(.install)
                || row.actions.contains(.reinstall)
        {
            return .use
        }
        return .none
    }

    private static func isCatalogRecommendation(
        _ row: ModelCheckpointRowPresentation
    ) -> Bool {
        row.selectedArtifact.row.operationalModel?.tier
            .caseInsensitiveCompare("Recommended") == .orderedSame
            && row.selectedArtifact.row.compatibility == .compatible
            && !row.selectedArtifact.row.isRevoked
    }

    private static func priority(
        _ row: ModelCheckpointRowPresentation,
        activeCheckpointID: String?,
        recommendedCheckpointID: String?
    ) -> Int {
        if row.id == activeCheckpointID {
            return 0
        }
        if row.id == recommendedCheckpointID {
            return 1
        }
        return 2
    }

    static func searchRank(
        _ row: ModelCheckpointRowPresentation,
        normalizedQuery: String
    ) -> Int {
        let title = row.title.lowercased()
        if title == normalizedQuery {
            return 0
        }
        if title.hasPrefix(normalizedQuery) {
            return 1
        }
        if title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains(where: { $0.hasPrefix(normalizedQuery) })
        {
            return 2
        }
        if title.contains(normalizedQuery) {
            return 3
        }
        let secondary = [
            row.familyName,
            row.providerName,
            row.description,
        ].joined(separator: " ").lowercased()
        return secondary.contains(normalizedQuery) ? 4 : 5
    }
}
