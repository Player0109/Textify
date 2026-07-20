import SwiftUI

enum TextifyVisualIdentity {
    static let signatureElement = "Release line"

    static let voiceVioletHex = "#7667F2"
    static let readyMintHex = "#34C892"
    static let recordCoralHex = "#FF5C68"

    static let voiceViolet = Color(red: 0.463, green: 0.404, blue: 0.949)
    static let readyMint = Color(red: 0.204, green: 0.784, blue: 0.573)
    static let recordCoral = Color(red: 1.000, green: 0.361, blue: 0.408)
    static let warmWarning = Color(red: 0.957, green: 0.620, blue: 0.180)
    static let slate = Color(red: 0.400, green: 0.439, blue: 0.522)
    static let consoleSelection = Color(red: 0.105, green: 0.153, blue: 0.225)
}

enum TextifyWindowMetrics {
    static let mainWidth: CGFloat = 1_080
    static let mainHeight: CGFloat = 720
    static let mainMinimumWidth: CGFloat = 920
    static let mainMinimumHeight: CGFloat = 620
    static let onboardingWidth: CGFloat = 820
    static let onboardingHeight: CGFloat = 560
    static let sidebarWidth: CGFloat = 220
    static let readableContentWidth: CGFloat = 820
}

enum TextifyReadinessPresentation {
    static func title(canDictate: Bool) -> String {
        canDictate ? "Ready to dictate" : "Finish setup"
    }

    static func detail(canDictate: Bool, triggerName: String) -> String {
        if canDictate {
            return "Hold \(triggerName), speak, then release to type."
        }
        return "Review Dictation, Models, and Privacy before your first dictation."
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
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tone.color.opacity(0.13), in: Capsule(style: .continuous))
            .accessibilityLabel(title)
    }
}

struct TextifyCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.035 : 0.18),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.08), lineWidth: 1)
            }
    }
}

struct TextifyPaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .tracking(-0.8)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)

            LinearGradient(
                colors: [
                    TextifyVisualIdentity.voiceViolet,
                    TextifyVisualIdentity.readyMint.opacity(0.72),
                    Color.clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 118, height: 2)
            .padding(.top, 7)
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
                .font(.system(.headline, design: .rounded, weight: .semibold))
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
            .font(.system(.callout, design: .rounded, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color.primary.opacity(0.12), Color.primary.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
    }
}

extension SettingsPane {
    var productionSubtitle: String {
        switch self {
        case .general:
            return "Readiness, startup, and the way Textify lives on your Mac."
        case .dictation:
            return "Choose how dictation starts and confirm your trigger."
        case .models:
            return "Pick the local speech model that fits your language and speed."
        case .privacy:
            return "Control permissions and the apps where Textify stays silent."
        case .advanced:
            return "Inspect runtime health and export privacy-safe diagnostics."
        }
    }
}
