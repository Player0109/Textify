import SwiftUI

struct OnboardingRootView: View {
    @Environment(AppServices.self) private var services
    @State private var launchAtLogin = true

    var body: some View {
        @Bindable var services = services

        VStack(alignment: .leading, spacing: 20) {
            Picker("Step", selection: $services.onboardingStep) {
                ForEach(OnboardingStep.allCases) { step in
                    Text(step.title).tag(step)
                }
            }
            .pickerStyle(.segmented)

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(services.onboardingStep.title)
                        .font(.title2)

                    onboardingContent
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Spacer()

            HStack {
                if services.onboardingStep == .completion {
                    Toggle("Launch at Login", isOn: $launchAtLogin)
                }

                Spacer()

                Button("Continue") {
                    advance()
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 360)
    }

    @ViewBuilder
    private var onboardingContent: some View {
        switch services.onboardingStep {
        case .welcome:
            Text("Textify setup is ready.")
        case .model:
            Text("Choose and download a curated English model during onboarding. No model is bundled with the app.")
        case .microphone:
            Text("Allow microphone access so Textify can capture your dictation.")
        case .accessibility:
            Text("Allow Accessibility access so Textify can type into the current app.")
        case .inputMonitoring:
            Text("Allow Input Monitoring so Textify can detect the dictation trigger.")
        case .triggerTest:
            Text("Press and hold your dictation trigger to confirm Textify can detect it.")
        case .completion:
            Text("Textify is ready to run from the menu bar.")
        }
    }

    private func advance() {
        if services.onboardingStep == .completion {
            Task {
                await services.setLaunchAtLoginEnabled(launchAtLogin)
            }
            return
        }

        guard let index = OnboardingStep.allCases.firstIndex(of: services.onboardingStep) else {
            return
        }

        let nextIndex = OnboardingStep.allCases.index(after: index)
        if nextIndex < OnboardingStep.allCases.endIndex {
            services.onboardingStep = OnboardingStep.allCases[nextIndex]
        }
    }
}
