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
        case .queued, .checkingSpace, .downloading, .verifying, .installing:
            return .processing
        case .installed:
            return .ready
        case .paused, .waitingForNetwork, .waitingForCatalogCheck,
             .interrupted, .failed, .revoked:
            return .blocked
        case .cancelled:
            return .idle
        }
    }

    private var progressColor: Color {
        voiceMarkState.color
    }
}
