import StoreKit
import SwiftUI

/// The paywall, shown after the plan reveal. StoreKit only — no analytics,
/// no email, no account. Annual pre-selected ("Best value"), billed price
/// most prominent (Apple rule), trial shown as a timeline, visible X and
/// Restore Purchases. Closing it keeps the full free plan.
struct PaywallView: View {
    @EnvironmentObject var subscription: SubscriptionState
    let programName: String
    var onClose: () -> Void
    var onPurchased: () -> Void

    @State private var selectedPlan: ProPlan = .yearly
    @State private var isPurchasing = false
    @State private var showNotConfigured = false
    @State private var showPrivacyPolicy = false
    /// onPurchased fires once — a purchase's success and the isPro
    /// change that follows it must not both finish the flow.
    @State private var didFinish = false

    enum ProPlan: String, CaseIterable, Identifiable {
        case yearly
        case monthly
        case lifetime

        var id: String { rawValue }

        var productID: String {
            switch self {
            case .yearly: return SubscriptionState.yearlyID
            case .monthly: return SubscriptionState.monthlyID
            case .lifetime: return SubscriptionState.lifetimeID
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your plan is ready")
                            .font(.largeTitle)
                            .bold()
                        Text(programName)
                            .font(.title3)
                            .foregroundStyle(Theme.secondaryText)
                        Text("Free gets you the full plan, unlimited logging, and your whole history — forever. Pro adds unlimited programs and custom exercises, more gym profiles, and accent colors.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.top, 8)

                    // Trial timeline (yearly only) — from the loaded
                    // StoreKit product's introductory offer, never a
                    // hardcoded trial length. No trial (products not
                    // loaded yet, or no offer on the product) = no
                    // timeline: never show a trial that doesn't exist.
                    if selectedPlan == .yearly, let trialDays = yearlyTrialDays {
                        // Stacks at large text sizes instead of squeezing
                        // three columns off the edge.
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { trialTimeline(trialDays, arrow: "arrow.right") }
                            VStack(alignment: .leading, spacing: 8) { trialTimeline(trialDays, arrow: "arrow.down") }
                        }
                        .padding()
                        .themeCard()
                    }

                    // Free vs Pro, compact.
                    VStack(alignment: .leading, spacing: 8) {
                        comparisonRow("Log workouts", free: "Unlimited", pro: "Unlimited")
                        comparisonRow("Programs", free: "2 programs", pro: "Unlimited")
                        comparisonRow("Custom exercises", free: "\(WorkoutStore.freeCustomExerciseCap)", pro: "Unlimited")
                        comparisonRow("Rest timer + Duo features", free: "Yes", pro: "Yes")
                    }
                    .padding()
                    .themeCard()

                    // Plan cards.
                    VStack(spacing: 10) {
                        // The saving comes from the loaded prices; until
                        // they load the badge makes no number claim.
                        planCard(.yearly, badge: subscription.yearlySavingsPercent.map { "Best value — save \($0)%" } ?? "Best value",
                                 billed: priceText(SubscriptionState.yearlyID, per: "year"),
                                 sub: yearlyTrialDays.map { "\($0)-day free trial · then billed yearly" } ?? "Billed yearly")
                        planCard(.monthly, badge: nil,
                                 billed: priceText(SubscriptionState.monthlyID, per: "month"),
                                 sub: "Billed monthly")
                        planCard(.lifetime, badge: nil,
                                 billed: priceText(SubscriptionState.lifetimeID, per: nil),
                                 sub: "One-time payment, yours forever")
                    }

                    // Outcome-framed features.
                    VStack(alignment: .leading, spacing: 6) {
                        featureRow("Unlimited programs")
                        featureRow("Unlimited custom exercises")
                        featureRow("Multiple gym profiles")
                        featureRow("Custom accent colors")
                    }

                    if !subscription.hasProducts {
                        #if DEBUG
                        Text("DEBUG: preview prices — StoreKit products didn't load (check the StoreKit configuration or App Store Connect).")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        #else
                        HStack(spacing: 8) {
                            if subscription.isLoadingProducts {
                                ProgressView()
                            }
                            Text(subscription.isLoadingProducts
                                 ? "Loading prices…"
                                 : "Prices couldn't load. Check your connection.")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                            if !subscription.isLoadingProducts {
                                Button("Retry") { Task { await subscription.loadProducts() } }
                                    .font(.caption)
                            }
                        }
                        #endif
                    }

                    Button(action: buySelected) {
                        if isPurchasing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text(buyButtonLabel)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing || subscription.isPro)

                    if subscription.isPro {
                        Text("You're Pro — thanks for supporting the app.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity)
                    }

                    if subscription.isRestoring {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Restoring purchases…")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }

                    if let notice = subscription.purchaseNotice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    if let error = subscription.purchaseError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.vividRed)
                    }

                    VStack(spacing: 8) {
                        Text("Payment is charged to your Apple Account at confirmation of purchase. Subscriptions renew automatically at the price shown unless cancelled at least 24 hours before the end of the current period; your account is charged for renewal within 24 hours before the period ends. Any unused part of a free trial is forfeited when you buy a subscription. Manage or cancel anytime in your Apple Account settings. Lifetime is a one-time purchase that doesn't renew.")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 16) {
                            Link("Terms of Use (EULA)", destination: PaywallView.termsOfUseURL)
                            Button("Privacy Policy") { showPrivacyPolicy = true }
                        }
                        .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Status Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore Purchases") {
                        Task { await subscription.restore() }
                    }
                    .font(.subheadline)
                    .disabled(subscription.isRestoring || isPurchasing)
                }
            }
            .alert("Can't reach the App Store", isPresented: $showNotConfigured) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Pro prices haven't loaded yet. Check your connection and try again. The free plan keeps your full program, unlimited logging, and your whole history.")
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                PrivacyPolicyView(onClose: { showPrivacyPolicy = false })
            }
            .onAppear {
                // A failure from an earlier paywall visit isn't news now.
                subscription.purchaseError = nil
                subscription.purchaseNotice = nil
            }
            // Pro arriving any way — restore, an approved Ask to Buy,
            // a purchase — closes the paywall.
            .onChange(of: subscription.isPro) { _, isPro in
                if isPro { finishPurchased() }
            }
        }
    }

    private func finishPurchased() {
        guard !didFinish else { return }
        didFinish = true
        onPurchased()
    }

    @ViewBuilder
    private func trialTimeline(_ trialDays: Int, arrow: String) -> some View {
        timelineStep("Today", "free")
        Image(systemName: arrow).font(.caption).foregroundStyle(Theme.secondaryText)
            .accessibilityHidden(true)
        if trialDays > 1 {
            timelineStep("Day \(trialDays - 1)", "reminder")
            Image(systemName: arrow).font(.caption).foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        timelineStep("Day \(trialDays)", "\(subscription.displayPrice(for: SubscriptionState.yearlyID))/year")
    }

    /// Apple's standard EULA. Swap for a custom one if you publish your own.
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    // MARK: - Pieces

    private func timelineStep(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).bold()
            Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonRow(_ label: String, free: String, pro: String) -> some View {
        let values = HStack(spacing: 4) {
            Text(free).font(.caption).foregroundStyle(Theme.secondaryText)
            Text("→").font(.caption).foregroundStyle(Theme.secondaryText)
            Text(pro).font(.caption).bold()
        }
        // Large Dynamic Type: the label and values stack instead of
        // running off the edge.
        return ViewThatFits(in: .horizontal) {
            HStack {
                Text(label).font(.subheadline).fixedSize()
                Spacer()
                values.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline)
                values
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.vividGreen)
            Text(text).font(.subheadline)
        }
    }

    private func planCard(_ plan: ProPlan, badge: String?, billed: String, sub: String) -> some View {
        let selected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    // Title and badge side by side, or stacked when the
                    // text is too large to fit both on one line.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            Text(planTitle(plan)).font(.headline).fixedSize()
                            if let badge { badgeView(badge).fixedSize() }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(planTitle(plan)).font(.headline)
                            if let badge { badgeView(badge) }
                        }
                    }
                    Text(billed)
                        .font(.title3)
                        .bold()
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Theme.secondaryText)
            }
            .padding()
            .background(selected ? Color.accentColor.opacity(0.12) : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.accentColor : Theme.border, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func badgeView(_ badge: String) -> some View {
        Text(badge)
            .font(.caption2)
            .bold()
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor)
            .clipShape(Capsule())
    }

    private func planTitle(_ plan: ProPlan) -> String {
        switch plan {
        case .yearly: return "Yearly"
        case .monthly: return "Monthly"
        case .lifetime: return "Lifetime"
        }
    }

    /// Yearly free-trial length in days, from the loaded StoreKit
    /// product's introductory offer — nil when no trial exists.
    private var yearlyTrialDays: Int? {
        subscription.trialDays(for: SubscriptionState.yearlyID)
    }

    /// "$29.99/year", or just the missing-price dash when the price
    /// hasn't loaded ("—/year" would read as a price).
    private func priceText(_ productID: String, per unit: String?) -> String {
        let price = subscription.displayPrice(for: productID)
        guard let unit, price != SubscriptionState.missingPrice else { return price }
        return "\(price)/\(unit)"
    }

    private var buyButtonLabel: String {
        // No loaded price, no price on the button: tapping it explains
        // that the App Store couldn't be reached.
        let price = subscription.displayPrice(for: selectedPlan.productID)
        let hasPrice = price != SubscriptionState.missingPrice
        switch selectedPlan {
        case .yearly:
            if let trialDays = yearlyTrialDays {
                return "Start \(trialDays)-day free trial"
            }
            return hasPrice ? "Subscribe — \(price)/year" : "Subscribe yearly"
        case .monthly: return hasPrice ? "Subscribe — \(price)/month" : "Subscribe monthly"
        case .lifetime: return hasPrice ? "Buy lifetime — \(price)" : "Buy lifetime"
        }
    }

    private func buySelected() {
        guard let product = product(for: selectedPlan) else {
            showNotConfigured = true
            return
        }
        isPurchasing = true
        Task {
            let ok = await subscription.purchase(product)
            isPurchasing = false
            if ok {
                finishPurchased()
            }
        }
    }

    private func product(for plan: ProPlan) -> StoreKit.Product? {
        switch plan {
        case .yearly: return subscription.yearlyProduct
        case .monthly: return subscription.monthlyProduct
        case .lifetime: return subscription.lifetimeProduct
        }
    }
}


/// The in-app privacy policy (guideline 5.1.1 wants it reachable from the
/// app, not only from the App Store listing). Keep it in sync with what the
/// app actually does and with the App Store privacy label. App Store
/// Connect also needs this hosted at a public URL before submission.
struct PrivacyPolicyView: View {
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Last updated November 14, 2026")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    section("The short version",
                            "Status keeps your workouts on your iPhone. The developer doesn't collect, store, sell, or see your data. There are no accounts, ads, analytics, or tracking.")
                    section("What's stored, and where",
                            "Your programs, logged sets, notes, bodyweight, profile answers (like goals, experience, and injuries you mention), and settings are stored on this device, shared only with the app's own widget and Live Activity. Deleting the app deletes them. Device backups you make through Apple may include them.")
                    section("Optional features you turn on",
                            "Apple Calendar: adds your planned workout days to your calendar and keeps them up to date. Status asks for full calendar access because it has to find its own events again to update or remove them; it only changes the events it added, and doesn't keep or send your other events. If that calendar syncs with iCloud, the events show on your other devices too. Flashlight signal: uses the torch to flash when a rest timer ends. Local network access (Muse): when you enable it, a server runs only while the app is open, so your own devices on your Wi-Fi can read and log workouts with your approval; it's never reachable from the internet. Export: creates a file only when you tap Export, and you choose where it goes.")
                    section("Purchases",
                            "Subscriptions and purchases are processed by Apple. Status receives only whether you have Pro, never your payment details.")
                    section("Children",
                            "Status isn't directed at children under 13 and doesn't knowingly collect anyone's personal information.")
                    section("Changes and contact",
                            "If this policy changes, the new version will appear here with a new date. Questions: contact the developer through the App Store listing's support link.")
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onClose() }
                }
            }
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(body).font(.subheadline).foregroundStyle(Theme.secondaryText)
        }
    }
}
