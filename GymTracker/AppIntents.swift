import AppIntents
import Foundation

// MARK: - App Intents (MCP P0, Layer 1)
//
// App Intents expose the app's verbs to Siri, Shortcuts, Spotlight, widgets,
// the Action Button, and Apple Intelligence. They are a system bridge, NOT an
// agent bridge — an outside agent cannot enumerate or invoke them directly.
// They matter because (1) they power Siri / Action Button / widgets for the
// 3M everyday users, and (2) they enable the Shortcuts bridge: an agent that
// can open shortcuts://run-shortcut can trigger one and get JSON back.
// The real agent bridge is the phone MCP server (MCPServer.swift) + the Mac
// companion (mac-companion/gym_tracker_mcp.py).
//
// Intents run in a separate process, so they cannot use the app's
// WorkoutStore (@StateObject). They read/write the same UserDefaults keys
// directly — one source of truth, shared with the UI.

enum GymTrackerIntentData {
    static let sessionsKey = "gymtracker.sessions.v1"
    static let weightKey = "gymtracker.bodyweight.v1"
    static let draftKey = "gymtracker.draft.v1"
    static let profileKey = "gymtracker.profile.v1"
    static let programKey = "gymtracker.program.v1"
    static let generatedKey = "gymtracker.generated.v1"
    static let restEndsAtKey = "gymtracker.restEndsAt.v1"
    static let customExercisesKey = "gymtracker.customExercises.v1"

    static var sessions: [SessionLog] {
        guard let data = SharedDefaults.store.data(forKey: sessionsKey),
              let decoded = try? JSONDecoder().decode([SessionLog].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.date > $1.date }
    }

    static var activeProgram: UserProgram? {
        guard let data = SharedDefaults.store.data(forKey: programKey),
              let decoded = try? JSONDecoder().decode(UserProgram.self, from: data) else {
            return nil
        }
        return decoded
    }

    static var profile: UserProfile? {
        guard let data = SharedDefaults.store.data(forKey: profileKey),
              let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return nil
        }
        return decoded
    }

    /// Custom exercises, for the session label's muscle-family check —
    /// same key the store persists them under. Absent = none; a custom
    /// exercise the label can't map simply keeps the plan title.
    static var customExercises: [CustomExercise] {
        guard let data = SharedDefaults.store.data(forKey: customExercisesKey),
              let decoded = try? JSONDecoder().decode([CustomExercise].self, from: data) else {
            return []
        }
        return decoded
    }

    /// The workout in progress: today's draft, or last night's with sets
    /// logged (it ran past midnight) — the same rule as the app.
    static var draft: DraftSession? {
        guard let data = SharedDefaults.store.data(forKey: draftKey),
              let decoded = try? JSONDecoder().decode(DraftSession.self, from: data),
              WorkoutStore.isDraftLive(date: decoded.date,
                                       hasDoneSets: decoded.logs.values.contains { $0.contains(where: \.done) }) else {
            return nil
        }
        return decoded
    }

    /// Tell the running app the draft/sessions changed on disk.
    static func notifyApp() {
        DarwinNotify.post(name: LiveActivityDraftKeys.draftChangedNotification)
    }

    static func saveSessions(_ sessions: [SessionLog]) {
        if let data = try? JSONEncoder().encode(sessions) {
            SharedDefaults.store.set(data, forKey: sessionsKey)
        }
    }

    static func saveDraft(_ draft: DraftSession) {
        if let data = try? JSONEncoder().encode(draft) {
            SharedDefaults.store.set(data, forKey: draftKey)
        }
    }

    static func clearDraft() {
        SharedDefaults.store.removeObject(forKey: draftKey)
    }

    static func todayDayKey() -> String? {
        Program.dayKey(for: Date())
    }

    /// Today's plan with the user's marked injuries applied — the same
    /// adapted program Today reads (see `WorkoutStore.adaptedActiveProgram`).
    /// Intents run outside the store, so the adaptation runs here off the
    /// decoded profile; equipment is the profile's have-set (the
    /// store's active Gym Profile isn't visible to intents).
    static func todayPlan() -> DayPlan? {
        guard let key = todayDayKey() else { return nil }
        guard let program = activeProgram else { return nil }
        guard let profile else { return program.day(forKey: key) }
        let adapted = InjuryAdaptation.adapt(program: program, profile: profile,
                                             customExercises: customExercises,
                                             equipment: profile.equipmentHave)
        return adapted.day(forKey: key)
    }

    /// Ensure a draft exists for today's plan (creates one if needed).
    @discardableResult
    static func ensureDraft() -> DraftSession? {
        // A workout in progress is never replaced: today's draft for this
        // plan, any draft with sets logged (train-anyway, a swapped plan,
        // or last night's that ran past midnight).
        if let existing = draft {
            let hasDone = existing.logs.values.contains { $0.contains(where: \.done) }
            let isToday = Calendar.current.isDateInToday(existing.date)
            if hasDone || (isToday && existing.dayKey == todayPlan()?.key) {
                return existing
            }
        }
        guard let plan = todayPlan() else { return nil }
        var logs: [String: [SetLog]] = [:]
        for template in plan.exercises {
            let weight = lastWeight(for: template)
            logs[template.id] = (0..<template.sets).map { _ in
                SetLog(weightLb: weight ?? template.defaultWeightLb, reps: template.topReps, done: false)
            }
        }
        // sourcePlan set like the app's own drafts (saving and the
        // app's plan-change check read it).
        let fresh = DraftSession(dayKey: plan.key, date: Date(), logs: logs,
                                 finisherChecks: plan.finisher.map { _ in false },
                                 templates: plan.exercises, sourcePlan: plan)
        saveDraft(fresh)
        notifyApp()
        return fresh
    }

    /// Same rule as the app: the heaviest done working set last time.
    static func lastWeight(for template: ExerciseTemplate) -> Double? {
        sessions
            .sorted { $0.date > $1.date }
            .flatMap { $0.exercises }
            .first { $0.exerciseId == template.id }
            .flatMap(lastWorkingWeight(in:))
    }

    static func jsonString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

// MARK: - Intents

struct GetTodayWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today's Workout"
    static var description = IntentDescription("Shows today's workout plan, or that today is a rest day.")

    func perform() async throws -> some IntentResult {
        guard let plan = GymTrackerIntentData.todayPlan() else {
            return .result(value: "Rest day — no workout scheduled today.",
                           dialog: "Today is a rest day.")
        }
        let json = GymTrackerIntentData.jsonString(plan)
        return .result(value: json, dialog: "Today is \(plan.title). \(plan.exercises.count) exercises.")
    }
}

struct LogSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Set"
    static var description = IntentDescription("Marks a set done for an exercise, with weight and reps.")

    @Parameter(title: "Exercise", description: "The exercise name, or its id.")
    var exercise: String

    @Parameter(title: "Weight (lb)", description: "Weight in lb. Leave empty for bodyweight.")
    var weight: Double?

    @Parameter(title: "Reps")
    var reps: Int

    init() {
        self.exercise = ""
        self.weight = nil
        self.reps = 10
    }

    init(exercise: String, weight: Double?, reps: Int) {
        self.exercise = exercise
        self.weight = weight
        self.reps = reps
    }

    func perform() async throws -> some IntentResult {
        guard var draft = GymTrackerIntentData.ensureDraft() else {
            return .result(value: "No workout today (rest day).",
                           dialog: "There's no workout today — it's a rest day.")
        }
        // The draft's own exercises first (a swapped / train-anyway
        // workout), then its source plan.
        let plan = draft.sourcePlan ?? GymTrackerIntentData.todayPlan()
            ?? DayPlan(key: draft.dayKey, title: "", subtitle: "", exercises: draft.templates, finisher: [])
        // Match exact id first, then exact name, then name-contains (same order as MCPServer).
        let match = draft.templates.first { $0.id == exercise }
            ?? draft.templates.first { $0.name.localizedCaseInsensitiveCompare(exercise) == .orderedSame }
            ?? draft.templates.first { $0.name.localizedCaseInsensitiveContains(exercise) }
            ?? plan.exercises.first { $0.id == exercise }
            ?? plan.exercises.first { $0.name.localizedCaseInsensitiveCompare(exercise) == .orderedSame }
            ?? plan.exercises.first { $0.name.localizedCaseInsensitiveContains(exercise) }
        guard let template = match else {
            return .result(value: "Exercise '\(exercise)' is not in today's workout.",
                           dialog: "I couldn't find \(exercise) in today's workout.")
        }
        var sets = draft.logs[template.id] ?? []
        if let index = sets.firstIndex(where: { !$0.done }) {
            sets[index].done = true
            if let weight { sets[index].weightLb = weight }
            sets[index].reps = reps
            draft.logs[template.id] = sets
            GymTrackerIntentData.saveDraft(draft)
            GymTrackerIntentData.notifyApp()
            let doneCount = sets.filter { $0.done }.count
            return .result(
                value: "Logged set \(doneCount) of \(sets.count) for \(template.name): \(weight.map { "\($0) lb" } ?? "bodyweight") × \(reps).",
                dialog: "Logged. That's set \(doneCount) of \(sets.count) for \(template.name).")
        }
        return .result(value: "All sets for \(template.name) are already done.",
                       dialog: "All sets for \(template.name) are already done.")
    }
}

struct StartWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Today's Workout"
    static var description = IntentDescription("Begins today's workout (creates the in-progress draft).")

    func perform() async throws -> some IntentResult {
        guard let draft = GymTrackerIntentData.ensureDraft(),
              let plan = draft.sourcePlan ?? GymTrackerIntentData.todayPlan() else {
            return .result(value: "Rest day — no workout scheduled today.",
                           dialog: "Today is a rest day.")
        }
        return .result(value: "Started \(plan.title) — \(draft.templates.count) exercises.",
                       dialog: "Started today's workout: \(plan.title).")
    }
}

struct FinishWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Finish Workout"
    static var description = IntentDescription("Saves the in-progress workout as a completed session.")

    func perform() async throws -> some IntentResult {
        guard let draft = GymTrackerIntentData.draft,
              let plan = draft.sourcePlan ?? GymTrackerIntentData.todayPlan() else {
            return .result(value: "No workout in progress.",
                           dialog: "There's no workout in progress to finish.")
        }
        // Save the workout that was actually done: the draft's source
        // plan, not whatever plan is current now — the label comes from
        // the session itself (its date and the exercises actually
        // logged), never copied from a plan. See
        // WorkoutStore.sessionLabel.
        let sourcePlan = draft.sourcePlan ?? plan
        // Only done sets, as the app saves them.
        let exerciseLogs = WorkoutStore.sessionExercises(templates: draft.templates, logs: draft.logs)
        guard !exerciseLogs.isEmpty else {
            return .result(value: "No sets checked off yet — nothing to save.",
                           dialog: "You haven't logged any sets yet, so there's nothing to save.")
        }
        // Dated by the workout's own day (it may have run past midnight).
        let savedAt = Calendar.current.isDateInToday(draft.date) ? Date() : draft.date
        let label = WorkoutStore.sessionLabel(date: savedAt, plan: sourcePlan, exercises: exerciseLogs, customs: GymTrackerIntentData.customExercises)
        let session = SessionLog(
            id: UUID(), date: savedAt, dayKey: label.dayKey, dayTitle: label.dayTitle,
            exercises: exerciseLogs,
            finisherDone: draft.finisherChecks.allSatisfy { $0 },
            finisherNotes: sourcePlan.finisher.joined(separator: "; ")
        )
        var sessions = GymTrackerIntentData.sessions
        sessions.append(session)
        sessions.sort { $0.date > $1.date }
        GymTrackerIntentData.saveSessions(sessions)
        GymTrackerIntentData.clearDraft()
        ReminderScheduler.cancelMissedDayNudge()
        GymTrackerIntentData.notifyApp()
        let doneSets = exerciseLogs.flatMap { $0.sets }.filter { $0.done }.count
        return .result(value: "Finished \(label.dayTitle). \(setsDoneText(done: doneSets)).",
                       dialog: "Nice work. \(label.dayTitle) is saved — \(setsDoneText(done: doneSets)).")
    }
}

struct GetProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "How Am I Doing This Week?"
    static var description = IntentDescription("Summarizes this week's training: sessions, volume, best lifts.")

    func perform() async throws -> some IntentResult {
        let sessions = GymTrackerIntentData.sessions
        let weekStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        let thisWeek = sessions.filter { $0.date >= weekStart }
        let thisWeekExercises = thisWeek.flatMap { $0.exercises }
        let setsDone = thisWeekExercises.flatMap { $0.sets }.filter { $0.done }.count
        // The shared volume formula (done working sets only, per-hand
        // dumbbell loads doubled) — never recomputed inline.
        let volume = volumeLb(for: thisWeekExercises)
        let summary: [String: Any] = [
            "sessionsThisWeek": thisWeek.count,
            "setsDoneThisWeek": setsDone,
            "volumeLbThisWeek": volume,
            "totalSessions": sessions.count,
        ]
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return .result(value: json,
                       dialog: "This week: \(thisWeek.count) sessions, \(setsDoneText(done: setsDone)).")
    }
}

struct StartRestTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Rest Timer"
    static var description = IntentDescription("Starts the rest countdown (default 90 seconds).")

    @Parameter(title: "Seconds", description: "Rest length in seconds. Default 90.")
    var seconds: Double?

    init() { self.seconds = nil }
    init(seconds: Double?) { self.seconds = seconds }

    func perform() async throws -> some IntentResult {
        let duration = seconds ?? 90
        let endsAt = Date().addingTimeInterval(duration)
        SharedDefaults.store.set(endsAt.timeIntervalSince1970, forKey: GymTrackerIntentData.restEndsAtKey)
        return .result(value: "Rest timer started for \(Int(duration)) seconds.",
                       dialog: "Resting for \(Int(duration)) seconds.")
    }
}

// MARK: - App Shortcuts (Siri, Spotlight, Action Button, widgets)

struct GymTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: ["Start today's workout in \(.applicationName)",
                      "Start my workout in \(.applicationName)"],
            shortTitle: "Start Workout",
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: LogSetIntent(),
            phrases: ["Log my last set in \(.applicationName)",
                      "Log a set in \(.applicationName)"],
            shortTitle: "Log Set",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: GetProgressIntent(),
            phrases: ["How am I doing this week in \(.applicationName)",
                      "How's my training going in \(.applicationName)"],
            shortTitle: "Weekly Progress",
            systemImageName: "chart.bar"
        )
    }
}

// MARK: - JSON export (user-initiated only, share sheet)

/// The full export payload: sessions + program + profile. The user taps
/// "Export workouts (JSON)" in Profile and chooses where the file goes
/// (Files, AirDrop, cable). Never automatic — the user initiates it.
struct GymTrackerExport: Encodable {
    var exportedAt: Date
    var profile: UserProfile?
    var program: UserProgram?
    var sessions: [SessionLog]
    var bodyWeightLb: Double?

    static func current(store: WorkoutStore) -> GymTrackerExport {
        GymTrackerExport(
            exportedAt: Date(),
            profile: store.profile,
            program: store.activeProgram,
            sessions: store.sessions,
            bodyWeightLb: store.bodyWeightLb
        )
    }

    func jsonData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }
}
