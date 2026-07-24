import SwiftUI

struct ModelCatalogVariantComparisonHeader: View {
    let sizeLabel: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            header(for: .wide)
                .frame(minWidth: ModelCatalogVariantComparisonLayout.wideMinimumWidth)
            header(for: .medium)
                .frame(minWidth: ModelCatalogVariantComparisonLayout.mediumMinimumWidth)
            header(for: .narrow)
        }
        .font(.caption2.bold().monospaced())
        .foregroundStyle(.secondary)
        .background(Color.primary.opacity(0.025))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func header(
        for layout: ModelCatalogVariantComparisonLayout
    ) -> some View {
        switch layout {
        case .wide:
            HStack(spacing: 10) {
                Text("VARIANT")
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ARTIFACT FORMAT")
                    Text("NUMERIC FORMAT")
                }
                    .frame(width: 118, alignment: .leading)
                Text("QUALITY")
                    .frame(width: 90, alignment: .leading)
                Text("SPEED")
                    .frame(width: 90, alignment: .leading)
                Text(sizeLabel.uppercased())
                    .frame(width: 74, alignment: .leading)
                Text("COMPUTE ROUTE")
                    .frame(width: 112, alignment: .leading)
                Text("STATE")
                    .frame(width: 104, alignment: .leading)
                Text("ACTION")
                    .frame(width: 124, alignment: .leading)
            }
            .padding(.leading, 48)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
        case .medium:
            HStack(spacing: 10) {
                Text("VARIANT")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("STATE")
                    .frame(width: 118, alignment: .leading)
                Text("ACTION")
                    .frame(width: 124, alignment: .leading)
            }
            .padding(.leading, 48)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
        case .narrow:
            Text("MODEL VARIANTS")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 48)
                .padding(.trailing, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 34)
        }
    }
}

struct ModelCatalogVariantComparisonRow: View {
    let model: ProductionModelPresentation
    let presentation: ModelCatalogVariantComparisonPresentation
    let isSelected: Bool
    let isActivating: Bool
    let isBusy: Bool
    let install: ModelCatalogInstallPresentation?
    let actions: Set<ModelCatalogRowAction>
    let onSelect: () -> Void
    let onUse: () -> Void
    let onDisable: () -> Void
    let onInstall: () -> Void
    let onCancelInstall: () -> Void
    let onRetryInstall: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                row(for: .narrow)
            } else {
                ViewThatFits(in: .horizontal) {
                    row(for: .wide)
                        .frame(
                            minWidth:
                                ModelCatalogVariantComparisonLayout
                                    .wideMinimumWidth
                        )
                    row(for: .medium)
                        .frame(
                            minWidth:
                                ModelCatalogVariantComparisonLayout
                                    .mediumMinimumWidth
                        )
                    row(for: .narrow)
                }
            }
        }
        .background(rowBackground)
        .overlay {
            if isSelected
                && (
                    colorSchemeContrast == .increased
                        || differentiateWithoutColor
                ) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary, lineWidth: 2)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 40)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func row(
        for layout: ModelCatalogVariantComparisonLayout
    ) -> some View {
        switch layout {
        case .wide:
            HStack(spacing: 10) {
                variant
                    .frame(maxWidth: .infinity, alignment: .leading)
                formatAndNumeric
                    .frame(width: 118, alignment: .leading)
                metric(presentation.quality)
                    .frame(width: 90, alignment: .leading)
                metric(presentation.speed)
                    .frame(width: 90, alignment: .leading)
                Text(presentation.size)
                    .frame(width: 74, alignment: .leading)
                Text(presentation.computeRoute)
                    .frame(width: 112, alignment: .leading)
                state
                    .frame(width: 104, alignment: .leading)
                actionControls
                    .frame(width: 124, alignment: .leading)
            }
            .font(.caption)
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .frame(minHeight: 62)
        case .medium:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    variant
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if layout.showsInlineState {
                        state
                            .frame(width: 118, alignment: .leading)
                    }
                    actionControls
                        .frame(width: 124, alignment: .leading)
                }
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), alignment: .topLeading),
                        count: 3
                    ),
                    alignment: .leading,
                    spacing: 9
                ) {
                    ForEach(layout.labeledFields, id: \.self) {
                        comparisonField($0)
                    }
                }
                .padding(.leading, 34)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        case .narrow:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    variant
                        .frame(maxWidth: .infinity, alignment: .leading)
                    actionControls
                }
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .topLeading),
                        GridItem(.flexible(), alignment: .topLeading),
                    ],
                    alignment: .leading,
                    spacing: 9
                ) {
                    ForEach(layout.labeledFields, id: \.self) {
                        comparisonField($0)
                    }
                }
                .padding(.leading, 34)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    private var variant: some View {
        HStack(spacing: 9) {
            Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(
                    isSelected
                        ? TextifyVisualIdentity.voiceViolet
                        : Color.secondary.opacity(0.65)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(presentation.variant)
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if presentation.isRecommended {
                        Text("RECOMMENDED")
                            .font(.caption2.bold().monospaced())
                            .foregroundStyle(TextifyVisualIdentity.voiceViolet)
                            .accessibilityLabel("Catalog recommendation")
                    }
                    if presentation.isFallback {
                        Text("SIGNED FALLBACK")
                            .font(.caption2.bold().monospaced())
                            .foregroundStyle(TextifyVisualIdentity.warmWarning)
                            .accessibilityLabel("Signed compatibility fallback")
                    }
                }
                Text(presentation.runtime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var formatAndNumeric: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(presentation.artifactFormat)
            Text(presentation.numericFormat)
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Artifact Format \(presentation.artifactFormat), "
                + "Numeric Format \(presentation.numericFormat)"
        )
    }

    private var state: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(presentation.state)
                .font(.caption)
                .foregroundStyle(stateColor)
                .fixedSize(horizontal: false, vertical: true)
            if let percentText = install?.percentText {
                Text(percentText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !presentation.isActionable {
                Text(presentation.compatibilityExplanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(
            presentation.isActionable
                ? presentation.state
                : presentation.compatibilityExplanation
        )
        .accessibilityValue(
            presentation.isActionable
                ? presentation.state
                : "\(presentation.state). \(presentation.compatibilityExplanation)"
        )
    }

    private func metric(
        _ value: ModelCatalogVariantComparisonMetric
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.title)
                .foregroundStyle(metricColor(value))
                .fixedSize(horizontal: false, vertical: true)
            if let detail = value.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func labeledMetric(
        _ label: String,
        _ value: ModelCatalogVariantComparisonMetric
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            fieldLabel(label)
            metric(value)
        }
        .accessibilityElement(children: .combine)
    }

    private func labeledField(
        _ label: String,
        _ value: String,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            fieldLabel(label)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func comparisonField(
        _ field: ModelCatalogVariantComparisonColumn
    ) -> some View {
        switch field {
        case .artifactFormat:
            labeledField("Artifact Format", presentation.artifactFormat)
        case .numericFormat:
            labeledField(
                "Numeric Format",
                presentation.numericFormat,
                monospaced: true
            )
        case .quality:
            labeledMetric("Quality", presentation.quality)
        case .speed:
            labeledMetric("Speed", presentation.speed)
        case .size:
            labeledField(presentation.sizeLabel, presentation.size)
        case .computeRoute:
            labeledField("Compute Route", presentation.computeRoute)
        case .state:
            labeledField("State", presentation.state)
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.caption2.bold().monospaced())
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var actionControls: some View {
        HStack(spacing: 5) {
            if isActivating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Preparing model")
            } else {
                primaryAction
            }

            Menu {
                if actions.contains(.details) {
                    Button("Inspect", systemImage: "info.circle", action: onSelect)
                }
                if actions.contains(.reinstall),
                   presentation.primaryAction != .reinstall {
                    Button("Reinstall", systemImage: "arrow.clockwise", action: onInstall)
                        .disabled(
                            isBusy
                                || !presentation.isActionable
                                || ProductionModelInstallConfiguration.current == nil
                        )
                }
                if actions.contains(.delete) {
                    Button(
                        "Delete",
                        systemImage: "trash",
                        role: .destructive,
                        action: onDelete
                    )
                    .disabled(presentation.isActive || isBusy)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More actions for \(presentation.variant)")
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch presentation.primaryAction {
        case .use:
            Button(model.useLabel, action: onUse)
                .disabled(isBusy || !presentation.isActionable)
                .help(presentation.compatibilityExplanation)
        case .disable:
            Button("Disable", action: onDisable)
                .disabled(isBusy)
        case .install:
            Button(model.installLabel, action: onInstall)
                .disabled(
                    isBusy
                        || !presentation.isActionable
                        || ProductionModelInstallConfiguration.current == nil
                )
                .help(presentation.compatibilityExplanation)
        case .reinstall:
            Button("Reinstall", action: onInstall)
                .disabled(
                    isBusy
                        || !presentation.isActionable
                        || ProductionModelInstallConfiguration.current == nil
                )
                .help(presentation.compatibilityExplanation)
        case .cancelInstall:
            Button("Cancel", action: onCancelInstall)
        case .retryInstall:
            Button("Retry", action: onRetryInstall)
                .disabled(isBusy || !presentation.isActionable)
                .help(presentation.compatibilityExplanation)
        case .none:
            Text("—")
                .foregroundStyle(.tertiary)
        }
    }

    private var stateColor: Color {
        if presentation.isActive {
            return TextifyVisualIdentity.readyMint
        }
        if !presentation.isActionable {
            return TextifyVisualIdentity.warmWarning
        }
        switch install?.state.phase {
        case .paused, .waitingForNetwork, .waitingForCatalogCheck,
             .failed, .interrupted, .revoked:
            return TextifyVisualIdentity.warmWarning
        case .queued, .checkingSpace, .downloading, .verifying, .installing,
             .installed, .cancelled, .none:
            return .secondary
        }
    }

    private func metricColor(
        _ metric: ModelCatalogVariantComparisonMetric
    ) -> Color {
        switch metric {
        case .reference, .compared:
            .primary
        case .unrated, .noBaseline, .notComparable:
            .secondary
        }
    }

    private var rowBackground: Color {
        guard isSelected else {
            return .clear
        }
        return colorScheme == .dark
            ? TextifyVisualIdentity.consoleSelection
            : TextifyVisualIdentity.voiceViolet.opacity(0.075)
    }
}

struct ModelCatalogVariantsAboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("About Model Variants", systemImage: "square.stack.3d.up")
                .font(.system(.headline, design: .rounded, weight: .semibold))

            explanation(
                title: "Artifact Format",
                text: ModelCatalogVariantTerminology.artifactFormatExplanation
            )
            explanation(
                title: "Numeric Format",
                text: ModelCatalogVariantTerminology.numericFormatExplanation
            )
            explanation(
                title: "Tradeoffs & Evidence",
                text: ModelCatalogVariantTerminology.tradeoffExplanation
            )
        }
        .padding(18)
        .frame(width: 380, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func explanation(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
