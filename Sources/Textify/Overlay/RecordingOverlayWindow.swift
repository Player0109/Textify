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

@MainActor
final class RecordingOverlayPresenter: RecordingOverlayPresenting {
    private var window: RecordingOverlayWindow?

    func present(_ state: RecordingOverlayState) {
        guard state != .hidden else {
            window?.orderOut(nil)
            return
        }

        let window = window ?? RecordingOverlayWindow(state: state)
        self.window = window
        window.update(state: state)
        window.positionAtBottomCenter()
        window.orderFrontRegardless()
    }
}

@MainActor
final class RecordingOverlayWindow: NSWindow {
    private let hostingView: NSHostingView<RecordingOverlayContent>

    init(state: RecordingOverlayState = .recording(elapsedSeconds: 0)) {
        let content = RecordingOverlayContent(state: state)
        self.hostingView = NSHostingView(rootView: content)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 72),
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
    }

    func update(state: RecordingOverlayState) {
        hostingView.rootView = RecordingOverlayContent(state: state)
    }

    func positionAtBottomCenter(screen: NSScreen? = NSScreen.main ?? NSScreen.screens.first) {
        guard let screen else {
            return
        }
        let visibleFrame = screen.visibleFrame
        setFrameOrigin(NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.minY + 48
        ))
    }
}

private struct RecordingOverlayContent: View {
    let state: RecordingOverlayState

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 12, height: 12)

            Text(title)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 260, height: 72)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch state {
        case .hidden:
            return ""
        case let .recording(elapsedSeconds):
            return elapsedSeconds > 2 ? "Recording \(elapsedSeconds)s" : "Recording"
        case .processing:
            return "Processing"
        case .cancelled:
            return "Cancelled"
        case let .blocked(reason):
            return reason
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
