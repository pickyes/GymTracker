import ActivityKit
import AppIntents
import Foundation

/// Interactive Live Activity intents (DaRon, 2026-11-09, 22:27):
/// "I want you to be able to go check set boxs and move to next
/// exercise from live activity."
///
/// From the lock screen, without opening the app:
///  - `ToggleSetIntent` — tap a set checkbox to mark that set done
///    (same as tapping the set circle in the app; it logs the set in the
///    real WorkoutStore draft and starts the rest timer).
///  - `NextExerciseIntent` — advance to the next exercise (updates the
///    current exercise, the set dots, and the body highlight).
///
/// SELF-CONTAINED BY DESIGN: this file is compiled into BOTH targets —
/// the app and the GymTrackerWidgetExtension — because the Live Activity
/// UI (in the extension) creates the buttons with `Button(intent:)`, so
/// the intent types must be visible there. It therefore does NOT import
/// Models.swift / WorkoutStore / AppIntents.swift. Instead it edits the
/// persisted draft (UserDefaults key "gymtracker.draft.v1", JSON-encoded
/// DraftSession) surgically with JSONSerialization: it flips ONE boolean
/// (`logs[exerciseId][setIndex].done`) and writes the JSON back, so every
/// other draft field (dayKey, date, finisherChecks, sessionMod, notes,
/// the templates' other fields) is preserved byte-for-byte in value.
/// Rest state is the same scalar UserDefaults keys the store uses.
/// After any mutation it posts the Darwin notification
/// `com.daronbarkley.GymTracker.draftChanged` so the running app pulls
/// the change in (WorkoutStore.reconcileFromDefaults), and it updates
/// the running Live Activity directly so the lock screen reflects the
/// tap right away.
enum LiveActivityDraftKeys {
    static let draft = "gymtracker.draft.v1"
    static let restEndsAt = "gymtracker.restEndsAt.v1"
    static let restPaused = "gymtracker.restPaused.v1"
    static let restTemplateID = "gymtracker.restTemplateID.v1"
    static let liveActivitySelectedExercise = "gymtracker.liveActivitySelectedExercise.v1"
    /// Default rest when an exercise has no per-exercise override — must
    /// match WorkoutStore.settings.restSecondsDefault.
    static let defaultRestSeconds: TimeInterval = 90
    static let draftChangedNotification = "com.daronbarkley.GymTracker.draftChanged"
}

/// Post a Darwin (CFNotificationCenter) notification — the cross-process
/// channel between a Live Activity intent and the running app. Unlike
/// UserDefaults observation, this fires even when the app is suspended.
enum DarwinNotify {
    static func post(name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true)
    }
}

/// Surgical read/write access to the persisted draft JSON. All reads are
/// defensive: a missing draft, exercise, or set index returns nil / an
/// empty list instead of crashing, and the intent then reports a graceful
/// "not found" result without writing anything.
enum LiveActivityDraftJSON {

    struct TemplateInfo {
        var id: String
        var name: String
        var restSeconds: TimeInterval?
        var sets: Int
    }

    /// The draft as a mutable JSON tree (nil when there is no draft).
    static func loadMutable() -> NSMutableDictionary? {
        guard let data = SharedDefaults.store.data(forKey: LiveActivityDraftKeys.draft),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.mutableContainers]),
              let dict = obj as? NSMutableDictionary else { return nil }
        return dict
    }

    /// Write the (mutated) draft JSON back to the same key.
    static func save(_ dict: NSDictionary) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        SharedDefaults.store.set(data, forKey: LiveActivityDraftKeys.draft)
    }

    /// Ordered templates from the draft (id, name, restSeconds, sets).
    /// JSON keys are DraftSession/ExerciseTemplate's Codable property
    /// names (no custom CodingKeys), so "id" / "name" / "restSeconds" /
    /// "sets" are the wire names.
    static func templates(in dict: NSDictionary) -> [TemplateInfo] {
        guard let raw = dict["templates"] as? [NSDictionary] else { return [] }
        return raw.compactMap { t in
            guard let id = t["id"] as? String,
                  let name = t["name"] as? String else { return nil }
            let rest = (t["restSeconds"] as? NSNumber)?.doubleValue
            let sets = (t["sets"] as? NSNumber)?.intValue ?? 0
            return TemplateInfo(id: id, name: name, restSeconds: rest, sets: sets)
        }
    }

    /// Done flags for one exercise's sets, in order (empty when the
    /// exercise has no logged sets yet).
    static func doneFlags(for exerciseId: String, in dict: NSDictionary) -> [Bool] {
        guard let logs = dict["logs"] as? NSDictionary,
              let sets = logs[exerciseId] as? [NSDictionary] else { return [] }
        return sets.map { ($0["done"] as? NSNumber)?.boolValue ?? false }
    }

    /// The template after `exerciseId` in today's plan, or nil when this
    /// is the last exercise.
    static func nextTemplate(after exerciseId: String, in dict: NSDictionary) -> TemplateInfo? {
        let templates = templates(in: dict)
        guard let i = templates.firstIndex(where: { $0.id == exerciseId }),
              templates.indices.contains(i + 1) else { return nil }
        return templates[i + 1]
    }

    /// Per-exercise rest override for `exerciseId` (nil = use the global
    /// default). Reads the draft's templates array.
    static func restSeconds(for exerciseId: String, in dict: NSDictionary) -> TimeInterval? {
        templates(in: dict).first(where: { $0.id == exerciseId })?.restSeconds
    }

    /// Flip one set's done flag in the persisted draft. Returns the new
    /// done value and the set's kind ("warmup" / "working" / "drop" /
    /// "failure" — SetKind's raw values), or nil when the draft,
    /// exercise, or set index is missing. Nothing is written on failure.
    static func toggleSet(exerciseId: String, setIndex: Int) -> (done: Bool, kind: String)? {
        guard let dict = loadMutable(),
              let logs = dict["logs"] as? NSMutableDictionary,
              let sets = logs[exerciseId] as? NSMutableArray,
              // NSMutableArray has no `.indices` — bounds-check by count.
              setIndex >= 0 && setIndex < sets.count,
              let set = sets[setIndex] as? NSMutableDictionary else { return nil }
        let nowDone = !((set["done"] as? NSNumber)?.boolValue ?? false)
        set["done"] = nowDone
        let kind = (set["kind"] as? String) ?? "working"
        save(dict)
        return (nowDone, kind)
    }
}

/// Builds the Live Activity's ContentState from the persisted draft +
/// rest keys, preserving the running activity's accent. Used by the
/// intents to refresh the lock screen right after a tap.
enum LiveActivityStateBuilder {

    /// ContentState for `exerciseId`, or nil when there is no draft or
    /// the exercise is not in today's plan. Timing (endsAt / remaining /
    /// total / paused) comes from the rest keys and the exercise's own
    /// rest override — the countdown itself is never restarted here; the
    /// rest keeps whatever end time it already had.
    static func state(for exerciseId: String, accentHex: String) -> RestTimerAttributes.ContentState? {
        guard let dict = LiveActivityDraftJSON.loadMutable() else { return nil }
        let templates = LiveActivityDraftJSON.templates(in: dict)
        guard let template = templates.first(where: { $0.id == exerciseId }) else { return nil }
        let nextName: String? = {
            guard let i = templates.firstIndex(where: { $0.id == exerciseId }),
                  templates.indices.contains(i + 1) else { return nil }
            return templates[i + 1].name
        }()
        let total = template.restSeconds ?? LiveActivityDraftKeys.defaultRestSeconds
        let paused = SharedDefaults.store.double(forKey: LiveActivityDraftKeys.restPaused)
        let isPaused = paused > 0
        let endsRaw = SharedDefaults.store.double(forKey: LiveActivityDraftKeys.restEndsAt)
        let endsAt: Date? = (!isPaused && endsRaw > 0) ? Date(timeIntervalSince1970: endsRaw) : nil
        let remaining: TimeInterval = {
            if isPaused { return paused }
            if let endsAt { return max(endsAt.timeIntervalSinceNow, 0) }
            return total
        }()
        return RestTimerAttributes.ContentState(
            exerciseName: template.name,
            endsAt: endsAt,
            remainingSeconds: remaining,
            totalSeconds: max(total, 1),
            isPaused: isPaused,
            accentHex: accentHex,
            exerciseId: template.id,
            sets: LiveActivityDraftJSON.doneFlags(for: exerciseId, in: dict),
            nextExerciseName: nextName)
    }

    /// Refresh the running Live Activity to show `exerciseId` (its name,
    /// set checkboxes, and next-exercise name), keeping the countdown
    /// and accent exactly as they are. No-op when no activity is running.
    static func updateActivity(for exerciseId: String) async {
        guard let activity = Activity<RestTimerAttributes>.activities.first else { return }
        let accentHex = activity.contentState.accentHex
        guard let state = state(for: exerciseId, accentHex: accentHex) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }
}

/// Tap a set checkbox in the Live Activity to mark that set done (or
/// undo it). Runs without opening the app (`openAppWhenRun = false`).
struct ToggleSetIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Set Done"
    static var description = IntentDescription("Marks a set done (or undone) from the lock screen rest timer.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Exercise ID")
    var exerciseId: String

    @Parameter(title: "Set Index")
    var setIndex: Int

    init() {
        self.exerciseId = ""
        self.setIndex = 0
    }

    init(exerciseId: String, setIndex: Int) {
        self.exerciseId = exerciseId
        self.setIndex = setIndex
    }

    func perform() async throws -> some IntentResult {
        guard let toggled = LiveActivityDraftJSON.toggleSet(exerciseId: exerciseId, setIndex: setIndex) else {
            return .result(value: "Set not found.", dialog: "That set isn't in today's workout.")
        }
        // Marking a working set done starts (restarts) the rest timer —
        // exactly like tapping the set circle in the app
        // (WorkoutStore.toggleSetDone -> startRest). A warm-up set never
        // starts a rest, and un-checking a set leaves the running rest
        // alone.
        if toggled.done, toggled.kind != "warmup" {
            let restSeconds: TimeInterval = {
                guard let dict = LiveActivityDraftJSON.loadMutable() else { return LiveActivityDraftKeys.defaultRestSeconds }
                return LiveActivityDraftJSON.restSeconds(for: exerciseId, in: dict)
                    ?? LiveActivityDraftKeys.defaultRestSeconds
            }()
            SharedDefaults.store.set(exerciseId, forKey: LiveActivityDraftKeys.restTemplateID)
            SharedDefaults.store.removeObject(forKey: LiveActivityDraftKeys.restPaused)
            SharedDefaults.store.set(
                Date().addingTimeInterval(restSeconds).timeIntervalSince1970,
                forKey: LiveActivityDraftKeys.restEndsAt)
        }
        // Tell the running app to pull the change in.
        DarwinNotify.post(name: LiveActivityDraftKeys.draftChangedNotification)
        // Flip the checkbox on the lock screen right away.
        await LiveActivityStateBuilder.updateActivity(for: exerciseId)
        return .result(value: toggled.done ? "Set done." : "Set undone.",
                       dialog: toggled.done ? "Set done." : "Set undone.")
    }
}

/// Move to the next exercise from the Live Activity. Runs without
/// opening the app. The rest timer keeps counting down untouched — only
/// the current exercise advances (the app picks it up via the Darwin
/// notification + the persisted selection key, and the activity refreshes
/// to the next exercise's name and set checkboxes).
struct NextExerciseIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Exercise"
    static var description = IntentDescription("Moves the workout to the next exercise from the lock screen rest timer.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Exercise ID")
    var exerciseId: String

    init() {
        self.exerciseId = ""
    }

    init(exerciseId: String) {
        self.exerciseId = exerciseId
    }

    func perform() async throws -> some IntentResult {
        guard let dict = LiveActivityDraftJSON.loadMutable(),
              let next = LiveActivityDraftJSON.nextTemplate(after: exerciseId, in: dict) else {
            return .result(value: "No next exercise.", dialog: "That's the last exercise.")
        }
        // Persist the selection so the running app advances its current
        // exercise (and body highlight) when it reconciles.
        SharedDefaults.store.set(next.id, forKey: LiveActivityDraftKeys.liveActivitySelectedExercise)
        DarwinNotify.post(name: LiveActivityDraftKeys.draftChangedNotification)
        // Refresh the lock screen to the next exercise's sets + name.
        await LiveActivityStateBuilder.updateActivity(for: next.id)
        return .result(value: "Next: \(next.name).", dialog: "Next: \(next.name).")
    }
}
