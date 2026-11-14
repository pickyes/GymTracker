import Foundation
import StoreKit
@preconcurrency import UserNotifications

/// Pro subscription state. StoreKit only — no analytics SDK, no account, no
/// email, nothing leaves the device. Apple handles payment; the app only
/// reads entitlements. Trial reminders are local notifications, on-device.
@MainActor
final class SubscriptionState: ObservableObject {
    /// Static IDs and proposed prices are plain constants — marked
    /// nonisolated so nonisolated views (e.g. PaywallView) can read them
    /// without a MainActor hop.
    nonisolated static let monthlyID = "com.daronbarkley.GymTracker.pro.monthly"
    nonisolated static let yearlyID = "com.daronbarkley.GymTracker.pro.yearly"
    nonisolated static let lifetimeID = "com.daronbarkley.GymTracker.pro.lifetime"

    /// Proposed prices (for DaRon to decide — NOT a decision). Shown only
    /// in debug builds when the App Store Connect products aren't
    /// configured yet (e.g. simulator), so the paywall layout can be judged.
    nonisolated static let proposedMonthlyPrice = "$4.99"
    nonisolated static let proposedYearlyPrice = "$29.99"
    nonisolated static let proposedLifetimePrice = "$59.99"
    /// Shown in place of a price that hasn't loaded.
    nonisolated static let missingPrice = "—"

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoadingProducts = false
    @Published var purchaseError: String?
    /// Non-error purchase/restore feedback ("pending approval",
    /// "nothing to restore").
    @Published var purchaseNotice: String?
    @Published var isRestoring = false
    /// Whether this Apple Account can still get each subscription's
    /// introductory offer. A free trial is only advertised when true —
    /// someone who already used it is charged right away.
    @Published var introOfferEligibility: [String: Bool] = [:]

    /// When the current Pro entitlement ends, if it ends (nil for
    /// lifetime, or when Pro isn't active). Set by the invite-redemption
    /// refresh so the friend sees how long their 7 free days run.
    @Published var inviteProExpiresAt: Date?

    var isPro: Bool { !purchasedProductIDs.isEmpty }
    var hasProducts: Bool { !products.isEmpty }

    var monthlyProduct: Product? { product(for: Self.monthlyID) }
    var yearlyProduct: Product? { product(for: Self.yearlyID) }
    var lifetimeProduct: Product? { product(for: Self.lifetimeID) }

    /// Loaded product by id, or nil. The local capture keeps the
    /// lookup closure from implicitly capturing self (Swift 6).
    private func product(for productID: String) -> Product? {
        let loaded = products
        return loaded.first(where: { $0.id == productID })
    }

    /// Billed price, most prominent (Apple rule): the StoreKit price when
    /// products loaded. Without one a release build shows no price at
    /// all: a hard-coded US price is wrong in every other storefront and
    /// may not match what Apple charges. Debug builds show the proposed
    /// price instead.
    func displayPrice(for productID: String) -> String {
        if let product = product(for: productID) {
            return product.displayPrice
        }
        #if DEBUG
        switch productID {
        case Self.monthlyID: return Self.proposedMonthlyPrice
        case Self.yearlyID: return Self.proposedYearlyPrice
        case Self.lifetimeID: return Self.proposedLifetimePrice
        default: return Self.missingPrice
        }
        #else
        return Self.missingPrice
        #endif
    }

    /// Whole percent saved by paying yearly instead of 12 months, from
    /// the loaded StoreKit prices, rounded down so it never overstates
    /// the saving. Nil until both products load, or when yearly saves
    /// nothing.
    var yearlySavingsPercent: Int? {
        guard let monthly = monthlyProduct?.price, let yearly = yearlyProduct?.price,
              monthly > 0 else { return nil }
        let fullYear = NSDecimalNumber(decimal: monthly * 12).doubleValue
        let saving = (1 - NSDecimalNumber(decimal: yearly).doubleValue / fullYear) * 100
        guard saving.isFinite, saving >= 1 else { return nil }
        return Int(saving.rounded(.down))
    }

    /// Free-trial length in days for a product, read from its loaded
    /// StoreKit introductory offer. Nil when products aren't loaded or
    /// the product has no free trial — a trial is never claimed that
    /// doesn't exist (P0-5: the paywall used to hardcode "7-day").
    func trialDays(for productID: String) -> Int? {
        guard let product = product(for: productID),
              introOfferEligibility[productID] == true,
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let daysPerUnit: Int
        switch offer.period.unit {
        case .day: daysPerUnit = 1
        case .week: daysPerUnit = 7
        case .month: daysPerUnit = 30
        case .year: daysPerUnit = 365
        @unknown default: return nil
        }
        let days = offer.period.value * daysPerUnit * max(offer.periodCount, 1)
        return days > 0 ? days : nil
    }

    private var transactionListener: Task<Void, Error>?

    init() {
        transactionListener = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                }
            }
        }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.updatePurchasedProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: [Self.monthlyID, Self.yearlyID, Self.lifetimeID])
            products = fetched.sorted { $0.id < $1.id }
            await refreshIntroOfferEligibility()
        } catch {
            // Products aren't configured yet (simulator / App Store Connect).
            // The paywall shows no prices (debug builds: the proposed ones).
            products = []
        }
    }

    /// Reads each subscription's intro-offer eligibility from StoreKit.
    func refreshIntroOfferEligibility() async {
        var eligibility: [String: Bool] = [:]
        for product in products {
            if let subscription = product.subscription {
                eligibility[product.id] = await subscription.isEligibleForIntroOffer
            }
        }
        introOfferEligibility = eligibility
    }

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                purchased.insert(transaction.productID)
            }
        }
        purchasedProductIDs = purchased
    }

    /// Refresh entitlements after an invite redemption sheet closes and
    /// report whether Pro is now active. Apple's redemption sheet has
    /// no completion callback, so this refresh IS the confirmation: the
    /// caller marks the invite code redeemed only when this returns
    /// true. Also records the earliest entitlement end date so the
    /// friend sees how long their 7 free days run (nil for lifetime).
    func refreshProStatusAfterInviteRedemption() async -> Bool {
        await updatePurchasedProducts()
        var earliest: Date?
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               let expiry = transaction.expirationDate {
                if earliest == nil || expiry < earliest! {
                    earliest = expiry
                }
            }
        }
        inviteProExpiresAt = earliest
        return isPro
    }

    /// Returns true if the purchase succeeded.
    func purchase(_ product: Product) async -> Bool {
        purchaseError = nil
        purchaseNotice = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    purchasedProductIDs.insert(transaction.productID)
                    await transaction.finish()
                    // Only a free-trial (introductory offer) purchase has
                    // a "trial ends" moment — a paid subscription would
                    // get a false "your trial ends tomorrow".
                    if Self.isIntroductoryOffer(transaction), let expiry = transaction.expirationDate {
                        scheduleTrialReminder(expiry: expiry, product: product)
                    }
                    await updatePurchasedProducts()
                    await refreshIntroOfferEligibility()
                    return true
                }
                purchaseError = "The App Store couldn't verify this purchase. Try Restore Purchases."
                return false
            case .pending:
                // Ask to Buy / Strong Customer Authentication: the
                // purchase completes later and arrives through
                // Transaction.updates.
                purchaseNotice = "Your purchase is waiting for approval. Pro turns on as soon as it's approved."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        guard !isRestoring else { return }
        purchaseError = nil
        purchaseNotice = nil
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
            if !isPro {
                purchaseNotice = "Nothing to restore — no Pro purchase was found for this Apple Account."
            }
        } catch StoreKitError.userCancelled {
            // Cancelled the sign-in sheet: no message.
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    /// True when the transaction was bought with the subscription's
    /// introductory offer (the free trial).
    private static func isIntroductoryOffer(_ transaction: Transaction) -> Bool {
        if #available(iOS 17.2, *) {
            return transaction.offer?.type == .introductory
        } else {
            return transaction.offerType == .introductory
        }
    }

    /// Ask for local-notification permission (rest timer + trial reminder).
    /// Called in context from the setup quiz.
    func requestNotificationPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Local notification 1 day before a trial/subscription ends. On-device
    /// only — no email, no server.
    func scheduleTrialReminder(expiry: Date, product: Product) {
        let center = UNUserNotificationCenter.current()
        // The purchased product's own price and billing period (it used
        // to always say the yearly price, even for monthly).
        let price = product.displayPrice
        let period = Self.periodWord(product.subscription?.subscriptionPeriod)
        let priceText = period.map { "\(price)/\($0)" } ?? price
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Your Status trial ends tomorrow"
            content.body = "Pro renews at \(priceText) unless you cancel. Cancel anytime in Settings."
            content.sound = .default
            let reminderDate = expiry.addingTimeInterval(-24 * 60 * 60)
            guard reminderDate > Date() else { return }
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminderDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: "gymtracker.trial-reminder", content: content, trigger: trigger)
            center.add(request)
        }
    }

    /// "year" / "month" / "week" / "day" (or "3 months") for a period.
    nonisolated static func periodWord(_ period: Product.SubscriptionPeriod?) -> String? {
        guard let period else { return nil }
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: return nil
        }
        return period.value == 1 ? unit : "\(period.value) \(unit)s"
    }
}
