import SwiftUI

/// The 8-step setup quiz (+ optional bodyweight + notifications).
/// Every question visibly changes the generated plan — the question title
/// says what it changes. One screen per question, big tappable cards,
/// progress dots, Back on every screen. Goal has a default (Build muscle),
/// so it's skippable; bodyweight is optional.
/// The quiz's answers + position, owned by OnboardingFlowView so going
/// Back from the plan reveal returns to the quiz with every answer kept
/// (the quiz view is recreated on each flow step).
struct SetupQuizState {
    var step = 0
    var profile = UserProfile()
    var weightText = ""
    var isKg = false
}

struct SetupQuizView: View {
    @EnvironmentObject var subscription: SubscriptionState
    @Binding var state: SetupQuizState
    var onComplete: (UserProfile) -> Void
    var onBack: () -> Void

    @State private var isRequestingNotifications = false

    /// The quiz's screens in order. The invite screen only appears while
    /// invites are enabled — otherwise it was a dead screen in the flow.
    enum QuizStep {
        case goal, targetAreas, experience, days, equipment, limits, bodyweight, invite, notifications
    }

    private var steps: [QuizStep] {
        var all: [QuizStep] = [.goal, .targetAreas, .experience, .days, .equipment, .limits, .bodyweight]
        if InviteCode.isEnabled { all.append(.invite) }
        all.append(.notifications)
        return all
    }

    private var totalSteps: Int { steps.count }

    private var step: Int {
        get { min(max(state.step, 0), totalSteps - 1) }
        nonmutating set { state.step = newValue }
    }

    private var currentStep: QuizStep { steps[step] }

    private var profile: UserProfile {
        get { state.profile }
        nonmutating set { state.profile = newValue }
    }
    private var weightText: String {
        get { state.weightText }
        nonmutating set { state.weightText = newValue }
    }
    private var isKg: Bool {
        get { state.isKg }
        nonmutating set { state.isKg = newValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch currentStep {
                    case .goal: goalStep
                    case .targetAreas: targetAreasStep
                    case .experience: experienceStep
                    case .days: daysStep
                    case .equipment: equipmentStep
                    case .limits: limitsStep
                    case .bodyweight: bodyweightStep
                    case .invite: inviteStep
                    case .notifications: notificationsStep
                    }
                }
                .padding()
            }
            // Recreate the ScrollView on every step so its scroll offset
            // resets to the top — otherwise the question text scrolls off
            // and the user only sees the option cards.
            .id(step)
            bottomBar
        }
    }

    // MARK: - Chrome

    private var progressHeader: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Color.accentColor : Theme.track)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: goBack) {
                Text("Back")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .themeCard()
            }
            .buttonStyle(.plain)
            Button(action: goNext) {
                Text(step == totalSteps - 1 ? "Not now" : "Continue")
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

    private func goBack() {
        withAnimation(AppAnimation.page) {
            if step > 0 {
                step -= 1
            } else {
                onBack()
            }
        }
    }

    private func goNext() {
        if currentStep == .bodyweight {
            // Bodyweight is optional — save it if entered, then move on.
            saveBodyweight()
        }
        withAnimation(AppAnimation.page) {
            if step < totalSteps - 1 {
                step += 1
            } else {
                // Last step ("Not now") — finish without notifications.
                profile.notificationsAllowed = false
                onComplete(profile)
            }
        }
    }

    private func saveBodyweight() {
        guard let value = Self.parseDecimal(weightText), value > 0 else {
            profile.bodyweightLb = nil
            return
        }
        profile.bodyweightLb = isKg ? value / 0.45359237 : value
        profile.bodyweightIsKg = isKg
    }

    /// Locale-aware decimal parsing: "72,5" works in comma locales (the
    /// decimal pad types the locale's separator), and "72.5" still works.
    static func parseDecimal(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: cleaned) { return number.doubleValue }
        return Double(cleaned.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Steps

    private func question(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2)
                .bold()
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            question("What's your goal?", "This sets your rep ranges and split emphasis.")
            ForEach(Goal.allCases, id: \.self) { goal in
                optionCard(selected: profile.goal == goal) {
                    profile.goal = goal
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.label).font(.headline)
                        Text(goal.detail).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            if profile.goal == .buildMuscle {
                Text("Build muscle is the default — tap Continue to keep it.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// Target areas (Leap "target-area rows" pattern). Multi-select;
    /// the finisher in the generated plan emphasizes the chosen areas.
    /// Optional — tap Continue to skip.
    private var targetAreasStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            question("What do you want to focus on?", "Pick any — your finisher will emphasize these areas. Optional.")
            ForEach(TargetArea.allCases, id: \.self) { area in
                optionCard(selected: profile.targetAreas.contains(area)) {
                    if profile.targetAreas.contains(area) {
                        profile.targetAreas.remove(area)
                    } else {
                        profile.targetAreas.insert(area)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area.label).font(.headline)
                        Text(area.subtitle)
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            Text("No equipment needed for these — bodyweight works too. Tap Continue to skip.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var experienceStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            question("How experienced are you?", "This sets your starting weights and exercise pool.")
            ForEach(ExperienceLevel.allCases, id: \.self) { level in
                optionCard(selected: profile.experience == level) {
                    profile.experience = level
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.label).font(.headline)
                        Text(level.detail).font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }

    private var daysStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            question("How many days a week?", "This sets your split.")
            ForEach([1, 2, 3, 4, 5, 6, 7], id: \.self) { days in
                optionCard(selected: profile.daysPerWeek == days) {
                    profile.daysPerWeek = days
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(days) day\(days == 1 ? "" : "s")").font(.headline)
                        Text(ProgramGenerator.splitName(for: days) + splitDetail(for: days))
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }

    private func splitDetail(for days: Int) -> String {
        switch days {
        case 1: return " — Full Body"
        case 2: return " — Upper/Lower"
        case 3: return " — Full Body A/B/C"
        case 4: return " — Upper/Lower"
        case 5: return " — Push/Pull/Legs + Upper Mix"
        case 6: return " — Push/Pull/Legs, twice a week"
        case 7: return " — Push/Pull/Legs + Arms & Core"
        default: return ""
        }
    }

    private var equipmentStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            question("What equipment do you have?", "Tap every item — mark what you HAVE and what you DON'T HAVE. Your plan only uses equipment you have, plus bodyweight.")
            // Count of have vs don't have.
            Text("\(profile.equipmentHave.count) have · \(Equipment.allCases.count - profile.equipmentHave.count) don't have")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 8) {
                Button("Have them all") {
                    withAnimation(AppAnimation.snappy) {
                        profile.equipmentHave = Set(Equipment.allCases)
                    }
                }
                .buttonStyle(.bordered)
                Button("Have none") {
                    withAnimation(AppAnimation.snappy) {
                        profile.equipmentHave = [.bodyweight]
                    }
                }
                .buttonStyle(.bordered)
            }
            .font(.caption)
            // No-equipment / bodyweight-only path: a first-class option,
            // not just the "Have none" shortcut. Sets the plan to
            // calisthenics only — the generator's pool is bodyweight
            // exercises, and the catalog's Bodyweight Only programs are
            // the matching ready-made plans.
            optionCard(selected: profile.equipmentHave == [.bodyweight]) {
                withAnimation(AppAnimation.snappy) {
                    profile.equipmentHave = [.bodyweight]
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No equipment — bodyweight only").font(.headline)
                    Text("Calisthenics: push-ups, pull-ups, dips, squats. No equipment needed.")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            if profile.equipmentHave == [.bodyweight] {
                Text("Bodyweight only — your plan will be calisthenics, with bodyweight progressions (harder variations, not heavier weights) as you get stronger.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            // The full checklist: every equipment type, each with its
            // uniform icon, tappable to flip HAVE / DON'T HAVE.
            VStack(spacing: 8) {
                ForEach(Equipment.allCases, id: \.self) { equipment in
                    equipmentRow(equipment)
                }
            }
            Text("Bodyweight is always available — it can't be unmarked.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// One equipment row: uniform icon, name, and a HAVE / DON'T HAVE
    /// toggle. Tap anywhere on the row to flip it.
    private func equipmentRow(_ equipment: Equipment) -> some View {
        let have = profile.equipmentHave.contains(equipment)
        let isBodyweight = equipment == .bodyweight
        return Button {
            guard !isBodyweight else { return }
            withAnimation(AppAnimation.snappy) {
                if have { profile.equipmentHave.remove(equipment) }
                else { profile.equipmentHave.insert(equipment) }
            }
        } label: {
            HStack(spacing: 12) {
                EquipmentIcon(equipment: equipment)
                Text(equipment.label)
                    .font(.headline)
                Spacer()
                // The state: HAVE (green check) or DON'T HAVE (grey).
                HStack(spacing: 6) {
                    Text(have ? "Have" : "Don't have")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(have ? Theme.vividGreen : Theme.secondaryText)
                    Image(systemName: have ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(have ? Theme.vividGreen : Theme.secondaryText)
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(have ? Theme.vividGreen.opacity(0.12) : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(have ? Theme.vividGreen.opacity(0.5) : Theme.border, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBodyweight)
        .accessibilityLabel("\(equipment.label), \(have ? "have" : "don't have")")
    }

    private var limitsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            question("Any limits or injuries?", "Tap the body to mark a spot — we'll swap exercises automatically and show you the swaps.")
            Text("This only changes your exercises — it isn't a diagnosis, and it doesn't mean an exercise is safe for you. Check with your doctor or physical therapist before training around an injury.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            optionCard(selected: profile.injuredParts.isEmpty && profile.otherLimitText.isEmpty) {
                profile.injuredParts = []
                profile.otherLimitText = ""
            } label: {
                Text("None").font(.headline)
            }
            BodyDiagramView(selected: $state.profile.injuredParts)
            TextField("Something else? Tell us briefly (stays on this phone)", text: $state.profile.otherLimitText)
                .textFieldStyle(.roundedBorder)
                .withKeyboardDoneToolbar(system: true)
            ForEach(Array(profile.limits).sorted { $0.label < $1.label }, id: \.self) { limit in
                if !limit.hint.isEmpty {
                    Text("\(limit.label): \(limit.hint)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private var bodyweightStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            question("Your bodyweight? (optional)", "A baseline for tracking only. Never required, never leaves this phone.")
            HStack(spacing: 8) {
                TextField("Enter your weight", text: $state.weightText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .withKeyboardDoneToolbar(system: true)
                Picker("Unit", selection: $state.isKg) {
                    Text("lb").tag(false)
                    Text("kg").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            Text("Tap Continue to skip this — you can add it later in Profile.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// Invite step (Debug Pass 2): your code + share, and redeem a
    /// friend's code. Skippable with Continue — it lives in Profile
    /// too, so nobody is stuck here. The step itself is in
    /// InviteCode.swift (`InviteQuizStep`); this is only the hook.
    private var inviteStep: some View {
        InviteQuizStep()
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            question("Rest timer + trial reminders?", "We'll ping you when rest is over — and before a trial ends.")
            Button {
                // One request only: a second tap while the system prompt
                // is up used to complete the quiz twice.
                guard !isRequestingNotifications else { return }
                isRequestingNotifications = true
                Task {
                    let granted = await subscription.requestNotificationPermission()
                    profile.notificationsAllowed = granted
                    onComplete(profile)
                    isRequestingNotifications = false
                }
            } label: {
                Text("Allow notifications")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isRequestingNotifications)
            Text("Local notifications only, on this phone. No email, no account.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Option card

    private func optionCard<Content: View>(selected: Bool, action: @escaping () -> Void,
                                           @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) {
            HStack {
                label()
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
}
