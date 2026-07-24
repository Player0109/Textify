import SwiftUI

enum TextifyVisualIdentity {
    static let signatureElement = "Spokenly blue selection"

    static let voiceVioletHex = "#0A84FF"
    static let readyMintHex = "#30D158"
    static let recordCoralHex = "#FF453A"

    static let voiceViolet = Color(red: 0.039, green: 0.518, blue: 1.000)
    static let readyMint = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let recordCoral = Color(red: 1.000, green: 0.271, blue: 0.227)
    static let warmWarning = Color(red: 1.000, green: 0.749, blue: 0.078)
    static let slate = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let windowSurface = Color(red: 0.110, green: 0.110, blue: 0.118)
    static let sidebarSurface = Color(red: 0.092, green: 0.092, blue: 0.098)
    static let cardSurface = Color(red: 0.127, green: 0.127, blue: 0.135)
    static let raisedSurface = Color(red: 0.153, green: 0.153, blue: 0.163)
    static let separator = Color.white.opacity(0.105)
    static let consoleSelection = Color(red: 0.105, green: 0.165, blue: 0.247)
}

enum TextifyWindowMetrics {
    static let mainWidth: CGFloat = 1_080
    static let mainHeight: CGFloat = 700
    static let mainMinimumWidth: CGFloat = 1_060
    static let mainMinimumHeight: CGFloat = 666
    static let onboardingWidth: CGFloat = 820
    static let onboardingHeight: CGFloat = 560
    static let sidebarWidth: CGFloat = 258
    static let readableContentWidth: CGFloat = 730
}

enum TextifyReadinessPresentation {
    static func title(canDictate: Bool) -> String {
        canDictate ? "Ready to dictate" : "Finish setup"
    }

    static func detail(canDictate: Bool, triggerName: String) -> String {
        if canDictate {
            return "Hold \(triggerName), speak, then release to type."
        }
        return "Review Dictation, Transcription Models, and Privacy before your first dictation."
    }
}

enum TextifyVoiceMarkState {
    case idle
    case ready
    case recording
    case processing
    case blocked

    var color: Color {
        switch self {
        case .idle:
            return TextifyVisualIdentity.slate
        case .ready:
            return TextifyVisualIdentity.readyMint
        case .recording:
            return TextifyVisualIdentity.recordCoral
        case .processing:
            return TextifyVisualIdentity.voiceViolet
        case .blocked:
            return TextifyVisualIdentity.warmWarning
        }
    }

    var animates: Bool {
        self == .recording || self == .processing
    }
}

struct TextifyVoiceMark: View {
    let state: TextifyVoiceMarkState
    var height: CGFloat = 24
    var animated = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let restingHeights: [Double] = [0.38, 0.68, 1.0, 0.58, 0.32]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !shouldAnimate)) { context in
            HStack(alignment: .center, spacing: max(2, height * 0.09)) {
                ForEach(restingHeights.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(state.color)
                        .frame(
                            width: max(2.5, height * 0.115),
                            height: barHeight(at: index, date: context.date)
                        )
                }
            }
            .frame(height: height)
        }
        .accessibilityHidden(true)
    }

    private var shouldAnimate: Bool {
        animated && state.animates && !reduceMotion
    }

    private func barHeight(at index: Int, date: Date) -> CGFloat {
        let base = restingHeights[index]
        guard shouldAnimate else {
            return max(3, height * base)
        }

        let time = date.timeIntervalSinceReferenceDate * 5.2
        let wave = (sin(time + Double(index) * 1.15) + 1) * 0.18
        return max(3, height * min(1, base * 0.72 + wave))
    }
}

struct TextifyStatusBadge: View {
    enum Tone {
        case neutral
        case accent
        case success
        case warning

        var color: Color {
            switch self {
            case .neutral:
                return TextifyVisualIdentity.slate
            case .accent:
                return TextifyVisualIdentity.voiceViolet
            case .success:
                return TextifyVisualIdentity.readyMint
            case .warning:
                return TextifyVisualIdentity.warmWarning
            }
        }
    }

    let title: String
    var tone: Tone = .neutral

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tone.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(title)
    }
}

struct TextifyCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TextifyVisualIdentity.cardSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(TextifyVisualIdentity.separator, lineWidth: 1)
            }
    }
}

struct TextifyPaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct TextifySectionLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TextifyKeycap: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(TextifyVisualIdentity.raisedSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(TextifyVisualIdentity.separator, lineWidth: 1)
            }
    }
}

extension SettingsPane {
    var productionSubtitle: String {
        switch self {
        case .general:
            return "Readiness, startup, and the way Textify lives on your Mac."
        case .dictation:
            return "Choose how dictation starts and confirm your trigger."
        case .transcriptionModels:
            return "Pick the local speech model that fits your language and speed."
        case .voiceCleaning:
            return "Optionally clean recorded speech before it reaches transcription."
        case .privacy:
            return "Control permissions and the apps where Textify stays silent."
        case .logs:
            return "Inspect privacy-safe runtime events without leaving Textify."
        case .advanced:
            return "Inspect runtime health and export privacy-safe diagnostics."
        }
    }
}
