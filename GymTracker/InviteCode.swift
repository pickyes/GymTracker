import SwiftUI
import StoreKit
import UIKit

/// Invite / referral codes — "share it, you both get 7 days of Pro free"
/// (DaRon, 2026-11-10).
///
/// What this file owns, in one place:
/// - one invite code per device (generated once, persisted on-device),
/// - the native share sheet for sending it,
/// - the friend's redemption flow up to Apple's redemption sheet,
/// - the on-device anti-abuse checks.
///
/// What it does NOT own:
/// - the Apple offer codes themselves — those are created in App Store
///   Connect (DaRon's step; products aren't configured there yet), and
///   Apple's redemption sheet redeems an Apple-issued offer code, not
///   this invite code. The invite code is what gates the sheet: a friend
///   enters a valid invite code, the app opens Apple's sheet, and the
///   sheet is where the 7 free days are applied. Until the offer codes
///   exist in App Store Connect, the sheet cannot grant anything — the
///   flow is built up to it, not through it.
/// - the SHARER's 7 days. Knowing "your friend redeemed" needs a record
///   outside this phone, and this app collects no data, has no accounts,
///   and sends nothing anywhere. There is no on-device-only mechanism
///   that can confirm a redemption on another device — a code generated
///   on phone A cannot be observed by phone A when phone B redeems it.
///   So the sharer's reward is built as a QUEUED state
///   (`confirmedFriendRedemptions`, always 0 until a ledger exists) and
///   the decision is DaRon's: a minimal referral ledger (code +
///   redemption event only, no personal data) on a server he approves,
///   or the sharer reward waits until that ledger exists. Nothing here
///   phones home, silently or otherwise — the invite only moves when
///   the user taps Share.
///
/// Keys (SharedDefaults.store, the `gymtracker.*` family):
/// - gymtracker.invite.code.v1 — this device's code (8 chars, no hyphens)
/// - gymtracker.invite.redeemedCodes.v1 — codes this device has redeemed
/// - gymtracker.invite.attemptedCodes.v1 — codes the redemption sheet was
///   opened for but Pro hasn't confirmed yet (a cancelled sheet must
///   not block a retry, so attempted != redeemed)
/// - gymtracker.invite.confirmedFriends.v1 — friends confirmed redeemed;
///   0 until the ledger lands, nothing on-device can ever raise it
enum InviteCode {
    static let codeKey = "gymtracker.invite.code.v1"
    static let redeemedCodesKey = "gymtracker.invite.redeemedCodes.v1"
    static let attemptedCodesKey = "gymtracker.invite.attemptedCodes.v1"
    static let confirmedFriendsKey = "gymtracker.invite.confirmedFriends.v1"
    /// A code that arrived via a tapped `gymtracker://invite?code=…`
    /// link, waiting to be prefilled into the redeem field. Written by
    /// the deep-link hook in GymTrackerApp, consumed (and cleared) by
    /// InviteRedeemSection on appear. Never a reward by itself — the
    /// code still has to pass validation and Apple's sheet.
    static let deepLinkCodeKey = "gymtracker.invite.deepLinkCode.v1"

    /// 31 characters — no 0/O, 1/I, or L, the pairs people actually
    /// confuse. 5/S stay: the code is shown monospaced and is normally
    /// copied, not retyped.
    static let alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

    /// 8 characters, shown grouped as XXXX-XXXX.
    /// Off until redemption works end to end. Apple's code sheet only
    /// accepts Apple-issued offer codes, so a friend's 8-character invite
    /// code can never grant the promised free week, and the sharer reward
    /// has no confirmation step yet. Showing it would be a broken feature
    /// (App Review 2.1). Turn on once codes are real one-time offer codes.
    static let isEnabled = false

    static let codeLength = 8

    /// The deep link a shared invite carries. The `gymtracker` scheme is
    /// already registered in Info.plist; the app-side handler is a
    /// separate hook (see the coordinator note in the debug report).
    static func deepLink(for code: String) -> URL {
        URL(string: "gymtracker://invite?code=\(display(normalize(code)))")!
    }

    /// Pull an invite code out of a `gymtracker://invite?code=…` link.
    /// Nil for any other URL, or a code that fails the format check.
    static func code(from url: URL) -> String? {
        guard url.scheme == "gymtracker", url.host == "invite" else { return nil }
        guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else { return nil }
        let code = normalize(raw)
        return isValidFormat(code) ? code : nil
    }

    /// Uppercase, no hyphens or spaces — the canonical stored form.
    static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { $0 != "-" && !$0.isWhitespace }
    }

    /// 8 characters, all from the alphabet.
    static func isValidFormat(_ normalized: String) -> Bool {
        normalized.count == codeLength && normalized.allSatisfy { alphabet.contains($0) }
    }

    /// Group as XXXX-XXXX for display (and for partial input while
    /// typing: a 5-character entry shows as XXXX-X).
    static func display(_ normalized: String) -> String {
        guard normalized.count > 4 else { return normalized }
        let split = normalized.index(normalized.startIndex, offsetBy: 4)
        return "\(normalized[..<split])-\(normalized[split...])"
    }

    /// What a typed field holds: normalized, alphabet-only, capped at
    /// 8 characters, grouped as the user types.
    static func formattedInput(_ raw: String) -> String {
        let clean = normalize(raw).filter { alphabet.contains($0) }
        return display(String(clean.prefix(codeLength)))
    }

    /// One code, drawn from the system RNG. Called once per device —
    /// the result is persisted, never regenerated.
    static func generate() -> String {
        var raw = ""
        while raw.count < codeLength {
            raw.append(alphabet.randomElement()!)
        }
        return raw
    }
}

/// The outcome of checking a friend's entered code, before anything
/// is presented or recorded.
enum InviteCodeValidation: Equatable {
    /// A usable code, in canonical (normalized, hyphenless) form.
    case valid(String)
    /// Not 8 alphabet characters — a typo or a paste of something else.
    case invalidFormat
    /// The device's own code — you can't redeem your own invite.
    case ownCode
    /// Already redeemed on this phone — each code works once per device.
    case alreadyRedeemed
}

/// Owns the invite state. Plain ObservableObject, same pattern as
/// WorkoutStore / MCPServer. All reads and writes are on-device
/// (SharedDefaults.store) and all calls come from user taps.
final class InviteCodeManager: ObservableObject {
    static let shared = InviteCodeManager()

    /// This device's code — generated once on first access, then read
    /// back forever. One code per device, by construction.
    @Published private(set) var myCode: String

    /// Codes this device has redeemed (confirmed by a Pro entitlement).
    @Published private(set) var redeemedCodes: [String]

    /// Codes the redemption sheet was opened for, not yet confirmed.
    /// Kept separate so cancelling Apple's sheet never blocks a retry.
    @Published private(set) var attemptedCodes: [String]

    /// Friends whose redemption has been confirmed. Always 0 until the
    /// referral ledger exists — nothing on-device can raise it. It is
    /// still persisted (rather than hardcoded) so the ledger, when it
    /// lands, has a key to write to.
    @Published private(set) var confirmedFriendRedemptions: Int

    /// This device's code, grouped for display (XXXX-XXXX).
    var displayCode: String { InviteCode.display(myCode) }

    /// The sharer's 7 days: queued until the ledger lands. True only
    /// when a friend's redemption has been confirmed.
    var sharerRewardReady: Bool { confirmedFriendRedemptions > 0 }

    init() {
        let store = SharedDefaults.store
        if let existing = store.string(forKey: InviteCode.codeKey),
           InviteCode.isValidFormat(existing) {
            myCode = existing
        } else {
            // Generate into a local first: reading `myCode` here would
            // touch `self` before the other stored properties are set.
            let generated = InviteCode.generate()
            myCode = generated
            store.set(generated, forKey: InviteCode.codeKey)
        }
        redeemedCodes = store.stringArray(forKey: InviteCode.redeemedCodesKey) ?? []
        attemptedCodes = store.stringArray(forKey: InviteCode.attemptedCodesKey) ?? []
        confirmedFriendRedemptions = store.integer(forKey: InviteCode.confirmedFriendsKey)
    }

    /// The anti-abuse gate, in order: format, own code, already redeemed.
    /// A code that was attempted but never confirmed is NOT refused —
    /// the user may have cancelled Apple's sheet.
    func validate(_ raw: String) -> InviteCodeValidation {
        let code = InviteCode.normalize(raw)
        guard InviteCode.isValidFormat(code) else { return .invalidFormat }
        if code == myCode { return .ownCode }
        if redeemedCodes.contains(code) { return .alreadyRedeemed }
        return .valid(code)
    }

    /// Record that the redemption sheet was opened for this code.
    func recordAttempt(_ code: String) {
        guard !attemptedCodes.contains(code) else { return }
        attemptedCodes.append(code)
        SharedDefaults.store.set(attemptedCodes, forKey: InviteCode.attemptedCodesKey)
    }

    /// Confirm a redemption after Pro is active. Moves the code from
    /// attempted to redeemed — a redeemed code can never be used again
    /// on this phone.
    func confirmRedemption(_ code: String) {
        if !redeemedCodes.contains(code) {
            redeemedCodes.append(code)
            SharedDefaults.store.set(redeemedCodes, forKey: InviteCode.redeemedCodesKey)
        }
        attemptedCodes.removeAll { $0 == code }
        SharedDefaults.store.set(attemptedCodes, forKey: InviteCode.attemptedCodesKey)
    }

    /// Apple's native redemption sheet. It has no completion callback:
    /// the caller records the attempt first, then confirms via a Pro
    /// entitlement refresh ("Check Pro status" in the UI).
    func presentRedemptionSheet() {
        // StoreKit 1 redemption sheet: `AppStore.presentCodeRedemptionSheet()`
        // does not exist in this SDK (Xcode 27.2, 2026-11-10 build failure),
        // so use the long-standing SKPaymentQueue API instead. Same sheet,
        // same behaviour — the friend redeems the code in Apple's UI.
        SKPaymentQueue.default().presentCodeRedemptionSheet()
    }

    /// What the native share sheet sends: a short message plus the
    /// `gymtracker://invite?code=…` link. User-initiated only — nothing
    /// here ever shares without a tap. The message promises the friend
    /// 7 days free, not the sharer's — the sharer's week is queued
    /// until the ledger exists, and the outbound message must not
    /// promise what isn't built yet.
    func shareItems() -> [Any] {
        let link = InviteCode.deepLink(for: myCode)
        let text = "Join me on Status — track your workouts and get stronger. Use my invite code \(displayCode) and you'll get 7 days of Pro free. \(link.absoluteString)"
        return [text, link]
    }
}

// MARK: - Invite screen (Profile → Invite friends)

/// The full invite screen: your code + share, how it works, redeem a
/// friend's code, and the sharer's queued reward. Presented as a sheet
/// from Profile. Needs SubscriptionState in the environment (for the
/// "Check Pro status" refresh after the redemption sheet).
struct InviteView: View {
    var onClose: () -> Void

    @ObservedObject private var manager = InviteCodeManager.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    InviteCodeCard()
                    howItWorks
                    InviteRedeemSection()
                    sharerRewardCard
                    Text("Invite codes live only on this phone. Sharing only happens when you tap Share — nothing is sent automatically.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding()
            }
            .navigationTitle("Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How it works")
                .font(.headline)
            howItWorksRow(number: "1", text: "Share your code with a friend — Messages, AirDrop, Mail, or copy it.")
            howItWorksRow(number: "2", text: "They enter it here, or tap the link you sent, and get 7 days of Pro free.")
            howItWorksRow(number: "3", text: "You get 7 days free too, once their redemption can be confirmed.")
        }
        .padding()
        .themeCard()
    }

    private func howItWorksRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.subheadline.weight(.bold))
                .frame(width: 28, height: 28)
                .background(Theme.cardElevated)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
    }

    /// The sharer's 7 days, as a queued state — never a promise with a
    /// date. It starts once a friend's redemption can be confirmed, and
    /// that confirmation step doesn't exist yet.
    private var sharerRewardCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your 7 days free")
                .font(.headline)
            if manager.sharerRewardReady {
                Text("\(manager.confirmedFriendRedemptions) friend\(manager.confirmedFriendRedemptions == 1 ? "" : "s") joined — your free week starts now.")
                    .font(.subheadline)
            } else {
                Text("Queued. Your free week starts once a friend's redemption can be confirmed — that confirmation step is still being built, so nothing is counted yet. Your code still works for your friends today.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding()
        .themeCard()
    }
}

/// Your code, with Copy and Share. Used by InviteView and the onboarding
/// quiz step — one card, one code, everywhere.
struct InviteCodeCard: View {
    @ObservedObject private var manager = InviteCodeManager.shared
    @State private var showShare = false
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your invite code")
                .font(.headline)
            Text(manager.displayCode)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
            HStack(spacing: 12) {
                Button("Copy code") {
                    UIPasteboard.general.string = manager.displayCode
                    justCopied = true
                }
                .buttonStyle(.bordered)
                Button("Share") { showShare = true }
                    .buttonStyle(.bordered)
            }
            if justCopied {
                Text("Copied — paste it anywhere.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding()
        .themeCard()
        .sheet(isPresented: $showShare) {
            ShareSheet(activityItems: manager.shareItems())
        }
    }
}

// MARK: - Redeem a friend's code

/// The friend side: enter a code, pass the on-device checks, open
/// Apple's redemption sheet, then confirm via a Pro entitlement
/// refresh. Used by InviteView and the onboarding quiz step. Needs
/// SubscriptionState in the environment.
struct InviteRedeemSection: View {
    @ObservedObject private var manager = InviteCodeManager.shared
    @EnvironmentObject private var subscription: SubscriptionState

    @State private var codeText = ""
    @State private var statusMessage: String?
    @State private var statusIsError = true
    @State private var sheetOpened = false
    @State private var lastAttemptedCode: String?
    @State private var checkingPro = false
    @State private var redeemed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Have a friend's code?")
                .font(.headline)
            Text("Enter it below — you'll get 7 days of Pro free.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            TextField("Invite code, like ABCD-1234", text: $codeText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onChange(of: codeText) { _, newValue in
                    codeText = InviteCode.formattedInput(newValue)
                }
                .withKeyboardDoneToolbar()
            Button("Redeem 7 days free") { redeem() }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .buttonStyle(.plain)
                .disabled(codeText.isEmpty)
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Theme.vividRed : Theme.secondaryText)
            }
            if sheetOpened, let code = lastAttemptedCode, !redeemed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple's redemption sheet is open — or just closed. Finish there, then tap below to check your Pro status.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Button(checkingPro ? "Checking…" : "Check Pro status") {
                        checkPro(code: code)
                    }
                    .buttonStyle(.bordered)
                    .disabled(checkingPro)
                }
            }
            if redeemed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Done — Pro is active. Enjoy your 7 days free.")
                        .font(.subheadline.weight(.semibold))
                    if let expiry = subscription.inviteProExpiresAt {
                        Text("Pro free until \(expiry.formatted(date: .abbreviated, time: .omitted)).")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        .padding()
        .themeCard()
        // A tapped invite link stashes its code in deepLinkCodeKey (see
        // the GymTrackerApp hook); prefill it here and consume it, so
        // the friend only has to tap Redeem.
        .onAppear {
            let store = SharedDefaults.store
            if let pending = store.string(forKey: InviteCode.deepLinkCodeKey),
               InviteCode.isValidFormat(pending) {
                codeText = InviteCode.display(pending)
            }
            store.removeObject(forKey: InviteCode.deepLinkCodeKey)
        }
    }

    /// Validate on-device, then open Apple's sheet. The attempt is
    /// recorded first (so a return to this screen remembers it); the
    /// code only counts as redeemed once Pro is confirmed below.
    private func redeem() {
        redeemed = false
        sheetOpened = false
        switch manager.validate(codeText) {
        case .invalidFormat:
            statusMessage = "That code doesn't look right — invite codes are 8 letters and numbers, like ABCD-1234."
            statusIsError = true
        case .ownCode:
            statusMessage = "That's your own code — share it with a friend instead. You can't redeem your own invite."
            statusIsError = true
        case .alreadyRedeemed:
            statusMessage = "You've already used this code — each invite code works once per phone."
            statusIsError = true
        case .valid(let code):
            lastAttemptedCode = code
            manager.recordAttempt(code)
            statusMessage = nil
            sheetOpened = true
            manager.presentRedemptionSheet()
        }
    }

    /// Apple's sheet has no completion callback, so confirmation is a
    /// Pro entitlement refresh. If Pro is active, the code is marked
    /// redeemed (and can never be used again on this phone). If not,
    /// the code stays attempt-only, so the user can try again.
    private func checkPro(code: String) {
        checkingPro = true
        // @MainActor: the state writes below must land on the main
        // thread, and the entitlement refresh is MainActor-isolated.
        Task { @MainActor in
            let isPro = await subscription.refreshProStatusAfterInviteRedemption()
            checkingPro = false
            if isPro {
                manager.confirmRedemption(code)
                redeemed = true
                statusMessage = nil
            } else {
                statusMessage = "Pro isn't active yet — if you just redeemed, wait a moment and try again, or check the code and try once more."
                statusIsError = true
            }
        }
    }
}

// MARK: - Onboarding quiz step

/// The invite step in the setup quiz: your code + share, and the same
/// redeem section as Profile. Skippable with Continue — it is also in
/// Profile later, so nobody is stuck here.
struct InviteQuizStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Invite friends — they get 7 days of Pro free")
                    .font(.title2)
                    .bold()
                Text("Share your code and a friend gets a free week of Pro. Your own free week starts once their redemption can be confirmed.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            InviteCodeCard()
            InviteRedeemSection()
            Text("You can find this later in Profile — Invite friends. Tap Continue to skip.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
