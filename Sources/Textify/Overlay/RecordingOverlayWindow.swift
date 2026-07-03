import AppKit
import SwiftUI

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
