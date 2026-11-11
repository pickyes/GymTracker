import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var subscription: SubscriptionState
    @EnvironmentObject var mcpServer: MCPServer
    @State private var weightText: String = ""
    @State private var didSetup = false
    @State private var showPaywall = false
    @State private var showInvite = false
    @State private var showExport = false
    @State private var showRetakeConfirm = false
    @State private var exportURL: URL?
    @State private var isApproving = false
    @State private var grantMessage: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Same as History: regular width gets a little more title leading so
    /// the first letter isn't clipped by the open display's rounded corner.
    private var titleLeading: CGFloat { horizontalSizeClass == .regular ? 24 : 16 }

    var body: some View {
        NavigationStack {
            List {
                // Title lines up with the section headers and card text
                // below it (same 16pt leading), not flush to the edge.
                PageTitle(text: "Profile")
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: titleLeading, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                Section("Bodyweight") {
                    HStack {
                        TextField("Enter your weight", text: $weightText)
                            .keyboardType(.decimalPad)
                        Text(store.settings.weightUnit.label)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if store.bodyWeightLb == nil {
                        Text("Not set yet. Your weight is never guessed — enter it when you know it.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Section("Your program") {
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
                    // Restore DaRon's preset (Debug Pass 2): only on his
                    // unlocked device, and only while the preset is NOT the
                    // active program — never offered to users who never
                    // unlocked it. Mirrors the row in ProgramsView.
                    if store.isDaronPresetUnlocked && !store.isPresetActive {
                        Button("Restore DaRon's 5-Day Split") {
                            store.restoreDaronPreset()
                        }
                        .font(.subheadline)
                    }
                    Button("Retake setup") {
                        showRetakeConfirm = true
                    }
                    .font(.subheadline)
                    .confirmationDialog("Retake setup?", isPresented: $showRetakeConfirm) {
                        Button("Start setup") { store.resetOnboarding() }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This starts the setup quiz again. Your current program and profile stay saved — you can keep them when setup finishes.")
                    }
                }

                Section("Gym Profiles") {
                    NavigationLink("Gym profiles") { GymProfilesView() }
                    if let id = store.activeGymProfileID,
                       let profile = store.gymProfiles.first(where: { $0.id == id }) {
                        Text("Active: \(profile.name) — \(profile.equipment.map { $0.label }.sorted().joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("Using your quiz equipment. Add a profile per location — home, gym, travel.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Section("Custom exercises") {
                    NavigationLink("Custom exercises") { CustomExercisesView() }
                    if !store.customExercises.isEmpty {
                        Text("\(store.customExercises.count) custom exercise\(store.customExercises.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Section("Body & injuries") {
                    NavigationLink("Body & injuries") { InjuryEditorView() }
                    if let parts = store.profile?.injuredParts, !parts.isEmpty {
                        Text(parts.map { $0.label }.sorted().joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("Tap the body to mark an injury — the program swaps exercises for that spot.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Section("Working weights") {
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

                if let limits = store.profile?.limits, !limits.isEmpty {
                    Section("Limits & swaps") {
                        ForEach(Array(limits).sorted { $0.label < $1.label }, id: \.self) { limit in
                            Text(limit.label)
                                .font(.subheadline)
                        }
                        if let other = store.profile?.otherLimitText, !other.isEmpty {
                            Text("Other: \(other)")
                                .font(.subheadline)
                        }
                        if let swaps = store.adaptedActiveProgram?.swaps, !swaps.isEmpty {
                            // Enumerated ids, not `\.from`: a program can
                            // swap the same exercise on two days (squat on
                            // Mon and Wed), and duplicate ForEach ids
                            // break the list. The adapted program's swaps
                            // cover the preset too — the stored preset has
                            // none of its own.
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

                Section("Muse access") {
                    // MCP server (off by default). LAN-only, foreground-only.
                    // No cloud, no account, nothing leaves the device except
                    // to Muse on the user's own Mac, on their own local
                    // network. Only Muse can connect.
                    // CONNECT creates a PENDING grant (no token yet) —
                    // nothing can authenticate until DaRon approves it with
                    // Face ID. Approve mints the token exactly once;
                    // Disconnect deletes the grant (the token dies with it).
                    // Read-only by default; gym:write only on the second
                    // explicit tap ("Allow logging workouts"). The old path
                    // (CONNECT straight to isEnabled + start()) bypassed
                    // the grant flow and is gone — every state below goes
                    // through requestGrant / approveGrantWithBiometrics /
                    // disconnect on MCPServer.
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
                            // An active grant that is no longer usable
                            // (expired) — hasActiveGrant is false, so this
                            // is the only way to reach here with a grant.
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
                    Button("Export workouts (JSON)") {
                        exportWorkouts()
                    }
                    Text("Sends a file you choose (Files, AirDrop). The Mac companion server reads this file when the phone isn't reachable. Never automatic.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Section("Status Pro") {
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
                                .font(.subheadline)
                        }
                    }
                    Button("Restore Purchases") {
                        Task { await subscription.restore() }
                    }
                    .font(.subheadline)
                }

                Section("Invite friends") {
                    HStack {
                        Text(InviteCodeManager.shared.displayCode)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button("Invite friends") { showInvite = true }
                            .font(.subheadline)
                    }
                    Text("Share your code — a friend gets 7 days of Pro free, and so do you.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Section {
                    NavigationLink("Settings") { SettingsView() }
                }

                Section("About") {
                    Text("Status v1.0 — your data stays on this device. No account, no network.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                // Bottom breathing room (shared LayoutClearance rule,
                // Debug Pass 2): the last row must scroll fully into
                // view clear of the floating menu button — and of the
                // rest-timer panel above it while a rest runs. The old
                // 40pt spacer was short of the 96pt menu-button value.
                Color.clear
                    .frame(height: LayoutClearance.bottom(restActive: store.isRestActive))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .toolbar(.hidden, for: .navigationBar)
            // Keyboard Done (DaRon 2026-11-10 08:49: the Bodyweight
            // field had NO Done button — typed 160 and the keyboard had
            // no way out). Native toolbar directly above the keyboard;
            // Done dismisses, and the value is already saved by then —
            // weightText saves live on every keystroke (saveWeight via
            // onChange), so dismissing IS confirming. Drag-to-dismiss
            // is the second path — tap-outside is NOT used here: an
            // .onTapGesture on this List swallows the NavigationLink
            // rows' taps (known SwiftUI pitfall — the List's row
            // selection loses the gesture arena to the parent tap),
            // so "All programs" etc. never navigated. (Row-tap
            // diagnosis, 2026-11-10.)
            .withKeyboardDoneToolbar()
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                if !didSetup {
                    didSetup = true
                    if let weight = store.bodyWeightLb {
                        let unit = store.settings.weightUnit
                        weightText = roundedWeightText(unit.displayValue(for: weight) ?? weight)
                    }
                }
            }
            .oledList()
            .onChange(of: weightText) { _, _ in
                saveWeight()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(
                    programName: store.activeProgram?.name ?? "Your plan",
                    onClose: { showPaywall = false },
                    onPurchased: { showPaywall = false }
                )
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
        // Fold (Debug Pass 2): the title leading (16↔24pt) flips
        // discretely on the size class, which used to snap with no
        // animation. Animate it on the shared fold spring so Profile
        // glides with the pose instead of popping.
        .animation(FoldAnimation.morph, value: horizontalSizeClass)
        .disableVerticalBar()
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
    @EnvironmentObject var store: WorkoutStore
    @State private var parts: Set<BodyPart> = []
    @State private var otherText: String = ""
    @State private var didSetup = false

    var body: some View {
        ScrollView {
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
            // Same 16pt sides/top as before; the bottom is the shared
            // LayoutClearance rule (Debug Pass 2) so the last hint line
            // scrolls clear of the floating menu button — and of the
            // rest-timer panel while a rest runs. The old uniform
            // 16pt padding left the bottom content under the button.
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, LayoutClearance.bottom(restActive: store.isRestActive))
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
