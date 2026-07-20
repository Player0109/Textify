import SwiftUI
import TextifyModels

struct ModelInstallProgressView: View {
    let state: DownloadState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(progressColor.opacity(0.13))
                TextifyVoiceMark(
                    state: voiceMarkState,
                    height: 20,
                    animated: state.phase == .downloading || state.phase == .verifying
                )
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(ModelInstallProgressPresentation.title(for: state))
                    Spacer()
                    if let percentText = ModelInstallProgressPresentation.percentText(for: state) {
                        Text(percentText)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .foregroundStyle(progressColor)
                    }
                }
                .font(.callout.weight(.medium))

                if state.totalBytes > 0 {
                    ProgressView(value: ModelInstallProgressPresentation.progressValue(for: state), total: 1)
                        .tint(progressColor)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(progressColor)
                }

                Text(ModelInstallProgressPresentation.detailText(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var voiceMarkState: TextifyVoiceMarkState {
        switch state.phase {
        case .checkingSpace, .downloading, .verifying, .installing:
            return .processing
        case .installed:
            return .ready
        case .interrupted, .failed:
            return .blocked
        case .cancelled:
            return .idle
        }
    }

    private var progressColor: Color {
        voiceMarkState.color
    }
}

enum ModelInstallProgressPresentation {
    static func title(for state: DownloadState) -> String {
        switch state.phase {
        case .checkingSpace:
            return "Preparing download"
        case .downloading:
            return "Downloading model"
        case .interrupted:
            return "Download interrupted"
        case .verifying:
            return "Verifying model"
        case .installing:
            return "Installing model"
        case .installed:
            return "Model installed"
        case .failed:
            return "Install failed"
        case .cancelled:
            return "Install cancelled"
        }
    }

    static func percentText(for state: DownloadState) -> String? {
        guard state.totalBytes > 0 else {
            return nil
        }

        return "\(Int((state.progressFraction * 100).rounded()))%"
    }

    static func progressValue(for state: DownloadState) -> Double {
        state.progressFraction
    }

    static func detailText(for state: DownloadState) -> String {
        if state.phase == .failed, let message = state.message {
            return message
        }

        if state.totalBytes > 0 {
            return "\(bytes(state.bytesDownloaded)) of \(bytes(state.totalBytes))"
        }

        if state.bytesDownloaded > 0 {
            return bytes(state.bytesDownloaded)
        }

        return state.message ?? "Starting..."
    }

    private static func bytes(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
