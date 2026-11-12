import SwiftUI

// MARK: - Welcome (screen 1 of the intro)

/// First screen a new user sees. Three value props, one big button, and a
/// skip path — the user is logging a set within ~90 seconds either way.
struct WelcomeView: View {
    var onBuild: () -> Void
    var onSkip: () -> Void

    /// The store, for the preset claim card only. The card is gated on
    /// `isDaronPresetUnlocked` — other users never see it. (Always
    /// present in the app: ContentView injects the store into the
    /// environment for the whole hierarchy, including this intro flow.)
    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Compact-width screens (Duo folded outer display, iPhones) get a
    /// tighter intro so the whole screen fits without scrolling.
    /// Regular-width screens keep the roomy layout.
    private var compactWidth: Bool { horizontalSizeClass == .compact }

    var body: some View {
        // Vertically centered on compact width: without the preset card
        // the content left ~30% dead space at the bottom on the folded
        // display. Centering the block makes the screen feel composed
        // instead of top-heavy; it still scrolls if the content ever
        // grows taller than the screen. (The preset card is back, but
        // only on DaRon's unlocked device — other users never see it.)
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: compactWidth ? 12 : 20) {
                VStack(alignment: .leading, spacing: compactWidth ? 6 : 8) {
                    Image(systemName: "dumbbell.fill")
                        .scaledFont(size: compactWidth ? 40 : 52)
                        .foregroundStyle(Color.accentColor)
                    Text("Status")
                        .font(compactWidth ? .title : .largeTitle)
                        .bold()
                    Text("Log. Lift. Get stronger.")
                        .font(compactWidth ? .headline : .title3)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, compactWidth ? 8 : 24)

                VStack(alignment: .leading, spacing: compactWidth ? 10 : 14) {
                    valueProp(icon: "list.clipboard.fill",
                              title: "Your program, built in",
                              detail: "Answer a few questions and your week is planned for you.")
                    valueProp(icon: "person.slash.fill",
                              title: "No account, no ads",
                              detail: "Open it and train. No sign-up wall, ever.")
                    valueProp(icon: "lock.shield.fill",
                              title: "Your data stays on your device",
                              detail: "No tracking, no analytics, nothing leaves this phone.")
                }

                // DaRon's preset, claimed explicitly on his device only:
                // shown only once this device is unlocked for it (deep
                // link or a previous claim) and only while another
                // program is active. Other users never see this card.
                // One tap restores his 5-day split and lands on Today.
                if store.isDaronPresetUnlocked, !store.isPresetActive {
                    Button(action: { store.restoreDaronPreset() }) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "dumbbell.fill")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Load DaRon's 5-Day Split")
                                    .font(.headline)
                                Text("Mon legs · Tue push · Wed legs · Thu pull · Fri upper mix")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(12)
                        .themeCard()
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onBuild) {
                    Text("Build my program")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(compactWidth ? 12 : 16)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button(action: onSkip) {
                    Text("Just want to log? Skip to the gym →")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, compactWidth ? 8 : 16)
            .frame(minHeight: proxy.size.height, alignment: .center)
        }
        }
    }

    private func valueProp(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

// MARK: - Privacy, once (screen 2 of the intro)

/// Shown on first launch only. The flag lives in UserDefaults, so a
/// returning user never sees this again — even after retaking setup.
struct PrivacyView: View {
    var onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .scaledFont(size: 52)
                        .foregroundStyle(Color.accentColor)
                    Text("Your Privacy")
                        .font(.largeTitle)
                        .bold()
                    Text("Your workouts never leave this phone.")
                        .font(.title3)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 12) {
                    privacyRow(icon: "checkmark", text: "Your logged workouts, weights, and bodyweight stay on this device.")
                    privacyRow(icon: "checkmark", text: "No account, no sign-up, no email address.")
                    privacyRow(icon: "checkmark", text: "No analytics, no tracking, no ads, no third-party SDKs.")
                    privacyRow(icon: "checkmark", text: "Subscriptions go through Apple (StoreKit) only — the app itself collects nothing.")
                    privacyRow(icon: "xmark", text: "Nothing is uploaded or shared unless you turn on a feature that does it, like Apple Calendar or Export.")
                }

                Text("Read the full privacy policy anytime in Profile. If the app ever changes how it handles data, the policy will be updated first.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)

                Button(action: onContinue) {
                    Text("Got it")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
    }

    private func privacyRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon == "checkmark" ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(icon == "checkmark" ? Theme.vividGreen : Theme.vividRed)
            Text(text)
                .font(.subheadline)
        }
    }
}
