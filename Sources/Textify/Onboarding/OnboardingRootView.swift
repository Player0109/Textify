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
            Text("Microphone permission status is not checked in this milestone.")
        case .accessibility:
            Text("Accessibility permission status is not checked in this milestone.")
        case .inputMonitoring:
            Text("Input Monitoring permission status is not checked in this milestone.")
        case .triggerTest:
            Text("Trigger testing is disabled until the native hotkey path is wired.")
        case .completion:
            Text("Onboarding completion is not persisted in this milestone.")
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
