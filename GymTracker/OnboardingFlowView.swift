import SwiftUI

/// Coordinates the first-launch flow: Welcome → Privacy (once) → Quiz →
/// Plan Reveal → Paywall → main app. The paywall's X still lands the user
/// on their full free program — the price is never a gate.
struct OnboardingFlowView: View {
    @EnvironmentObject var store: WorkoutStore

    enum Step {
        case welcome
        case privacy
        case quiz
        case reveal
        case paywall
    }

    @State private var step: Step = .welcome
    @State private var profile = UserProfile()
    @State private var program: UserProgram?

    var body: some View {
        Group {
            switch step {
            case .welcome:
                WelcomeView(
                    onBuild: { step = store.hasSeenPrivacy ? .quiz : .privacy },
                    onSkip: skipToGym
                )
                .transition(.opacity)
            case .privacy:
                PrivacyView(onContinue: {
                    store.markPrivacySeen()
                    step = .quiz
                })
                .transition(.opacity)
            case .quiz:
                SetupQuizView(
                    onComplete: { finishedProfile in
                        profile = finishedProfile
                        program = ProgramGenerator.generate(
                            profile: finishedProfile,
                            customExercises: store.customExercises,
                            preferences: store.exercisePreferences,
                            equipment: finishedProfile.equipmentHave
                        )
                        step = .reveal
                    },
                    onBack: { step = .welcome }
                )
                .transition(.opacity)
            case .reveal:
                if let program {
                    PlanRevealView(
                        program: program,
                        profile: profile,
                        onStart: { updated in
                            self.program = updated
                            step = .paywall
                        },
                        onBack: { step = .quiz }
                    )
                    .transition(.opacity)
                }
            case .paywall:
                PaywallView(
                    programName: program?.name ?? "Your plan",
                    onClose: finish,
                    onPurchased: finish
                )
                .transition(.opacity)
            }
        }
        // Crossfade between flow steps (welcome → privacy → quiz →
        // reveal → paywall) instead of a hard cut.
        .animation(AppAnimation.page, value: step)
    }

    /// "Skip to the gym" — straight to a starter 3-day full-body plan.
    private func skipToGym() {
        let starter = UserProfile.starter
        let starterProgram = ProgramGenerator.generate(
            profile: starter,
            customExercises: store.customExercises,
            preferences: store.exercisePreferences,
            equipment: starter.equipmentHave
        )
        store.completeOnboarding(profile: starter, program: starterProgram)
    }

    /// Paywall closed (X) or purchase succeeded — land on the program.
    private func finish() {
        if let program {
            store.completeOnboarding(profile: profile, program: program)
        }
    }
}
