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
                        Text("Free gets you the full plan, unlimited logging, and your whole history — forever. Pro adds more programs and deeper tracking.")
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
                        HStack(spacing: 8) {
                            timelineStep("Today", "free")
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(Theme.secondaryText)
                            if trialDays > 1 {
                                timelineStep("Day \(trialDays - 1)", "reminder")
                                Image(systemName: "arrow.right").font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            timelineStep("Day \(trialDays)", "\(subscription.displayPrice(for: SubscriptionState.yearlyID))/year")
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
                        planCard(.yearly, badge: "Best value — save 50%",
                                 billed: subscription.displayPrice(for: SubscriptionState.yearlyID) + "/year",
                                 sub: yearlyTrialDays.map { "\($0)-day free trial · then billed yearly" } ?? "Billed yearly")
                        planCard(.monthly, badge: nil,
                                 billed: subscription.displayPrice(for: SubscriptionState.monthlyID) + "/month",
                                 sub: "Billed monthly")
                        planCard(.lifetime, badge: nil,
                                 billed: subscription.displayPrice(for: SubscriptionState.lifetimeID),
                                 sub: "One-time payment, yours forever")
                    }

                    // Outcome-framed features.
                    VStack(alignment: .leading, spacing: 6) {
                        featureRow("Unlimited programs")
                        featureRow("See your strength curve, all time")
                        featureRow("Your own exercises")
                        featureRow("Every future feature")
                    }

                    if !subscription.hasProducts {
                        Text("Preview prices — the Pro products still need to be created in App Store Connect before anyone can buy. Closing this keeps the full free plan.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
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

                    if let error = subscription.purchaseError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.vividRed)
                    }

                    Text("Cancel anytime in Settings. No account, no email — Apple handles payment.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
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
                }
            }
            .alert("Pro isn't available yet", isPresented: $showNotConfigured) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The Pro products still need to be created in App Store Connect. You can close this and use the free plan — it includes your full program, unlimited logging, and your whole history.")
            }
        }
    }

    // MARK: - Pieces

    private func timelineStep(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).bold()
            Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonRow(_ label: String, free: String, pro: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(free).font(.caption).foregroundStyle(Theme.secondaryText)
            Text("→").font(.caption).foregroundStyle(Theme.secondaryText)
            Text(pro).font(.caption).bold()
        }
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
                    HStack(spacing: 8) {
                        Text(planTitle(plan))
                            .font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
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

    private var buyButtonLabel: String {
        switch selectedPlan {
        case .yearly:
            if let trialDays = yearlyTrialDays {
                return "Start \(trialDays)-day free trial"
            }
            return "Subscribe — \(subscription.displayPrice(for: SubscriptionState.yearlyID))/year"
        case .monthly: return "Subscribe — \(subscription.displayPrice(for: SubscriptionState.monthlyID))/month"
        case .lifetime: return "Buy lifetime — \(subscription.displayPrice(for: SubscriptionState.lifetimeID))"
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
                onPurchased()
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
