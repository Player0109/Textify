import SwiftUI
import TextifyModels

struct ModelInstallProgressView: View {
    let state: DownloadState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ModelInstallProgressPresentation.title(for: state))
                Spacer()
                if let percentText = ModelInstallProgressPresentation.percentText(for: state) {
                    Text(percentText)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout.weight(.medium))

            if state.totalBytes > 0 {
                ProgressView(value: ModelInstallProgressPresentation.progressValue(for: state), total: 1)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            Text(ModelInstallProgressPresentation.detailText(for: state))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 360, alignment: .leading)
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
