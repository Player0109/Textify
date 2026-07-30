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
    static let windowSurface = Color(red: 0.067, green: 0.082, blue: 0.110)
    static let sidebarSurface = Color(red: 0.051, green: 0.067, blue: 0.094)
    static let cardSurface = Color(red: 0.098, green: 0.122, blue: 0.161)
    static let raisedSurface = Color(red: 0.145, green: 0.176, blue: 0.227)
    static let separator = Color.white.opacity(0.13)
    static let consoleSelection = Color(red: 0.063, green: 0.176, blue: 0.310)

    static let cardSurfaceTop = Color(red: 0.118, green: 0.145, blue: 0.188)
    static let cardSurfaceBottom = Color(red: 0.082, green: 0.102, blue: 0.137)
    static let panelHighlight = Color.white.opacity(0.16)
    static let panelShadow = Color.black.opacity(0.30)
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
        HStack(spacing: 5) {
            Circle()
                .fill(tone.color)
                .frame(width: 5, height: 5)
                .shadow(color: tone.color.opacity(0.55), radius: 2)

            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .tracking(0.25)
        .foregroundStyle(tone.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tone.color.opacity(0.17),
                            tone.color.opacity(0.09)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(tone.color.opacity(0.27), lineWidth: 0.75)
        }
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .ignore)
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
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    TextifyVisualIdentity.cardSurfaceTop,
                                    TextifyVisualIdentity.cardSurfaceBottom
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.035),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                TextifyVisualIdentity.panelHighlight,
                                TextifyVisualIdentity.separator.opacity(0.72)
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
    }
}

struct TextifyPaneHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(TextifyVisualIdentity.voiceViolet.opacity(0.11))

                TextifyVoiceMark(state: .processing, height: 15)
            }
            .frame(width: 36, height: 36)
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(
                        TextifyVisualIdentity.voiceViolet.opacity(0.22),
                        lineWidth: 0.75
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(
                        .system(
                            size: 24,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .tracking(-0.25)

                Text(subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct TextifySectionLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TextifyVisualIdentity.voiceViolet,
                            TextifyVisualIdentity.voiceViolet.opacity(0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 15)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(
                        .system(
                            size: 13,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .tracking(0.1)

                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TextifyKeycap: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                TextifyVisualIdentity.raisedSurface,
                                TextifyVisualIdentity.cardSurface
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                TextifyVisualIdentity.separator
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.32), radius: 2, y: 2)
            .accessibilityLabel(title)
    }
}

struct TextifyAcousticBackdrop: View {
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    var body: some View {
        ZStack {
            TextifyVisualIdentity.windowSurface

            if !reduceTransparency {
                LinearGradient(
                    colors: [
                        TextifyVisualIdentity.sidebarSurface.opacity(0.52),
                        .clear,
                        TextifyVisualIdentity.cardSurface.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        TextifyVisualIdentity.voiceViolet.opacity(0.095),
                        TextifyVisualIdentity.voiceViolet.opacity(0.018),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: 430
                )

                TextifyAcousticTrace()
                    .stroke(
                        LinearGradient(
                            colors: [
                                .clear,
                                TextifyVisualIdentity.voiceViolet.opacity(0.12),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(
                            lineWidth: 0.75,
                            lineCap: .round
                        )
                    )
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct TextifyAcousticTrace: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let startX = rect.width * 0.36
        let endX = rect.maxX + 24

        for index in 0..<4 {
            let baseline = rect.height * (0.09 + CGFloat(index) * 0.045)
            let amplitude = rect.height * (0.028 + CGFloat(index) * 0.006)

            path.move(to: CGPoint(x: startX, y: baseline))
            path.addCurve(
                to: CGPoint(x: endX, y: baseline + amplitude * 0.18),
                control1: CGPoint(
                    x: rect.width * 0.57,
                    y: baseline - amplitude
                ),
                control2: CGPoint(
                    x: rect.width * 0.78,
                    y: baseline + amplitude
                )
            )
        }

        return path
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
