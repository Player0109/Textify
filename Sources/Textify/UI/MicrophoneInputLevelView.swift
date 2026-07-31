import SwiftUI
import TextifyAudio

enum MicrophoneInputPresentationCopy {
    static let selectedInputUnavailable =
        "Selected microphone is unavailable. Choose another microphone or System Default."

    static func errorMessage(
        for error: LiveAudioRecorderError
    ) -> String {
        switch error {
        case .selectedInputUnavailable:
            return selectedInputUnavailable
        case .microphonePermissionDenied:
            return "Microphone access is required to show the input level."
        case .alreadyRecording, .notRecording, .inputNodeUnavailable,
             .unsupportedInputFormat,
             .engineStartFailed, .conversionFailed, .emptyRecording,
             .deviceChangedDuringRecording:
            return "The microphone input level is temporarily unavailable."
        }
    }
}

struct MicrophoneInputLevelView: View {
    let level: Float
    let isMonitoring: Bool
    let error: LiveAudioRecorderError?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Input Level", systemImage: "mic.fill")
                    .font(.callout.weight(.medium))

                Spacer()

                Text(isMonitoring ? "Listening" : "Not listening")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(level), total: 1)
                .progressViewStyle(.linear)
                .tint(TextifyVisualIdentity.readyMint)
                .accessibilityLabel("Microphone input level")
                .accessibilityValue(
                    "\(Int((level * 100).rounded())) percent"
                )

            if let error {
                Text(MicrophoneInputPresentationCopy.errorMessage(for: error))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
