import AppKit
import SwiftUI
import TextifyRuntime

enum DictationOverlayPresentation {
    static func state(for status: DictationRuntimeStatus) -> RecordingOverlayState {
        if case .recording = status {
            return .recording(elapsedSeconds: 0)
        }
        if status == .blocked(.excludedApp) {
            return .blocked("Textify disabled for this app.")
        }
        switch status {
        case .cancelled:
            return .hidden
        case let .blocked(error):
            return .blocked(error.overlayMessage)
        case let .failed(error):
            return .blocked(error.overlayMessage)
        case .idle, .waitingForActivation, .processing, .inserting, .completed:
            return .hidden
        case .recording:
            return .recording(elapsedSeconds: 0)
        }
    }
}

private extension ProductionDictationError {
    var overlayMessage: String {
        switch self {
        case .readinessBlocked(.microphonePermissionDenied):
            return "Microphone access needed."
        case .readinessBlocked(.accessibilityPermissionDenied):
            return "Accessibility access needed."
        case .readinessBlocked(.noActiveModel),
             .readinessBlocked(.activeModelMissing):
            return "Install the dictation model."
        case .readinessBlocked(.activeModelRevoked):
            return "Choose a replacement dictation model."
        case .readinessBlocked(.activeModelNotReady):
            return "Model is still preparing."
        case .readinessBlocked(.transcriptionRuntimeFailed),
             .transcriptionNotReady,
             .transcriptionFailed:
            return "Transcription unavailable."
        case .microphoneChanged:
            return "Microphone changed. Try again."
        case .audioStartFailed, .audioFinishFailed, .audioConversionFailed:
            return "Microphone recording failed."
        case .insertionFailed:
            return "Text insertion failed."
        case .concurrentDictation:
            return "Dictation is already active."
        case .excludedApp:
            return "Textify disabled for this app."
        }
    }
}

@MainActor
protocol RecordingOverlayPresenting: AnyObject {
    func present(_ state: RecordingOverlayState)
}

private struct RecordingOverlayApplication {
    let name: String
    let icon: NSImage?

    static let unavailable = RecordingOverlayApplication(
        name: "Current app",
        icon: nil
    )
}

@MainActor
private protocol RecordingOverlayApplicationProviding {
    func currentApplication() -> RecordingOverlayApplication
}

@MainActor
private struct WorkspaceRecordingOverlayApplicationProvider: RecordingOverlayApplicationProviding {
    func currentApplication() -> RecordingOverlayApplication {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return .unavailable
        }

        let name = application.localizedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let displayName = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Current app"

        return RecordingOverlayApplication(
            name: displayName,
            icon: application.icon
        )
    }
}

@MainActor
final class RecordingOverlayPresenter: RecordingOverlayPresenting {
    private var window: RecordingOverlayWindow?
    private var sessionApplication: RecordingOverlayApplication?
    private let applicationProvider: any RecordingOverlayApplicationProviding

    init() {
        self.applicationProvider = WorkspaceRecordingOverlayApplicationProvider()
    }

    func present(_ state: RecordingOverlayState) {
        guard state != .hidden else {
            window?.orderOut(nil)
            return
        }

        switch state {
        case .recording, .blocked:
            sessionApplication = applicationProvider.currentApplication()
        case .processing, .cancelled:
            if sessionApplication == nil {
                sessionApplication = applicationProvider.currentApplication()
            }
        case .hidden:
            break
        }

        let application = sessionApplication ?? .unavailable
        let window = window ?? RecordingOverlayWindow(
            state: state,
            application: application
        )
        self.window = window
        window.update(state: state, application: application)
        window.positionAtBottomCenter()
        window.reveal()
    }
}

@MainActor
final class RecordingOverlayWindow: NSWindow {
    private let hostingView: NSHostingView<RecordingOverlayContent>

    fileprivate init(
        state: RecordingOverlayState = .recording(elapsedSeconds: 0),
        application: RecordingOverlayApplication = .unavailable
    ) {
        let content = RecordingOverlayContent(
            state: state,
            application: application
        )
        self.hostingView = NSHostingView(rootView: content)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 344, height: 88),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        contentView = hostingView
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
    }

    fileprivate func update(
        state: RecordingOverlayState,
        application: RecordingOverlayApplication
    ) {
        hostingView.rootView = RecordingOverlayContent(
            state: state,
            application: application
        )
    }

    func reveal() {
        guard !isVisible else {
            orderFrontRegardless()
            return
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            alphaValue = 1
            orderFrontRegardless()
            return
        }

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func positionAtBottomCenter(screen: NSScreen? = NSScreen.main ?? NSScreen.screens.first) {
        guard let screen else {
            return
        }
        let visibleFrame = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.minY + 22
        ))
    }
}

private struct RecordingOverlayContent: View {
    let state: RecordingOverlayState
    let application: RecordingOverlayApplication

    private let cornerRadius: CGFloat = 21

    var body: some View {
        ZStack {
            capsuleBackground

            VStack(spacing: 7) {
                identityRow
                signalRow
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 328, height: 72)
        .overlay {
            RecordingSignalGlow(state: state, cornerRadius: cornerRadius)
        }
        .shadow(color: .black.opacity(0.38), radius: 14, y: 7)
        .padding(8)
        .frame(width: 344, height: 88)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
    }

    private var capsuleBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.075, green: 0.084, blue: 0.096).opacity(0.92),
                            Color(red: 0.035, green: 0.041, blue: 0.049).opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.07), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
    }

    private var identityRow: some View {
        HStack(spacing: 8) {
            applicationIcon

            Text(application.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 10)

            TextifyVoiceMark(state: voiceMarkState, height: 14, animated: true)
            Text("Textify")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.48))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var applicationIcon: some View {
        if let icon = application.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(1)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.65)
                }
        } else {
            Image(systemName: "macwindow")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.65)
                }
        }
    }

    @ViewBuilder
    private var signalRow: some View {
        switch state {
        case let .blocked(reason):
            compactStatus(reason)
        case .cancelled:
            compactStatus("Cancelled — nothing was inserted")
        case .hidden:
            Color.clear.frame(height: 11)
        case .recording, .processing:
            RecordingSignalWaveform(state: state)
                .frame(height: 11)
        }
    }

    private func compactStatus(_ message: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 4, height: 4)
                .shadow(color: indicatorColor.opacity(0.65), radius: 3)
            Text(message)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.54))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 11)
    }

    private var voiceMarkState: TextifyVoiceMarkState {
        switch state {
        case .hidden:
            return .idle
        case .recording:
            return .recording
        case .processing:
            return .processing
        case .cancelled:
            return .idle
        case .blocked:
            return .blocked
        }
    }

    private var indicatorColor: Color {
        switch state {
        case .hidden:
            return .clear
        case .recording:
            return .red
        case .processing:
            return .accentColor
        case .cancelled:
            return .secondary
        case .blocked:
            return .orange
        }
    }
}

private struct RecordingSignalWaveform: View {
    let state: RecordingOverlayState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 34
    private let barSpacing: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates || reduceMotion)) { context in
            GeometryReader { geometry in
                let availableWidth = geometry.size.width - CGFloat(barCount - 1) * barSpacing
                let barWidth = max(2.2, availableWidth / CGFloat(barCount))

                HStack(alignment: .center, spacing: barSpacing) {
                    ForEach(0..<barCount, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(barColor(at: index))
                            .frame(
                                width: barWidth,
                                height: barHeight(
                                    at: index,
                                    date: context.date,
                                    maximumHeight: geometry.size.height
                                )
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var animates: Bool {
        switch state {
        case .recording, .processing:
            return true
        case .hidden, .cancelled, .blocked:
            return false
        }
    }

    private func barHeight(at index: Int, date: Date, maximumHeight: CGFloat) -> CGFloat {
        guard animates, !reduceMotion else {
            let restingWave = 0.18 + abs(sin(Double(index) * 0.62)) * 0.16
            return max(3, maximumHeight * restingWave)
        }

        let normalizedIndex = Double(index) / Double(max(1, barCount - 1))
        let speed = state == .processing ? 5.4 : 3.9
        let time = date.timeIntervalSinceReferenceDate * speed
        let carrier = (sin(time + normalizedIndex * 13.5) + 1) * 0.5
        let detail = (sin(time * 0.63 - normalizedIndex * 27.0) + 1) * 0.5
        let center = (sin(time * 0.28) + 1) * 0.5
        let distance = normalizedIndex - center
        let travelingEnergy = exp(-(distance * distance) / 0.032)
        let energy = 0.16 + carrier * 0.34 + detail * 0.18 + travelingEnergy * 0.32
        return max(3, maximumHeight * min(1, energy))
    }

    private func barColor(at index: Int) -> Color {
        let position = Double(index) / Double(max(1, barCount - 1))
        switch state {
        case .recording:
            return Color.white.opacity(0.36 + position * 0.32)
        case .processing:
            return TextifyVisualIdentity.voiceViolet.opacity(0.42 + position * 0.34)
        case .blocked:
            return TextifyVisualIdentity.warmWarning.opacity(0.48)
        case .cancelled:
            return Color.white.opacity(0.26)
        case .hidden:
            return .clear
        }
    }
}

private struct RecordingSignalGlow: View {
    let state: RecordingOverlayState
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let phase = reduceMotion
                ? 18.0
                : context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 7.5) / 7.5 * 360
            let glow = AngularGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .clear, location: 0.16),
                    .init(color: glowAccent.opacity(0.86), location: 0.27),
                    .init(color: Color(red: 0.30, green: 0.83, blue: 1.00).opacity(0.72), location: 0.36),
                    .init(color: .clear, location: 0.50),
                    .init(color: .clear, location: 0.76),
                    .init(color: TextifyVisualIdentity.voiceViolet.opacity(0.66), location: 0.88),
                    .init(color: .clear, location: 1.00)
                ],
                center: .center,
                startAngle: .degrees(phase),
                endAngle: .degrees(phase + 360)
            )

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.65)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(glow, lineWidth: 1.15)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(glow, lineWidth: 1.8)
                    .blur(radius: 5)
                    .opacity(0.58)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var glowAccent: Color {
        switch state {
        case .recording:
            return TextifyVisualIdentity.recordCoral
        case .processing:
            return TextifyVisualIdentity.voiceViolet
        case .blocked:
            return TextifyVisualIdentity.warmWarning
        case .hidden, .cancelled:
            return TextifyVisualIdentity.slate
        }
    }
}
