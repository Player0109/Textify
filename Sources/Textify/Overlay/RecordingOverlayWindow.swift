import AppKit
import SwiftUI
import TextifyRuntime
import TextifySettings

enum DictationOverlayPresentation {
    static func state(for status: DictationRuntimeStatus) -> RecordingOverlayState {
        if case .recording = status {
            return .recording(remainingSeconds: nil)
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
            return .recording(remainingSeconds: nil)
        }
    }
}

enum DictationSessionPresentationCopy {
    static let sessionLimitReached =
        "5-minute limit reached — processing captured speech."

    static func remainingRecordingSeconds(
        deadlineUptimeMilliseconds: Int,
        nowUptimeMilliseconds: Int
    ) -> Int {
        let remainingMilliseconds = max(
            0,
            deadlineUptimeMilliseconds - nowUptimeMilliseconds
        )
        let wholeSeconds = remainingMilliseconds / 1_000
        let partialSecond = remainingMilliseconds % 1_000
        return wholeSeconds + (partialSecond > 0 ? 1 : 0)
    }

    static func recordingWarning(remainingSeconds: Int) -> String? {
        guard remainingSeconds > 0,
              remainingSeconds <= DictationSessionLimits.warningDurationSeconds
        else {
            return nil
        }
        return "Recording stops in \(remainingSeconds)s"
    }

    static func processingProgress(
        completedWindows: Int,
        totalWindows: Int
    ) -> String? {
        guard totalWindows > 1, completedWindows > 0 else {
            return nil
        }
        return "Processing \(min(completedWindows, totalWindows)) of \(totalWindows)"
    }

    static func status(for state: RecordingOverlayState) -> String? {
        switch state {
        case let .recording(remainingSeconds):
            return remainingSeconds.flatMap(recordingWarning)
        case .processing:
            return nil
        case let .processingProgress(completedWindows, totalWindows):
            return processingProgress(
                completedWindows: completedWindows,
                totalWindows: totalWindows
            )
        case .sessionLimitReached:
            return sessionLimitReached
        case .hidden, .cancelled, .blocked:
            return nil
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
        case .selectedMicrophoneUnavailable:
            return MicrophoneInputPresentationCopy.selectedInputUnavailable
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
    func beginSession()
    func endSession()

    func present(
        _ state: RecordingOverlayState,
        preferences: RecordingOverlayPreferences
    )
}

enum RecordingOverlayGeometry {
    static let baseSize = CGSize(width: 344, height: 88)
    static let bottomInset: CGFloat = 22

    static func size(
        preferences: RecordingOverlayPreferences
    ) -> CGSize {
        let scale = CGFloat(preferences.normalized().scale)
        return CGSize(
            width: baseSize.width * scale,
            height: baseSize.height * scale
        )
    }

    static func frame(
        visibleFrame: CGRect,
        preferences: RecordingOverlayPreferences
    ) -> CGRect {
        let preferences = preferences.normalized()
        let size = size(preferences: preferences)
        let proposedOrigin = CGPoint(
            x: visibleFrame.midX - size.width / 2
                + CGFloat(preferences.xOffset),
            y: visibleFrame.minY + bottomInset
                + CGFloat(preferences.yOffset)
        )
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        let origin = CGPoint(
            x: min(max(proposedOrigin.x, visibleFrame.minX), maximumX),
            y: min(max(proposedOrigin.y, visibleFrame.minY), maximumY)
        )
        return CGRect(origin: origin, size: size)
    }
}

private struct RecordingOverlayApplication {
    let name: String
    let icon: NSImage?

    static let unavailable = RecordingOverlayApplication(
        name: "Current app",
        icon: nil
    )
}

enum RecordingOverlayApplicationCapturePolicy {
    static func shouldCapture(
        currentSessionID: UUID?,
        nextSessionID: UUID,
        hasSessionApplication: Bool
    ) -> Bool {
        currentSessionID != nextSessionID || !hasSessionApplication
    }
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
    private var sessionID: UUID?
    private var applicationSessionID: UUID?
    private let applicationProvider: any RecordingOverlayApplicationProviding

    init() {
        self.applicationProvider = WorkspaceRecordingOverlayApplicationProvider()
    }

    func beginSession() {
        sessionID = UUID()
        applicationSessionID = nil
        sessionApplication = nil
    }

    func endSession() {
        window?.orderOut(nil)
        sessionID = nil
        applicationSessionID = nil
        sessionApplication = nil
    }

    func present(
        _ state: RecordingOverlayState,
        preferences: RecordingOverlayPreferences
    ) {
        guard state != .hidden else {
            window?.orderOut(nil)
            return
        }

        if sessionID == nil {
            beginSession()
        }
        guard let activeSessionID = sessionID else {
            return
        }
        let shouldCaptureApplication =
            RecordingOverlayApplicationCapturePolicy.shouldCapture(
                currentSessionID: applicationSessionID,
                nextSessionID: activeSessionID,
                hasSessionApplication: sessionApplication != nil
            )
        if shouldCaptureApplication {
            sessionApplication = applicationProvider.currentApplication()
            applicationSessionID = activeSessionID
        }

        let application = sessionApplication ?? .unavailable
        let window = window ?? RecordingOverlayWindow(
            state: state,
            application: application,
            preferences: preferences
        )
        self.window = window
        window.update(
            state: state,
            application: application,
            preferences: preferences
        )
        window.position(preferences: preferences)
        window.reveal()
    }
}

@MainActor
final class RecordingOverlayWindow: NSWindow {
    private let hostingView: NSHostingView<RecordingOverlayContent>

    fileprivate init(
        state: RecordingOverlayState = .recording(remainingSeconds: nil),
        application: RecordingOverlayApplication = .unavailable,
        preferences: RecordingOverlayPreferences = .defaults
    ) {
        let content = RecordingOverlayContent(
            state: state,
            application: application,
            preferences: preferences
        )
        self.hostingView = NSHostingView(rootView: content)
        let size = RecordingOverlayGeometry.size(
            preferences: preferences
        )

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
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
        application: RecordingOverlayApplication,
        preferences: RecordingOverlayPreferences
    ) {
        let size = RecordingOverlayGeometry.size(
            preferences: preferences
        )
        setContentSize(size)
        hostingView.rootView = RecordingOverlayContent(
            state: state,
            application: application,
            preferences: preferences
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

    func position(
        preferences: RecordingOverlayPreferences,
        screen: NSScreen? = NSScreen.main ?? NSScreen.screens.first
    ) {
        guard let screen else {
            return
        }
        setFrame(
            RecordingOverlayGeometry.frame(
                visibleFrame: screen.visibleFrame,
                preferences: preferences
            ),
            display: false
        )
    }
}

private struct RecordingOverlayContent: View {
    let state: RecordingOverlayState
    let application: RecordingOverlayApplication
    let preferences: RecordingOverlayPreferences

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
        .scaleEffect(CGFloat(preferences.scale))
        .frame(
            width: RecordingOverlayGeometry.baseSize.width
                * CGFloat(preferences.scale),
            height: RecordingOverlayGeometry.baseSize.height
                * CGFloat(preferences.scale)
        )
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
        case let .recording(remainingSeconds):
            if let remainingSeconds,
               let warning = DictationSessionPresentationCopy.recordingWarning(
                   remainingSeconds: remainingSeconds
               ) {
                compactStatus(warning)
            } else {
                RecordingSignalWaveform(state: state)
                    .frame(height: 11)
            }
        case .processing:
            RecordingSignalWaveform(state: state)
                .frame(height: 11)
        case let .processingProgress(completedWindows, totalWindows):
            compactStatus(
                DictationSessionPresentationCopy.processingProgress(
                    completedWindows: completedWindows,
                    totalWindows: totalWindows
                ) ?? "Processing"
            )
        case .sessionLimitReached:
            compactStatus(
                DictationSessionPresentationCopy.sessionLimitReached
            )
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
        case .processing, .processingProgress, .sessionLimitReached:
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
        case .processing, .processingProgress:
            return .accentColor
        case .sessionLimitReached:
            return .orange
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
        case .recording, .processing, .processingProgress:
            return true
        case .hidden, .sessionLimitReached, .cancelled, .blocked:
            return false
        }
    }

    private func barHeight(at index: Int, date: Date, maximumHeight: CGFloat) -> CGFloat {
        guard animates, !reduceMotion else {
            let restingWave = 0.18 + abs(sin(Double(index) * 0.62)) * 0.16
            return max(3, maximumHeight * restingWave)
        }

        let normalizedIndex = Double(index) / Double(max(1, barCount - 1))
        let speed: Double
        switch state {
        case .processing, .processingProgress:
            speed = 5.4
        case .hidden, .recording, .sessionLimitReached, .cancelled,
             .blocked:
            speed = 3.9
        }
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
        case .processing, .processingProgress:
            return TextifyVisualIdentity.voiceViolet.opacity(0.42 + position * 0.34)
        case .sessionLimitReached:
            return TextifyVisualIdentity.warmWarning.opacity(0.48)
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
        case .processing, .processingProgress:
            return TextifyVisualIdentity.voiceViolet
        case .sessionLimitReached, .blocked:
            return TextifyVisualIdentity.warmWarning
        case .hidden, .cancelled:
            return TextifyVisualIdentity.slate
        }
    }
}
