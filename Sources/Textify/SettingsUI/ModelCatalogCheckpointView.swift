import SwiftUI
import TextifyModels
import TextifySettings

struct ModelCheckpointToolbar: View {
    @Binding var searchText: String
    @Binding var browseAllLanguages: Bool
    let language: TranscriptionLanguage
    let downloadCount: Int
    let onSelectLanguage: (TranscriptionLanguage) -> Void
    let onShowDownloads: () -> Void
    let onVerify: () -> Void
    let onImport: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(TranscriptionLanguage.allCases, id: \.self) {
                    language in
                    Button {
                        onSelectLanguage(language)
                    } label: {
                        if language == self.language {
                            Label(
                                language.displayName,
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(language.displayName)
                        }
                    }
                }
            } label: {
                Label(language.displayName, systemImage: "character.bubble")
            }
            .help("Dictation Language")

            Button {
                browseAllLanguages.toggle()
            } label: {
                Label(
                    browseAllLanguages
                        ? String(localized: "Use Language Filter")
                        : String(localized: "Browse All Languages"),
                    systemImage:
                        browseAllLanguages
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "globe"
                )
            }
            .foregroundStyle(
                browseAllLanguages
                    ? TextifyVisualIdentity.voiceViolet
                    : .secondary
            )

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search all models", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Search")
                }
            }
            .padding(.horizontal, 10)
            .frame(minWidth: 180, idealWidth: 300)
            .frame(minHeight: 28)
            .background(
                Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )

            Spacer(minLength: 0)

            Button(action: onShowDownloads) {
                Label(
                    downloadCount == 0
                        ? String(localized: "Downloads")
                        : String(localized: "Downloads \(downloadCount)"),
                    systemImage: "arrow.down.circle"
                )
            }

            Menu {
                Button(
                    "Verify Installed",
                    systemImage: "checkmark.seal",
                    action: onVerify
                )
                if let onImport {
                    Button(
                        "Import Whisper Model…",
                        systemImage: "square.and.arrow.down",
                        action: onImport
                    )
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More catalog actions")
        }
        .controlSize(.small)
    }
}

struct ModelCheckpointCatalogSurface: View, Equatable {
    let presentation: ModelCatalogScreenProjection
    let isBusy: Bool
    let disabledReason: String?
    let focusedCheckpointID: String?
    let selectedCheckpointID: String?
    let keyboardFocus: FocusState<Bool>.Binding
    let transferRegistry: ModelCatalogTransferStateRegistry
    let transferTopologyVersion: UInt64
    let onCommand: (ModelCatalogScreenCommand) -> Void

    @State private var layoutMode = ModelCheckpointLayoutMode.stacked
    private let layoutPolicy = ModelCheckpointLayoutPolicy()

    static func == (
        lhs: ModelCheckpointCatalogSurface,
        rhs: ModelCheckpointCatalogSurface
    ) -> Bool {
        lhs.presentation == rhs.presentation
            && lhs.isBusy == rhs.isBusy
            && lhs.disabledReason == rhs.disabledReason
            && lhs.focusedCheckpointID == rhs.focusedCheckpointID
            && lhs.selectedCheckpointID == rhs.selectedCheckpointID
            && lhs.keyboardFocus.wrappedValue
                == rhs.keyboardFocus.wrappedValue
            && lhs.transferRegistry === rhs.transferRegistry
            && lhs.transferTopologyVersion
                == rhs.transferTopologyVersion
    }

    var body: some View {
        VStack(spacing: 0) {
            ModelCheckpointColumnHeader(layoutMode: layoutMode)
            ForEach(presentation.sections) { section in
                if let title = section.title {
                    ModelCheckpointFamilyHeader(
                        title: title,
                        provider: section.providerName
                    )
                }
                ForEach(section.rows) { row in
                    ModelCheckpointCatalogRow(
                        row: row,
                        layoutMode: layoutMode,
                        isBusy: isBusy,
                        disabledReason: disabledReason,
                        isKeyboardFocused:
                            keyboardFocus.wrappedValue
                                && focusedCheckpointID == row.id,
                        isSelected: selectedCheckpointID == row.id,
                        transferCell: transferRegistry.cellIfPresent(
                            for: row.selectedArtifactID
                        ),
                        onCommand: onCommand
                    )
                    .id(ModelCatalogHierarchyRowID.checkpoint(row.id))
                }
            }
            .id(layoutMode)
        }
        .background {
            LinearGradient(
                colors: [
                    TextifyVisualIdentity.cardSurfaceTop,
                    TextifyVisualIdentity.cardSurfaceBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
            .stroke(
                LinearGradient(
                    colors: [
                        TextifyVisualIdentity.panelHighlight,
                        TextifyVisualIdentity.separator.opacity(0.72),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
        .shadow(
            color: TextifyVisualIdentity.panelShadow,
            radius: 7,
            y: 3
        )
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updateLayoutMode(availableWidth: proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) {
                        _, availableWidth in
                        updateLayoutMode(availableWidth: availableWidth)
                    }
            }
        }
        .focusable()
        .focused(keyboardFocus)
        .accessibilityLabel("Model catalog")
    }

    private func updateLayoutMode(availableWidth: CGFloat) {
        let nextMode = layoutPolicy.mode(
            availableWidth: availableWidth,
            previous: layoutMode
        )
        if nextMode != layoutMode {
            layoutMode = nextMode
        }
    }
}

private struct ModelCheckpointColumnHeader: View {
    let layoutMode: ModelCheckpointLayoutMode
    private let metrics = ModelCheckpointLayoutMetrics.current

    var body: some View {
        Group {
            switch layoutMode {
            case .wide:
                HStack(spacing: metrics.columnSpacing) {
                    Text("Model")
                        .frame(
                            minWidth: metrics.modelColumnFloor,
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    Text("Quality")
                        .frame(
                            width: metrics.qualityColumnFloor,
                            alignment: .leading
                        )
                    Text("Speed")
                        .frame(
                            width: metrics.speedColumnFloor,
                            alignment: .leading
                        )
                    Text("State")
                        .frame(
                            width: metrics.stateColumnFloor,
                            alignment: .leading
                        )
                    Text("Action")
                        .frame(
                            width: metrics.actionColumnFloor,
                            alignment: .leading
                        )
                }
                .padding(
                    .horizontal,
                    metrics.horizontalPadding / 2
                )
            case .stacked:
                Text("Model Details")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(
                        .horizontal,
                        metrics.horizontalPadding / 2
                    )
            }
        }
        .frame(minHeight: 38)
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .textCase(.uppercase)
        .tracking(0.9)
        .foregroundStyle(.secondary)
        .background(Color.primary.opacity(0.025))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Model, Quality, Speed, State, Action"
        )
    }
}

private struct ModelCheckpointFamilyHeader: View {
    let title: String
    let provider: String?
    private let metrics = ModelCheckpointLayoutMetrics.current

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            if let provider {
                Text(provider)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, metrics.horizontalPadding / 2)
        .frame(minHeight: 48)
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ModelCheckpointCatalogRow: View {
    let row: ModelCatalogScreenRow
    let layoutMode: ModelCheckpointLayoutMode
    let isBusy: Bool
    let disabledReason: String?
    let isKeyboardFocused: Bool
    let isSelected: Bool
    let transferCell: ModelCatalogTransferStateCell?
    let onCommand: (ModelCatalogScreenCommand) -> Void
    private let metrics = ModelCheckpointLayoutMetrics.current

    var body: some View {
        Group {
            switch layoutMode {
            case .wide:
                HStack(
                    alignment: .center,
                    spacing: metrics.columnSpacing
                ) {
                    identity
                        .frame(
                            minWidth: metrics.modelColumnFloor,
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    ModelCheckpointSignalMetric(
                        level: row.qualityLevel,
                        label: row.qualityLabel
                    )
                    .frame(
                        width: metrics.qualityColumnFloor,
                        alignment: .leading
                    )
                    ModelCheckpointSignalMetric(
                        level: row.speedLevel,
                        label: row.speedLabel
                    )
                    .frame(
                        width: metrics.speedColumnFloor,
                        alignment: .leading
                    )
                    state
                        .frame(
                            width: metrics.stateColumnFloor,
                            alignment: .leading
                        )
                    actions
                        .frame(
                            width: metrics.actionColumnFloor,
                            alignment: .leading
                        )
                }
                .padding(
                    .horizontal,
                    metrics.horizontalPadding / 2
                )
                .padding(.vertical, 11)
            case .stacked:
                VStack(alignment: .leading, spacing: 10) {
                    identity
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .flexible(),
                                alignment: .topLeading
                            ),
                            GridItem(
                                .flexible(),
                                alignment: .topLeading
                            ),
                        ],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        labeledField("Quality") {
                            ModelCheckpointSignalMetric(
                                level: row.qualityLevel,
                                label: row.qualityLabel
                            )
                        }
                        labeledField("Speed") {
                            ModelCheckpointSignalMetric(
                                level: row.speedLevel,
                                label: row.speedLabel
                            )
                        }
                        labeledField("State") {
                            state
                        }
                        labeledField("Action") {
                            actions
                        }
                    }
                    .padding(.leading, 28)
                }
                .padding(
                    .horizontal,
                    metrics.horizontalPadding / 2
                )
                .padding(.vertical, 11)
            }
        }
        .frame(minHeight: layoutMode == .wide ? 86 : 118)
        .contentShape(Rectangle())
        .onTapGesture {
            onCommand(.inspect(checkpointID: row.checkpointID))
        }
        .contextMenu {
            secondaryActions
        }
        .background {
            if row.isActive {
                LinearGradient(
                    colors: [
                        TextifyVisualIdentity.consoleSelection.opacity(0.9),
                        TextifyVisualIdentity.voiceViolet.opacity(0.055),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .overlay(alignment: .leading) {
            if row.isActive {
                Capsule(style: .continuous)
                    .fill(TextifyVisualIdentity.voiceViolet)
                    .frame(width: 3)
                    .padding(.vertical, 11)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 42)
        }
        .overlay {
            if isKeyboardFocused {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        TextifyVisualIdentity.voiceViolet.opacity(0.72),
                        lineWidth: 2
                    )
                    .padding(3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilitySummary)
        .accessibilityValue(
            transferCell?.snapshot.accessibilityValue
                ?? row.lifecycleState
                ?? String(localized: "Not installed")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            accessibilityActions
        }
        .accessibilityIdentifier("model-checkpoint-\(row.id)")
        .help(disabledReason ?? "")
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(
                systemName:
                    row.isActive
                    ? "circle.inset.filled"
                    : "circle"
            )
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(
                row.isActive
                    ? TextifyVisualIdentity.voiceViolet
                    : Color.secondary.opacity(0.55)
            )
            .accessibilityHidden(true)

            ModelCheckpointProviderMark(
                provider: row.provider,
                logoKey: row.providerLogoKey,
                isActive: row.isActive
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let annotation = row.annotation.title {
                    TextifyStatusBadge(
                        title: annotation.uppercased(),
                        tone:
                            row.annotation == .inUse
                            ? .success
                            : .accent
                    )
                    .fixedSize(horizontal: true, vertical: true)
                }
                ModelCheckpointVersionControl(
                    row: row,
                    isBusy: isBusy,
                    onUse: {
                        onCommand(
                            .use(
                                checkpointID: row.checkpointID,
                                artifactID: $0
                            )
                        )
                    }
                )
                Text(row.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let languageCompatibilityNote =
                    row.languageCompatibilityNote
                {
                    Label(
                        languageCompatibilityNote,
                        systemImage: "character.bubble"
                    )
                    .font(.caption2)
                    .foregroundStyle(TextifyVisualIdentity.warmWarning)
                }
                if row.versionCount == 1 {
                    Text(row.selectedArtifactName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var state: some View {
        Group {
            if let transferCell {
                ModelCheckpointTransferStateView(cell: transferCell)
            } else if let lifecycleState = row.lifecycleState {
                Text(lifecycleState)
                    .foregroundStyle(
                        lifecycleState.hasPrefix("Failed")
                            || lifecycleState == "Revoked"
                            ? TextifyVisualIdentity.warmWarning
                            : .secondary
                    )
            } else {
                Color.clear
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch row.primaryAction {
            case .use:
                Button("Use") {
                    onCommand(
                        .use(
                            checkpointID: row.checkpointID,
                            artifactID: row.selectedArtifactID
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            case .cancel:
                Button("Cancel") {
                    guard let attemptID = row.transferAttemptID else {
                        return
                    }
                    onCommand(.cancel(attemptID: attemptID))
                }
                    .disabled(isBusy)
            case .retry:
                Button("Retry") {
                    guard let attemptID = row.transferAttemptID else {
                        return
                    }
                    onCommand(.retry(attemptID: attemptID))
                }
                    .disabled(isBusy)
            case .none:
                EmptyView()
            }
            if row.primaryAction == .use, !row.isInstalled {
                Text(row.downloadSize)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var secondaryActions: some View {
        Button(
            "Inspect",
            systemImage: "info.circle"
        ) {
            onCommand(.inspect(checkpointID: row.checkpointID))
        }
        if row.installOnlyAvailable {
            Button(
                "Install Only",
                systemImage: "arrow.down.circle"
            ) {
                onCommand(
                    .installOnly(
                        checkpointID: row.checkpointID,
                        artifactID: row.selectedArtifactID
                    )
                )
            }
        }
        if row.isInstalled {
            Button(
                "Reveal in Finder",
                systemImage: "folder"
            ) {
                onCommand(.reveal(artifactID: row.selectedArtifactID))
            }
            .disabled(isBusy)
            Button(
                "Verify Integrity",
                systemImage: "checkmark.seal"
            ) {
                onCommand(.verify(artifactID: row.selectedArtifactID))
            }
            .disabled(isBusy)
            Button(
                "Reinstall (\(row.downloadSize))",
                systemImage: "arrow.clockwise"
            ) {
                onCommand(
                    .installOnly(
                        checkpointID: row.checkpointID,
                        artifactID: row.selectedArtifactID
                    )
                )
            }
            .disabled(
                isBusy
                    || row.selectedArtifactIsRevoked
                    || !row.selectedArtifactAllowsOperations
            )
            Button(
                "Remove",
                systemImage: "trash",
                role: .destructive
            ) {
                onCommand(.remove(artifactID: row.selectedArtifactID))
            }
            .disabled(isBusy)
        }
    }

    @ViewBuilder
    private var accessibilityActions: some View {
        Button("Inspect") {
            onCommand(.inspect(checkpointID: row.checkpointID))
        }
        switch row.primaryAction {
        case .use:
            Button("Use") {
                onCommand(
                    .use(
                        checkpointID: row.checkpointID,
                        artifactID: row.selectedArtifactID
                    )
                )
            }
        case .cancel:
            if let attemptID = row.transferAttemptID {
                Button("Cancel") {
                    onCommand(.cancel(attemptID: attemptID))
                }
            }
        case .retry:
            if let attemptID = row.transferAttemptID {
                Button("Retry") {
                    onCommand(.retry(attemptID: attemptID))
                }
            }
        case .none:
            EmptyView()
        }
        if row.versionCount > 1 {
            ForEach(row.versionOptions.filter(\.isActionable)) { option in
                Button("Use \(option.displayName)") {
                    onCommand(
                        .use(
                            checkpointID: row.checkpointID,
                            artifactID: option.id
                        )
                    )
                }
            }
        }
        if row.isInstalled {
            Button("Verify Integrity") {
                onCommand(.verify(artifactID: row.selectedArtifactID))
            }
            Button("Reveal in Finder") {
                onCommand(.reveal(artifactID: row.selectedArtifactID))
            }
            Button("Remove") {
                onCommand(.remove(artifactID: row.selectedArtifactID))
            }
        }
    }

    private func labeledField<Content: View>(
        _ label: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.bold().monospaced())
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            content()
        }
    }
}

private struct ModelCheckpointSignalMetric: View {
    let level: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(1...5, id: \.self) { index in
                    RoundedRectangle(
                        cornerRadius: 1.5,
                        style: .continuous
                    )
                    .fill(
                        index <= level
                            ? TextifyVisualIdentity.voiceViolet
                            : Color.primary.opacity(0.13)
                    )
                    .frame(width: 4, height: CGFloat(5 + index * 3))
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            level == 0 ? label : "\(label), \(level) of 5"
        )
    }
}

private struct ModelCheckpointProviderMark: View {
    let provider: ModelProviderIdentity
    let logoKey: ModelProviderLogoKey?
    let isActive: Bool

    var body: some View {
        Group {
            switch logoKey {
            case let .asset(name):
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .padding(provider.logoInset)
            case let .system(name):
                Image(systemName: name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(provider.accent)
            case let .monogram(mark):
                Text(mark)
                    .font(
                        .system(
                            size: mark.count > 1 ? 9 : 14,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(provider.accent)
            case .none:
                EmptyView()
            }
        }
        .frame(width: 30, height: 30)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    provider.accent.opacity(isActive ? 0.58 : 0.24),
                    lineWidth: isActive ? 1.5 : 1
                )
        }
        .accessibilityLabel(provider.name)
    }
}

private struct ModelCheckpointTransferStateView: View {
    @Bindable var cell: ModelCatalogTransferStateCell

    var body: some View {
        Text(cell.snapshot.visualValue)
            .foregroundStyle(.secondary)
            .accessibilityValue(cell.snapshot.accessibilityValue)
    }
}

private struct ModelCheckpointVersionControl: View {
    let row: ModelCatalogScreenRow
    let isBusy: Bool
    let onUse: (String) -> Void

    @State private var showsPopover = false
    @State private var showsComparison = false

    var body: some View {
        Group {
            switch row.versionRoute {
            case .none:
                EmptyView()
            case .popover:
                Button("\(row.versionCount) versions") {
                    showsPopover = true
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TextifyVisualIdentity.voiceViolet)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .popover(isPresented: $showsPopover) {
                    ModelVersionChoiceView(
                        row: row,
                        isBusy: isBusy,
                        onUse: onUse
                    )
                }
            case .comparisonSheet:
                Button("Compare \(row.versionCount) versions") {
                    showsComparison = true
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TextifyVisualIdentity.voiceViolet)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .sheet(isPresented: $showsComparison) {
                    ModelVersionComparisonSheet(
                        row: row,
                        isBusy: isBusy,
                        onUse: onUse
                    )
                }
            }
        }
    }
}

private struct ModelVersionChoiceView: View {
    let row: ModelCatalogScreenRow
    let isBusy: Bool
    let onUse: (String) -> Void

    @State private var selectedArtifactID: String

    init(
        row: ModelCatalogScreenRow,
        isBusy: Bool,
        onUse: @escaping (String) -> Void
    ) {
        self.row = row
        self.isBusy = isBusy
        self.onUse = onUse
        _selectedArtifactID = State(
            initialValue: row.selectedArtifactID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(row.title)
                .font(.headline)
            Text("Choose the version Textify should use.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(row.versionOptions) { option in
                Button {
                    selectedArtifactID = option.id
                } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Image(
                            systemName:
                                selectedArtifactID == option.id
                                ? "circle.inset.filled"
                                : "circle"
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(option.displayName)
                                    .font(.callout.weight(.semibold))
                                if option.isRecommended {
                                    TextifyStatusBadge(
                                        title: String(
                                            localized: "Recommended"
                                        ).uppercased(),
                                        tone: .accent
                                    )
                                    .fixedSize(
                                        horizontal: true,
                                        vertical: true
                                    )
                                }
                            }
                            Text(
                                "\(option.runtime) • \(option.downloadSize) • \(option.state)"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            Text(option.accuracyTradeoff)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                            if !option.isActionable {
                                Text(option.compatibility)
                                    .font(.caption2)
                                    .foregroundStyle(
                                        TextifyVisualIdentity.warmWarning
                                    )
                                    .fixedSize(
                                        horizontal: false,
                                        vertical: true
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(!option.isActionable)
            }

            Divider()
            HStack {
                Spacer()
                Button("Use Selected Version") {
                    guard let option = selectedOption else {
                        return
                    }
                    onUse(option.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isBusy
                        || selectedArtifactID == row.selectedArtifactID
                        || selectedOption == nil
                )
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private var selectedOption: ModelCatalogScreenVersionOption? {
        row.versionOptions.first {
            $0.id == selectedArtifactID && $0.isActionable
        }
    }
}

private struct ModelVersionComparisonSheet: View {
    let row: ModelCatalogScreenRow
    let isBusy: Bool
    let onUse: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedArtifactID: String

    init(
        row: ModelCatalogScreenRow,
        isBusy: Bool,
        onUse: @escaping (String) -> Void
    ) {
        self.row = row
        self.isBusy = isBusy
        self.onUse = onUse
        _selectedArtifactID = State(
            initialValue: row.selectedArtifactID
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Compare Versions")
                        .font(.title2.bold())
                    Text(row.title)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close", action: dismiss.callAsFunction)
            }
            .padding(18)

            Divider()

            Grid(
                alignment: .leading,
                horizontalSpacing: 14,
                verticalSpacing: 0
            ) {
                GridRow {
                    Text("Select")
                    Text("Version")
                    Text("Quality")
                    Text("Speed")
                    Text("Download Size")
                    Text("State")
                }
                .font(.caption2.bold().monospaced())
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.vertical, 9)

                ForEach(row.versionOptions) { option in
                    GridRow {
                        Button {
                            selectedArtifactID = option.id
                        } label: {
                            Image(
                                systemName:
                                    selectedArtifactID == option.id
                                    ? "circle.inset.filled"
                                    : "circle"
                            )
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.displayName)
                                .font(.callout.weight(.semibold))
                            Text(option.runtime)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if row.hasMultipleComparisonGroups,
                                let comparisonGroupID =
                                    option.comparisonGroupID
                            {
                                Text(comparisonGroupID)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(option.quality.title)
                        Text(option.speed.title)
                        Text(option.downloadSize)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.state)
                            if !option.isActionable {
                                Text(option.compatibility)
                                    .font(.caption2)
                                    .foregroundStyle(
                                        TextifyVisualIdentity.warmWarning
                                    )
                            }
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 10)
                    .disabled(!option.isActionable)
                }
            }
            .padding(.horizontal, 18)

            if let option = selectedOption {
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Text(option.accuracyTradeoff)
                    Text(option.expectedFinalization)
                    Text(option.requirements)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }

            Divider()
            HStack {
                Text(
                    selectedOption.map {
                        "Download: \($0.downloadSize)"
                    } ?? ""
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Use Selected Version") {
                    guard let option = selectedOption,
                        option.isActionable
                    else {
                        return
                    }
                    onUse(option.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isBusy
                        || selectedArtifactID == row.selectedArtifactID
                        || selectedOption?.isActionable != true
                )
            }
            .padding(18)
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private var selectedOption: ModelCatalogScreenVersionOption? {
        row.versionOptions.first { $0.id == selectedArtifactID }
    }
}

struct VoiceCleaningFeatureCard: View {
    let row: ModelCheckpointRowPresentation?
    let isBusy: Bool
    let disabledReason: String?
    let onUse:
        (
            ModelCheckpointRowPresentation,
            ModelCatalogExactArtifactPresentation
        ) -> Void
    let onDisable: () -> Void
    let onInspect: (ModelCheckpointRowPresentation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.badge.minus")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(TextifyVisualIdentity.voiceViolet)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Voice Cleaning")
                        .font(.title3.bold())
                    Text(
                        "Reduce background noise locally before transcription."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if let row {
                    Button("Details") {
                        onInspect(row)
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            if let row {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(row.title)
                                .font(.headline)
                            ModelCheckpointVersionControl(
                                row: ModelCatalogScreenRow(row),
                                isBusy: isBusy,
                                onUse: { artifactID in
                                    guard let artifact =
                                        row.checkpoint.artifacts.first(
                                            where: { $0.id == artifactID }
                                        )
                                    else {
                                        return
                                    }
                                    onUse(row, artifact)
                                }
                            )
                        }
                        Text(
                            row.selectedArtifact.metadata.presentation
                                .displayName
                        )
                        .font(.callout)
                        Text(
                            row.selectedArtifact.row.model.accuracyTradeoff
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if row.isInstalled {
                        Toggle(
                            "Enable Voice Cleaning",
                            isOn: Binding(
                                get: { row.isActive },
                                set: { enabled in
                                    if enabled {
                                        onUse(row, row.selectedArtifact)
                                    } else {
                                        onDisable()
                                    }
                                }
                            )
                        )
                        .toggleStyle(.switch)
                        .disabled(
                            isBusy
                                || !row.selectedArtifact.row.compatibility
                                    .allowsModelOperations
                                || row.selectedArtifact.row.isRevoked
                        )
                    } else {
                        VStack(alignment: .trailing, spacing: 4) {
                            Button("Download and Enable") {
                                onUse(row, row.selectedArtifact)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                isBusy
                                    || !row.selectedArtifact.row.compatibility
                                        .allowsModelOperations
                                    || row.selectedArtifact.row.isRevoked
                            )
                            Text(row.downloadSize)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Voice Cleaner",
                    systemImage: "waveform.badge.exclamationmark",
                    description: Text(
                        "This version of Textify does not include a compatible voice cleaner."
                    )
                )
            }
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            row?.isActive == true
                                ? TextifyVisualIdentity.consoleSelection
                                : TextifyVisualIdentity.cardSurfaceTop,
                            TextifyVisualIdentity.cardSurfaceBottom,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            row?.isActive == true
                                ? TextifyVisualIdentity.voiceViolet.opacity(
                                    0.46
                                )
                                : TextifyVisualIdentity.panelHighlight,
                            TextifyVisualIdentity.separator.opacity(0.72),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: row?.isActive == true ? 1 : 0.8
                )
        }
        .shadow(
            color: TextifyVisualIdentity.panelShadow,
            radius: 7,
            y: 3
        )
        .help(disabledReason ?? "")
    }
}

struct ModelCheckpointInspectorSurface: View {
    let row: ModelCheckpointRowPresentation
    let isBusy: Bool
    let disabledReason: String?
    let onVerify: (ModelCatalogExactArtifactPresentation) -> Void
    let onReinstall: (ModelCatalogExactArtifactPresentation) -> Void
    let onReveal: (ModelCatalogExactArtifactPresentation) -> Void
    let onRemove: (ModelCatalogExactArtifactPresentation) -> Void

    @State private var showsTechnicalDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Checkpoint")
                    .font(.caption2.bold().monospaced())
                    .textCase(.uppercase)
                    .foregroundStyle(TextifyVisualIdentity.voiceViolet)
                Text(row.title)
                    .font(.title3.bold())
                Text(row.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            section("Overview") {
                ModelCheckpointInspectorFact(
                    label: "Purpose",
                    value:
                        row.selectedArtifact.row.model.purpose
                        == .voiceCleaning
                        ? "Voice cleaning"
                        : "Speech recognition"
                )
                ModelCheckpointInspectorFact(
                    label: "Provider",
                    value: row.providerName
                )
                ModelCheckpointInspectorFact(
                    label: "Languages",
                    value: languageDescription
                )
                ModelCheckpointInspectorFact(
                    label: "Quality evidence",
                    value:
                        row.selectedArtifact.row.model
                        .qualityEvidenceDescription
                        ?? "No signed comparable quality evidence"
                )
                ModelCheckpointInspectorFact(
                    label: "Speed evidence",
                    value:
                        row.selectedArtifact.row.model
                        .speedEvidenceDescription
                        ?? "No signed stable speed evidence"
                )
            }

            if !installedArtifacts.isEmpty {
                section("Installed Files") {
                    ForEach(installedArtifacts) { artifact in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(
                                        artifact.metadata.presentation
                                            .displayName
                                    )
                                    .font(.callout.weight(.semibold))
                                    Text(
                                        artifact.row.measuredLocalBytes.map {
                                            "About "
                                                + ByteCountFormatter.string(
                                                    fromByteCount: $0,
                                                    countStyle: .file
                                                )
                                        } ?? artifact.row.sizeDescription
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    Button(
                                        "Reveal in Finder",
                                        systemImage: "folder"
                                    ) {
                                        onReveal(artifact)
                                    }
                                    Button(
                                        "Verify Integrity",
                                        systemImage: "checkmark.seal"
                                    ) {
                                        onVerify(artifact)
                                    }
                                    Button(
                                        "Reinstall (\(artifact.row.sizeDescription))",
                                        systemImage: "arrow.clockwise"
                                    ) {
                                        onReinstall(artifact)
                                    }
                                    .disabled(
                                        artifact.row.isRevoked
                                            || !artifact.row.compatibility
                                                .allowsModelOperations
                                    )
                                    Button(
                                        "Remove",
                                        systemImage: "trash",
                                        role: .destructive
                                    ) {
                                        onRemove(artifact)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .disabled(isBusy)
                                .accessibilityLabel(
                                    "Maintenance actions for \(artifact.metadata.presentation.displayName)"
                                )
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            section("Versions") {
                ForEach(row.versionOptions) { option in
                    HStack(alignment: .top, spacing: 9) {
                        Image(
                            systemName:
                                option.id == row.selectedArtifactID
                                ? "circle.inset.filled"
                                : "circle"
                        )
                        .foregroundStyle(
                            option.id == row.selectedArtifactID
                                ? TextifyVisualIdentity.voiceViolet
                                : .secondary
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.displayName)
                                .font(.callout.weight(.semibold))
                            Text(
                                "\(option.runtime) • \(option.downloadSize) • \(option.state)"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            Text(option.accuracyTradeoff)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(
                                    horizontal: false,
                                    vertical: true
                                )
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            DisclosureGroup(
                "Technical Details",
                isExpanded: $showsTechnicalDetails
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ModelCheckpointInspectorFact(
                        label: "Exact Artifact",
                        value: row.selectedArtifact.id
                    )
                    ModelCheckpointInspectorFact(
                        label: "Artifact Format",
                        value: ModelCatalogVariantTerminology.artifactFormat(
                            row.selectedArtifact.metadata.artifactFormat
                        )
                    )
                    ModelCheckpointInspectorFact(
                        label: "Numeric Format",
                        value:
                            row.selectedArtifact.metadata.numericFormat.rawValue
                    )
                    ModelCheckpointInspectorFact(
                        label: "Runtime",
                        value: ModelCatalogVariantTerminology.runtime(
                            row.selectedArtifact.metadata.runtime
                        )
                    )
                    ModelCheckpointInspectorFact(
                        label: "Compute Route",
                        value: ModelCatalogVariantTerminology.computeRoute(
                            row.selectedArtifact.metadata.computeRoute
                        )
                    )
                    ModelCheckpointInspectorFact(
                        label: "Compatibility",
                        value: row.compatibilityExplanation
                    )
                    if let model = row.selectedArtifact.row.operationalModel {
                        ModelCheckpointInspectorFact(
                            label: "Provenance",
                            value:
                                "\(model.provenance.sourceName) • revision \(model.provenance.sourceRevision.prefix(12))"
                        )
                        ModelCheckpointInspectorFact(
                            label: "License",
                            value: model.licenses.map {
                                "\($0.spdxId) — \($0.name)"
                            }.joined(separator: " • ")
                        )
                    }
                }
                .padding(.top, 8)
            }
            .font(.callout.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(TextifyVisualIdentity.cardSurface)
        .help(disabledReason ?? "")
    }

    private var installedArtifacts: [ModelCatalogExactArtifactPresentation] {
        row.checkpoint.artifacts.filter(\.row.isInstalled)
    }

    private var languageDescription: String {
        let languages = Set(
            row.checkpoint.artifacts.flatMap {
                $0.row.operationalModel?.capabilities.languages ?? []
            }
        )
        if languages.contains("*") {
            return "Multilingual"
        }
        return languages.sorted().map {
            Locale.current.localizedString(forLanguageCode: $0)?
                .capitalized
                ?? $0.uppercased()
        }.joined(separator: ", ")
    }

    private func section<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(title)
                .font(.caption2.bold().monospaced())
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct ModelCheckpointInspectorFact: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
