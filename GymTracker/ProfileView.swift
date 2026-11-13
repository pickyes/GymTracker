import SwiftUI
import UIKit
import StoreKit

/// One row on the Profile page, laid out like Apple's Settings app
/// (Nov 12): an icon tile, a title, and its own page with a header card
/// (icon, title, one-line description) above the controls.
enum ProfileSection: String, CaseIterable, Identifiable, Hashable {
    case program, bodyweight, gyms, exercises, injuries, weights, limits, muse, pro, settings, legal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .program: return "Your Program"
        case .bodyweight: return "Bodyweight"
        case .gyms: return "Gym Profiles"
        case .exercises: return "Exercises"
        case .injuries: return "Body"
        case .weights: return "Working Weights"
        case .limits: return "Limits & Swaps"
        case .muse: return "Muse Access"
        case .pro: return "Status Pro"
        case .settings: return "Settings"
        case .legal: return "Privacy & About"
        }
    }

    var icon: String {
        switch self {
        case .program: return "calendar"
        case .bodyweight: return "scalemass.fill"
        case .gyms: return "building.2.fill"
        case .exercises: return "figure.strengthtraining.traditional"
        case .injuries: return "bandage.fill"
        case .weights: return "dumbbell.fill"
        case .limits: return "arrow.triangle.swap"
        case .muse: return "desktopcomputer"
        case .pro: return "star.fill"
        case .settings: return "gearshape.fill"
        case .legal: return "hand.raised.fill"
        }
    }

    var tint: Color {
        switch self {
        case .program: return .blue
        case .bodyweight: return .teal
        case .gyms: return .indigo
        case .exercises: return .orange
        case .injuries: return .red
        case .weights: return .gray
        case .limits: return .pink
        case .muse: return .purple
        case .pro: return .yellow
        case .settings: return .gray
        case .legal: return .blue
        }
    }

    var blurb: String {
        switch self {
        case .program: return "The plan you're following, every program you've made, and setup."
        case .bodyweight: return "Your current weight, used for bodyweight exercises and progress."
        case .gyms: return "The equipment at each place you train — home, gym, travel."
        case .exercises: return "The weight you're working with on each exercise, and exercises you've added."
        case .injuries: return "Your weight, sore spots to train around, and what they swap out."
        case .weights: return "The weight you're working with on each exercise in your program."
        case .limits: return "What your injuries rule out, and what replaced it."
        case .muse: return "Let Muse on your Mac read your workouts over your own Wi-Fi."
        case .pro: return "Your subscription, purchases, and restore."
        case .settings: return "Units, appearance, rest timer, calendar, privacy, and more."
        case .legal: return "Privacy policy, terms of use, and how your data is kept."
        }
    }

    /// Sections that open an existing page directly (it has its own
    /// title and controls).
    var opensOwnPage: Bool {
        switch self {
        case .gyms, .exercises, .injuries, .settings: return true
        default: return false
        }
    }
}

/// The colored rounded-square icon tile used in the Profile list.
struct SectionIconTile: View {
    let section: ProfileSection
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: section.icon)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(section.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct ProfileView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @Environment(\.duoWide) private var wide
    @Environment(\.duoSwapped) private var swapped
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var subscription: SubscriptionState
    @EnvironmentObject var mcpServer: MCPServer
    @State private var weightText: String = ""
    @State private var didSetup = false
    @State private var showPaywall = false
    @State private var showInvite = false
    @State private var showManageSubscription = false
    @State private var showPrivacyPolicy = false
    @State private var showExport = false
    @State private var showRetakeConfirm = false
    @State private var exportURL: URL?
    @State private var isApproving = false
    @State private var grantMessage: String?
    /// Folded: the pushed section.
    @State private var path: [ProfileSection] = []
    /// Open Duo: the section shown beside the list (first one by
    /// default, like Settings opening on General).
    @State private var selected: ProfileSection = .program
    /// True once a section was picked by hand. Folding only carries a
    /// hand-picked section over; otherwise it lands on the list.
    @State private var userPicked = false

    /// Grouped like Settings: you and your plan, your body, the app.
    /// Settings-app groups (DaRon picked layout A): Your Program on its
    /// own, then Training, Body and App.
    private var groups: [(title: String, sections: [ProfileSection])] {
        // Combined pages (DaRon): Body = bodyweight + injuries + limits,
        // Exercises = working weights + custom exercises, Settings =
        // settings + privacy & about.
        [
            ("Training", [.gyms, .exercises, .injuries]),
            ("App", [.muse, .pro, .settings]),
        ]
    }

    var body: some View {
        Group {
            if wide {
                // The list keeps the front screen's exact width and side
                // (right, like Today) for a seamless unfold; the section
                // waits on the other page. Swap mirrors it.
                DuoPagePair(wide: true, swapped: swapped, stacksWhenTall: false) {
                    detailPane
                } main: {
                    sidebar
                        .background(Theme.card.opacity(0.45))
                }
            } else {
                NavigationStack(path: $path) {
                    rootList
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: ProfileSection.self) { section in
                            sectionPage(section)
                        }
                }
            }
        }
        .disableVerticalBar()
        .onChange(of: wide) { _, isWide in
            // Unfold keeps the open section open; fold pushes the one
            // that was showing beside the list.
            if isWide {
                if let open = path.last { selected = open; userPicked = true }
                path = []
            } else {
                path = userPicked ? [selected] : []
            }
        }
        .onAppear {
            if !didSetup {
                didSetup = true
                if let weight = store.bodyWeightLb {
                    let unit = store.settings.weightUnit
                    weightText = roundedWeightText(unit.displayValue(for: weight) ?? weight)
                }
            }
        }
        .onChange(of: weightText) { _, _ in saveWeight() }
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                programName: store.activeProgram?.name ?? "Your plan",
                onClose: { showPaywall = false },
                onPurchased: { showPaywall = false }
            )
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscription)
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView(onClose: { showPrivacyPolicy = false })
        }
        .sheet(isPresented: $showInvite) {
            InviteView(onClose: { showInvite = false })
        }
        .sheet(isPresented: $showExport) {
            if let exportURL {
                ShareSheet(activityItems: [exportURL])
            }
        }
    }

    // MARK: List (folded page / open sidebar)

    /// Folded: the Settings-style list; each row pushes its page.
    private var rootList: some View {
        List {
            PageTitle(text: "Profile")
                // In the clock's row, like Today (Nov 12).
                .padding(.top, 30)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
            Section {
                NavigationLink(value: ProfileSection.program) { summaryCard }
            }
            Section {
                NavigationLink(value: ProfileSection.program) { sectionRow(.program) }
            }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.sections) { section in
                        NavigationLink(value: section) { sectionRow(section) }
                    }
                }
            }
            clearanceRow
        }
        .listStyle(.insetGrouped)
        .oledList()
        .ignoresSafeArea(edges: .top)
        .infinityTopEdge()
    }

    /// Open Duo: the same list as a sidebar; the chosen row is lit and
    /// its page shows beside it.
    private var sidebar: some View {
        List {
            PageTitle(text: "Profile")
                .padding(.top, 30)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
            Section {
                // The header opens Your Program too, but only the row
                // below lights up for it (one highlight, not two).
                Button { selected = .program; userPicked = true } label: { summaryCard }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
            }
            Section {
                sidebarButton(.program) { sectionRow(.program) }
            }
            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.sections) { section in
                        sidebarButton(section) { sectionRow(section) }
                    }
                }
            }
            clearanceRow
        }
        // Grouped rounded sections inside the page margins, like the
        // Settings app (the plain list ran the icons off the edge).
        .listStyle(.insetGrouped)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        // The title sits in the clock's row, like the other pages.
        .contentMargins(.top, 0, for: .scrollContent)
        .oledList()
        .ignoresSafeArea(edges: .top)
        .infinityTopEdge()
    }

    /// A sidebar row: opens its page beside the list; the open one is lit.
    private func sidebarButton<Label: View>(_ section: ProfileSection, @ViewBuilder label: () -> Label) -> some View {
        Button { selected = section; userPicked = true } label: {
            label()
        }
        .buttonStyle(.plain)
        .listRowBackground(selected == section ? Color.accentColor.opacity(0.3) : Theme.card)
    }

    /// Apple Account-style card at the top: the plan you're on.
    private var summaryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 58, height: 58)
                .background(Color.accentColor.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.profile?.name ?? store.activeProgram?.name ?? "No program yet")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                if let program = store.activeProgram, let profile = store.profile {
                    Text(profile.name == nil
                         ? "\(profile.goal.label) · \(daysPerWeekText(program.days.count)) · \(subscription.isPro ? "Pro" : "Free")"
                         : "\(program.name) · \(subscription.isPro ? "Pro" : "Free")")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("Set up your plan, gyms, and body.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func sectionRow(_ section: ProfileSection) -> some View {
        HStack(spacing: 14) {
            SectionIconTile(section: section)
            Text(section.title)
                .foregroundStyle(Theme.text)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var clearanceRow: some View {
        Color.clear
            .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    // MARK: Section pages

    @ViewBuilder
    private var detailPane: some View {
        NavigationStack {
            sectionPage(selected)
        }
        .id(selected)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func sectionPage(_ section: ProfileSection) -> some View {
        switch section {
        case .gyms: GymProfilesView()
        case .exercises, .weights:
            CustomExercisesView(leadingSections: AnyView(Group {
                Section { headerCard(.exercises) }
                weightsContent
            }))
            .toolbar(wide ? .hidden : .automatic, for: .navigationBar)
        case .settings, .legal:
            SettingsView(trailingSections: AnyView(legalContent))
        case .injuries, .bodyweight, .limits:
            List {
                Section { headerCard(.injuries) }
                bodyweightContent
                Section("Sore spots") {
                    InjuryEditorView(embedded: true)
                        .padding(.vertical, 6)
                }
                if !(store.profile?.limits.isEmpty ?? true) || store.activeProgram?.isPreset == true {
                    limitsContent
                }
                clearanceRow
            }
            .listStyle(.insetGrouped)
            .oledList()
            .navigationTitle("Body")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(wide ? .hidden : .automatic, for: .navigationBar)
            .withKeyboardDoneToolbar()
            .scrollDismissesKeyboard(.interactively)
        default:
            List {
                Section { headerCard(section) }
                sectionContent(section)
                clearanceRow
            }
            .listStyle(.insetGrouped)
            .oledList()
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
            // Open Duo: the header card is the title, so the page drops
            // the nav bar and starts at the top (Nov 12).
            .toolbar(wide ? .hidden : .automatic, for: .navigationBar)
            .withKeyboardDoneToolbar()
            .scrollDismissesKeyboard(.interactively)
        }
    }

    /// Settings-style header: big icon tile, title, one-line blurb.
    private func headerCard(_ section: ProfileSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionIconTile(section: section, size: 58)
            Text(section.title)
                .font(.title2.weight(.bold))
            Text(section.blurb)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func sectionContent(_ section: ProfileSection) -> some View {
        switch section {
        case .program: programContent
        case .bodyweight: bodyweightContent
        case .weights: weightsContent
        case .limits: limitsContent
        case .muse: museContent
        case .pro: proContent
        case .legal: legalContent
        case .gyms, .exercises, .injuries, .settings: EmptyView()
        }
    }

    @ViewBuilder private var bodyweightContent: some View {
        Section {
            HStack {
                TextField("Enter your weight", text: $weightText)
                    .keyboardType(.decimalPad)
                Text(store.settings.weightUnit.label)
                    .foregroundStyle(Theme.secondaryText)
            }
        } footer: {
            if store.bodyWeightLb == nil {
                Text("Not set yet. Your weight is never guessed — enter it when you know it.")
            }
        }
    }

    @ViewBuilder private var programContent: some View {
        Section("Current") {
            if let program = store.activeProgram {
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.name)
                        .font(.headline)
                    if let profile = store.profile {
                        Text("\(profile.goal.label) · \(daysPerWeekText(program.days.count)) · \(profile.equipmentLabel)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            NavigationLink("All programs") { ProgramsView() }
            // Switch back to the generated program, if it isn't active.
            if let generated = store.generatedProgram, generated.id != store.activeProgram?.id {
                Button {
                    store.useGeneratedProgram()
                } label: {
                    programRow(name: generated.name, active: false)
                }
                .buttonStyle(.plain)
            }
            // Restore DaRon's preset: only on his unlocked device, and
            // only while the preset is NOT the active program.
            if store.isDaronPresetUnlocked && !store.isPresetActive {
                Button("Restore DaRon's 5-Day Split") {
                    store.restoreDaronPreset()
                }
            }
        }
        Section {
            Button("Retake setup") {
                showRetakeConfirm = true
            }
            .confirmationDialog("Retake setup?", isPresented: $showRetakeConfirm) {
                Button("Start setup") { store.resetOnboarding() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This starts the setup quiz again. Your current program and profile stay saved — you can keep them when setup finishes.")
            }
        } footer: {
            if let id = store.activeGymProfileID,
               let profile = store.gymProfiles.first(where: { $0.id == id }) {
                Text("Gym: \(profile.name)")
            }
        }
    }

    @ViewBuilder private var weightsContent: some View {
        Section {
            if workingWeights.isEmpty {
                Text("Log a session and your working weights will show up here.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(workingWeights, id: \.name) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.name)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer()
                        Text(item.weight)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    if let note = item.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder private var limitsContent: some View {
        if let limits = store.profile?.limits, !limits.isEmpty {
            Section("Limits") {
                ForEach(Array(limits).sorted { $0.label < $1.label }, id: \.self) { limit in
                    Text(limit.label)
                        .font(.subheadline)
                }
                if let other = store.profile?.otherLimitText, !other.isEmpty {
                    Text("Other: \(other)")
                        .font(.subheadline)
                }
            }
            if let swaps = store.adaptedActiveProgram?.swaps, !swaps.isEmpty {
                // Enumerated ids: a program can swap the same exercise on
                // two days, and duplicate ForEach ids break the list.
                Section("Swaps") {
                    ForEach(Array(swaps.enumerated()), id: \.offset) { _, swap in
                        Text(swap.displayText)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        if store.activeProgram?.isPreset == true {
            Section("Left shoulder") {
                Text("Stop and swap anything that pinches the front of the left shoulder. No overhead pressing that hurts. Incline DB press is out — cable chest fly replaces it on push day. No RDLs — DB hip thrust instead. No one-arm rows.")
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder private var museContent: some View {
        // MCP server (off by default). LAN-only, foreground-only. CONNECT
        // creates a PENDING grant (no token yet) — nothing can
        // authenticate until it's approved with Face ID. Approve mints
        // the token exactly once; Disconnect deletes the grant.
        // Read-only by default; gym:write only on the second explicit tap.
        Section {
            if mcpServer.hasActiveGrant {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(mcpServer.isRunning ? "Connected" : "Stopped — open the app")
                        .foregroundStyle(mcpServer.isRunning ? Theme.vividGreen : Theme.secondaryText)
                }
                if let url = mcpServer.url {
                    HStack {
                        Text("URL")
                        Spacer()
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Button("Copy URL") {
                        UIPasteboard.general.string = url
                    }
                }
                HStack {
                    Text("Token")
                    Spacer()
                    Text(String(mcpServer.token.prefix(8)) + "…")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Copy") {
                        UIPasteboard.general.string = mcpServer.token
                    }
                    Button("Regenerate") {
                        mcpServer.regenerateToken()
                    }
                }
                .font(.caption)
                .buttonStyle(.borderless)
                Text("Runs only while this app is open. Muse on your Mac connects to it (or to the Mac companion server). Only Muse can connect — no other agent is allowed. The server never sends data to the internet.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Button("Disconnect") {
                    grantMessage = nil
                    mcpServer.disconnect()
                }
            } else if mcpServer.grant?.status == .pending {
                HStack {
                    Text("Status")
                    Spacer()
                    Text("Waiting for approval")
                        .foregroundStyle(Theme.secondaryText)
                }
                Text("Muse asked to connect. Approve with Face ID to let it in — read-only by default, so Muse can read your workouts but can't log anything.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Button("Approve") {
                    approveGrant(includeWrite: false)
                }
                .disabled(isApproving)
                Button("Allow logging workouts") {
                    approveGrant(includeWrite: true)
                }
                .disabled(isApproving)
                Text("Allowing logging lets Muse log sets and start workouts. You can disconnect anytime.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                if let grantMessage {
                    Text(grantMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Button("Cancel") {
                    grantMessage = nil
                    mcpServer.disconnect()
                }
            } else {
                if mcpServer.grant != nil {
                    Text("Your last connection expired. Tap CONNECT to set up a new one.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Button("CONNECT") {
                    grantMessage = nil
                    mcpServer.requestGrant()
                }
                Text("Only Muse can connect — no other agent is allowed. The server runs only while this app is open and never sends data to the internet.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        Section {
            Button("Export workouts (JSON)") {
                exportWorkouts()
            }
        } footer: {
            Text("Sends a file you choose (Files, AirDrop). The Mac companion server reads this file when the phone isn't reachable. Never automatic.")
        }
    }

    @ViewBuilder private var proContent: some View {
        Section {
            HStack {
                Text(subscription.isPro ? "Pro" : "Free")
                    .font(.headline)
                Spacer()
                if subscription.isPro {
                    Text("Thanks for supporting the app.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Button("View Pro") { showPaywall = true }
                }
            }
            if subscription.isPro {
                Button("Manage Subscription") { showManageSubscription = true }
            }
            Button("Restore Purchases") {
                Task { await subscription.restore() }
            }
        }
        if InviteCode.isEnabled {
            Section("Invite friends") {
                HStack {
                    Text(InviteCodeManager.shared.displayCode)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button("Invite friends") { showInvite = true }
                }
                Text("Share your code — a friend gets 7 days of Pro free, and so do you.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    @ViewBuilder private var legalContent: some View {
        Section {
            Button("Privacy Policy") { showPrivacyPolicy = true }
            Link("Terms of Use (EULA)", destination: PaywallView.termsOfUseURL)
        }
        Section("About") {
            Text("Status v1.0 — your data stays on this device. No account, no network.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func programRow(name: String, active: Bool) -> some View {
        HStack {
            Text(name)
                .font(.subheadline)
            Spacer()
            if active {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// Working weights for the active program's exercises — only the ones
    /// with a weight set (last logged or default). Numbers only, so the rows
    /// never squeeze on the folded display.
    private var workingWeights: [(name: String, weight: String, note: String?)] {
        // The adapted program: a swapped-out exercise (squat for a knee
        // injury) doesn't list its old working weight as current.
        guard let program = store.adaptedActiveProgram else { return [] }
        var seen: Set<String> = []
        var items: [(name: String, weight: String, note: String?)] = []
        for day in program.days {
            for template in day.exercises where !seen.contains(template.id) {
                seen.insert(template.id)
                guard let weight = store.lastWeight(for: template) ?? template.defaultWeightLb,
                      weight > 0 else { continue }
                items.append((template.name, store.displayWeightLabel(weight, isPair: template.isPair, for: template), template.weightNote))
            }
        }
        return items
    }

    /// Face ID-gated approval for the pending Muse grant. Read-only by
    /// default; gym:write only when includeWrite is true (the second
    /// explicit tap). On Face ID failure or cancel the grant stays
    /// pending — no token is issued — and the message says so plainly.
    /// The token is minted exactly once, inside approveGrant on the
    /// server; nothing here re-mints it (not on appear, not on retry —
    /// a retry just re-runs Face ID against the same pending grant).
    private func approveGrant(includeWrite: Bool) {
        isApproving = true
        grantMessage = nil
        mcpServer.approveGrantWithBiometrics(includeWrite: includeWrite) { result in
            isApproving = false
            switch result {
            case .success:
                grantMessage = nil
            case .failure(let error):
                grantMessage = error.localizedDescription
            }
        }
    }

    private func saveWeight() {
        let cleaned = weightText.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty {
            store.saveBodyWeight(nil)
        } else if let value = Double(cleaned), value > 0 {
            store.saveBodyWeight(store.settings.weightUnit.storedValue(for: value) ?? value)
        }
    }

    /// User-initiated JSON export (share sheet). Writes a temp file and
    /// presents the share sheet; the user chooses where it goes.
    private func exportWorkouts() {
        let payload = GymTrackerExport.current(store: store)
        guard let data = payload.jsonData() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gym-tracker-workouts.json")
        do {
            try data.write(to: url)
            exportURL = url
            showExport = true
        } catch {
            // If the write fails there's nothing to share.
        }
    }
}

/// Edit injuries from Profile. Local state while editing; saves (and
/// regenerates the generated program so the new swaps apply) when the user
/// taps Save or leaves the screen. A no-op save is skipped so the program
/// is never regenerated when nothing changed.
struct InjuryEditorView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    @State private var parts: Set<BodyPart> = []
    @State private var otherText: String = ""
    @State private var didSetup = false
    /// Inside the combined Body page's list: just the editor (no scroll
    /// view or toolbar of its own); it still saves when it goes away.
    var embedded = false

    var body: some View {
        if embedded {
            editor
                .buttonStyle(.borderless)
                .onAppear(perform: setup)
                .onDisappear { save() }
                // One save shortly after you stop tapping or typing
                // (each save rebuilds the program; text also saves).
                .onChange(of: parts) { _, _ in scheduleSave() }
                .onChange(of: otherText) { _, _ in scheduleSave() }
        } else {
            standalone
        }
    }

    @State private var saveTask: Task<Void, Never>?

    private func scheduleSave() {
        guard didSetup else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func setup() {
        if !didSetup {
            didSetup = true
            parts = store.profile?.injuredParts ?? []
            otherText = store.profile?.otherLimitText ?? ""
        }
    }

    private var editor: some View {
            VStack(alignment: .leading, spacing: 20) {
                Text("Tap the body to mark a spot as injured or limited. The program swaps exercises for that spot — tap again to unmark.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Text("Marking a spot only changes your exercises — it isn't a diagnosis, and it doesn't mean an exercise is safe for you. Check with your doctor or physical therapist before training around an injury.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                BodyDiagramView(selected: $parts)
                if !parts.isEmpty {
                    Button("Clear all marked spots") {
                        withAnimation(AppAnimation.snappy) { parts = [] }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Clear all marked spots")
                }
                TextField("Something else? Tell us briefly (stays on this phone)", text: $otherText)
                    .textFieldStyle(.roundedBorder)
                ForEach(Array(derivedLimits).sorted { $0.label < $1.label }, id: \.self) { limit in
                    if !limit.hint.isEmpty {
                        Text("\(limit.label): \(limit.hint)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
    }

    private var standalone: some View {
        ScrollView {
            editor
            // Same 16pt sides/top as before; the bottom is the shared
            // LayoutClearance rule (Debug Pass 2) so the last hint line
            // scrolls clear of the floating menu button — and of the
            // rest-timer panel while a rest runs. The old uniform
            // 16pt padding left the bottom content under the button.
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
            // Keyboard Done + tap-outside: same as Profile above — the
            // "Something else?" field had no way out either. Done
            // dismisses; the text saves via Save or on leave.
            // NOTE (2026-11-10): the .dismissKeyboardOnTapOutside()
            // that used to sit here is REMOVED — it swallowed the body
            // diagram's muscle Buttons (verified on screen: 4 taps on
            // the front figure — shoulder x3, abs x1 — marked nothing,
            // while the Front/Back picker in the same view worked, so
            // the parent .onTapGesture was eating the diagram taps, the
            // same arena defect as the Profile List rows at :353).
            // Keyboard dismissal stays covered by the native Done
            // toolbar + .scrollDismissesKeyboard(.interactively).
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Injuries")
        .navigationBarTitleDisplayMode(.inline)
        .withKeyboardDoneToolbar()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear {
            if !didSetup {
                didSetup = true
                parts = store.profile?.injuredParts ?? []
                otherText = store.profile?.otherLimitText ?? ""
            }
        }
        .onDisappear { save() }
    }

    private var derivedLimits: Set<Limit> {
        var set = Set(parts.map { $0.limit })
        if !otherText.trimmingCharacters(in: .whitespaces).isEmpty { set.insert(.other) }
        return set
    }

    private func save() {
        let currentParts = store.profile?.injuredParts ?? []
        let currentOther = store.profile?.otherLimitText ?? ""
        guard parts != currentParts || otherText != currentOther else { return }
        store.updateInjuries(parts: parts, otherText: otherText)
    }
}

// MARK: - Share sheet (UIActivityViewController)

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
