import ActivityKit
import Combine
import Foundation
import SwiftUI
import UIKit

// MARK: - Log models (stored on-device in UserDefaults)

/// Set type (Hevy / JEFIT pattern). Warm-up sets don't trigger the rest
/// timer and don't count toward 1RM.
enum SetKind: String, Codable, CaseIterable, Equatable {
    case warmup
    case working
    case drop
    case failure

    var label: String {
        switch self {
        case .warmup: return "Warm-up"
        case .working: return "Working"
        case .drop: return "Drop"
        case .failure: return "Failure"
        }
    }

    var shortLabel: String {
        switch self {
        case .warmup: return "W"
        case .working: return ""
        case .drop: return "D"
        case .failure: return "F"
        }
    }
}

struct SetLog: Codable, Equatable {
    var weightLb: Double?
    var reps: Int
    var done: Bool
    var kind: SetKind

    init(weightLb: Double? = nil, reps: Int, done: Bool = false, kind: SetKind = .working) {
        self.weightLb = weightLb
        self.reps = reps
        self.done = done
        self.kind = kind
    }

    // Custom decoder: older saved sessions have no `kind` key — default to .working.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weightLb = try container.decodeIfPresent(Double.self, forKey: .weightLb)
        reps = try container.decode(Int.self, forKey: .reps)
        done = try container.decode(Bool.self, forKey: .done)
        kind = try container.decodeIfPresent(SetKind.self, forKey: .kind) ?? .working
    }

    private enum CodingKeys: String, CodingKey {
        case weightLb, reps, done, kind
    }
}

struct ExerciseLog: Codable, Equatable {
    var exerciseId: String
    var name: String
    var isPair: Bool
    var sets: [SetLog]
    /// The per-exercise unit override in effect when this was logged
    /// (nil = the global unit then). Saved so History and Calendar
    /// render the weight in the same unit Today showed — a kg override
    /// must not silently become lb after saving. Nil on older saves
    /// (decoded as absent), which fall back to the global unit.
    var unitOverride: WeightUnit? = nil
}

struct SessionLog: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var dayKey: String
    var dayTitle: String
    var exercises: [ExerciseLog]
    var finisherDone: Bool
    var finisherNotes: String
}

// MARK: - User notes (Notes page)

/// A note the user wrote: either a workout note (written in the
/// per-exercise note field on Today, saved with the workout — title is
/// the exercise, `workoutTitle` is the day it came from) or a free note
/// written on the Notes page (`workoutTitle` is nil). Stored on-device
/// only, like everything else. Sorted by most recently edited, so the
/// note just touched is always on top.
struct UserNote: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var workoutTitle: String?
    /// Pinned notes stay at the top of the list. (DaRon 22:42.)
    var isPinned: Bool = false
    /// The category this note is filed under, if any. Nil =
    /// Uncategorized. Categories are user-named strings kept in
    /// WorkoutStore.noteCategories. (DaRon 22:42.)
    var category: String? = nil

    /// Display title: the title as written, or the first line of the
    /// body when the title is blank (a note is never untitled on screen).
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = body.components(separatedBy: .newlines).first ?? ""
        let line = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? "New Note" : line
    }

    /// Preview line: the first line of the body (or the second line when
    /// the title came from the body).
    var previewLine: String {
        let lines = body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lines.dropFirst().first ?? ""
        }
        return lines.first ?? ""
    }
}

// MARK: - Draft session (in-progress workout, autosaved)

/// The workout in progress. Lives in WorkoutStore (app root) so it survives
/// fold/unfold, and is written to UserDefaults on every change so even a
/// process death mid-workout loses nothing.
struct DraftSession: Codable, Equatable {
    var dayKey: String
    var date: Date
    var logs: [String: [SetLog]]
    var finisherChecks: [Bool]
    /// The ordered exercise list for today (user-reordered / added / swapped).
    var templates: [ExerciseTemplate]
    /// One-off per-workout overrides (Session Mods) that don't touch the program.
    var sessionMod: SessionMod?
    /// Per-exercise session notes (today only).
    var notes: [String: String]
    /// When each per-exercise note was first typed (today only). The
    /// Notes page stamps the note with this time — the moment it was
    /// typed — not the moment the workout was saved. (DaRon 21:51.)
    var noteTimes: [String: Date]
    /// The plan this draft was built from. dayKey is only the weekday
    /// ("Mon"), so a same-day plan change (legs swapped to push, then
    /// back) used to keep the old exercise list under the new plan's
    /// title — the saved 17:39 "Legs" session held the morning's
    /// upper-body exercises. The draft now remembers its source plan;
    /// ensureDraft resets the draft when the plan's exercise set
    /// changes, and saving uses this plan's title/finisher.
    var sourcePlan: DayPlan?

    init(dayKey: String, date: Date, logs: [String: [SetLog]], finisherChecks: [Bool],
         templates: [ExerciseTemplate] = [], sessionMod: SessionMod? = nil, notes: [String: String] = [:],
         noteTimes: [String: Date] = [:], sourcePlan: DayPlan? = nil) {
        self.dayKey = dayKey
        self.date = date
        self.logs = logs
        self.finisherChecks = finisherChecks
        self.templates = templates
        self.sessionMod = sessionMod
        self.notes = notes
        self.noteTimes = noteTimes
        self.sourcePlan = sourcePlan
    }

    // Custom decoder: older drafts have no `templates` / `sessionMod` / `notes` / `noteTimes`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        date = try container.decode(Date.self, forKey: .date)
        logs = try container.decode([String: [SetLog]].self, forKey: .logs)
        finisherChecks = try container.decode([Bool].self, forKey: .finisherChecks)
        templates = try container.decodeIfPresent([ExerciseTemplate].self, forKey: .templates) ?? []
        sessionMod = try container.decodeIfPresent(SessionMod.self, forKey: .sessionMod)
        notes = try container.decodeIfPresent([String: String].self, forKey: .notes) ?? [:]
        noteTimes = try container.decodeIfPresent([String: Date].self, forKey: .noteTimes) ?? [:]
        sourcePlan = try container.decodeIfPresent(DayPlan.self, forKey: .sourcePlan)
    }

    private enum CodingKeys: String, CodingKey {
        case dayKey, date, logs, finisherChecks, templates, sessionMod, notes, noteTimes, sourcePlan
    }
}

/// One-off per-workout overrides (Fitbod "Training Session Mods" pattern).
/// Changes today only — never touches the saved program.
struct SessionMod: Codable, Equatable {
    var shorterSession: Bool = false
    var equipment: Set<Equipment>? = nil
    var focusMuscle: MuscleGroup? = nil
    /// Deload: half the sets, same exercises, for a recovery week.
    /// Use every 4–8 weeks when training feels heavy.
    var deload: Bool = false
}

// MARK: - Program templates

struct ExerciseTemplate: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var sets: Int
    var repRange: String
    var topReps: Int
    var defaultWeightLb: Double?
    var isPair: Bool
    var weightNote: String?
    var cues: String?
    /// Per-exercise rest override in seconds. Nil = use the global default.
    var restSeconds: TimeInterval?
    /// Per-exercise unit override. Nil = use the global unit.
    var unitOverride: WeightUnit?
    /// Routine note (shown every time this exercise appears).
    var note: String?
    /// True when this is a bodyweight exercise (no external load), copied
    /// from the library entry when the template is built. Stored so saved
    /// programs and drafts render "Bodyweight × reps" for nil weights;
    /// decoded as false when absent (pre-flag saves). See the custom
    /// decoder in the extension below.
    var isBodyweight: Bool = false

    /// Bottom of the rep range, parsed from repRange ("8–12" -> 8) — the
    /// rep count a set resets to after a progression bump. Computed, not
    /// stored, so it can never disagree with repRange.
    var bottomReps: Int { GymTracker.bottomReps(forRepRange: repRange, topReps: topReps) }
}

/// Custom decoder for ExerciseTemplate: `isBodyweight` arrived after
/// programs and drafts were already being saved, so older JSON has no key
/// for it. decodeIfPresent keeps those saves loading instead of failing
/// the whole program/draft decode. (A memberwise init is still synthesized
/// — this lives in an extension so it can't remove it.)
extension ExerciseTemplate {
    private enum CodingKeys: String, CodingKey {
        case id, name, sets, repRange, topReps, defaultWeightLb, isPair, weightNote, cues,
             restSeconds, unitOverride, note, isBodyweight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        sets = try container.decode(Int.self, forKey: .sets)
        repRange = try container.decode(String.self, forKey: .repRange)
        topReps = try container.decode(Int.self, forKey: .topReps)
        defaultWeightLb = try container.decodeIfPresent(Double.self, forKey: .defaultWeightLb)
        isPair = try container.decode(Bool.self, forKey: .isPair)
        weightNote = try container.decodeIfPresent(String.self, forKey: .weightNote)
        cues = try container.decodeIfPresent(String.self, forKey: .cues)
        restSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .restSeconds)
        unitOverride = try container.decodeIfPresent(WeightUnit.self, forKey: .unitOverride)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        isBodyweight = try container.decodeIfPresent(Bool.self, forKey: .isBodyweight) ?? false
    }
}

struct DayPlan: Identifiable, Codable, Equatable {
    var key: String
    var title: String
    var subtitle: String
    var exercises: [ExerciseTemplate]
    var finisher: [String]
    var id: String { key }

    /// Estimated session length in minutes, from the actual rest per
    /// exercise (template override, else the 90 s default) + ~45 s of
    /// lifting per set + 10 min warm-up/finisher (Gap 15: the old
    /// "2 min/set + 10" understated real time — an 18-set legs day at
    /// 150 s rests is ~65 min, not 46).
    var estimatedMinutes: Int {
        var seconds: Double = 10 * 60
        for exercise in exercises {
            let rest = exercise.restSeconds ?? AppSettings.default.restSecondsDefault
            seconds += Double(exercise.sets) * (rest + 45)
        }
        return max(15, Int((seconds / 60).rounded()))
    }
}

// MARK: - Weight units (lb/kg, global + per-exercise override)

enum WeightUnit: String, Codable, CaseIterable, Equatable {
    case lb
    case kg

    var label: String { rawValue }

    /// Convert a stored lb value to this unit for display. kg rounds to the
    /// nearest 0.5 kg (a loadable increment).
    func displayValue(for weightLb: Double?) -> Double? {
        guard let weightLb, weightLb > 0 else { return nil }
        switch self {
        case .lb: return weightLb
        case .kg: return (weightLb * 0.45359237 * 2).rounded() / 2
        }
    }

    /// Convert a displayed value back to stored lb.
    func storedValue(for display: Double?) -> Double? {
        guard let display, display > 0 else { return nil }
        switch self {
        case .lb: return display
        case .kg: return display / 0.45359237
        }
    }
}

// MARK: - Target areas (Leap "target-area rows" pattern)

/// What the user wants to focus on. Shown as pill rows in the goal step.
/// The generator uses them to shape the finisher; they change nothing about
/// sex or age (never asked).
/// A focus area for the finisher (Leap "target-area rows" pattern). The
/// options partition the body — no muscle appears in two options, and
/// together they cover every muscle group plus a Full Body choice. Each
/// option has a real subtitle describing what it covers (never a repeat
/// of the title). Multi-select: the finisher emphasizes every area picked.
/// `fullBody` carries no muscles — it means "no specific focus", so the
/// finisher falls back to the day's default slots.
enum TargetArea: String, Codable, CaseIterable, Hashable, Equatable {
    case chest
    case back
    case shoulders
    case arms
    case abs
    case glutes
    case legs
    case fullBody

    var label: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .abs: return "Abs & Core"
        case .glutes: return "Glutes"
        case .legs: return "Legs"
        case .fullBody: return "Full Body"
        }
    }

    /// What the option covers, in plain words.
    var subtitle: String {
        switch self {
        case .chest: return "Pecs, upper and lower"
        case .back: return "Lats, upper back, and neck"
        case .shoulders: return "Delts, front, side, and rear"
        case .arms: return "Biceps, triceps, forearms, and wrists"
        case .abs: return "Abs and obliques"
        case .glutes: return "Glutes and hips"
        case .legs: return "Quads, hamstrings, calves, feet, and ankles"
        case .fullBody: return "A little of everything, every session"
        }
    }

    var muscles: [MuscleGroup] {
        switch self {
        case .chest: return [.chest]
        case .back: return [.back, .neck]
        case .shoulders: return [.shoulders]
        case .arms: return [.biceps, .triceps, .forearms, .wrists]
        case .abs: return [.core, .obliques]
        case .glutes: return [.glutes]
        case .legs: return [.quads, .hamstrings, .calves, .feet, .ankles]
        case .fullBody: return []
        }
    }

    /// Map a stored raw value to the current areas. Handles the retired
    /// options: "armsAndBack" split into Arms + Back, "buttAndThigh"
    /// (glutes + hamstrings) split into Glutes + Legs. Unknown values
    /// are dropped rather than failing the whole profile decode.
    static func fromStored(_ raw: String) -> [TargetArea] {
        switch raw {
        case "armsAndBack": return [.arms, .back]
        case "buttAndThigh": return [.glutes, .legs]
        default:
            if let area = TargetArea(rawValue: raw) { return [area] }
            return []
        }
    }
}

// MARK: - User profile + generated program (onboarding, on-device only)

/// What the user is training for. Each goal visibly changes the generated
/// plan (rep ranges, split emphasis). No sex or age is asked — they change
/// nothing in the program.
enum Goal: String, Codable, CaseIterable, Equatable {
    case buildMuscle
    case getStronger
    case getLean
    case stayConsistent

    var label: String {
        switch self {
        case .buildMuscle: return "Build muscle"
        case .getStronger: return "Get stronger"
        case .getLean: return "Get lean"
        case .stayConsistent: return "Stay consistent"
        }
    }

    var detail: String {
        switch self {
        case .buildMuscle: return "8–12 reps, more volume"
        case .getStronger: return "4–6 reps on big lifts"
        case .getLean: return "6–12 reps + conditioning finisher"
        case .stayConsistent: return "3 days, full-body, shortest sessions"
        }
    }
}

enum ExperienceLevel: String, Codable, CaseIterable, Equatable {
    case new
    case some
    case experienced

    var label: String {
        switch self {
        case .new: return "New — never lifted"
        case .some: return "Some experience"
        case .experienced: return "Experienced"
        }
    }

    var detail: String {
        switch self {
        case .new: return "Bodyweight + machines first, light weights"
        case .some: return "Barbell compounds, moderate weights"
        case .experienced: return "Barbell compounds from day one, more volume"
        }
    }
}

enum EquipmentAccess: String, Codable, CaseIterable, Equatable {
    case fullGym
    case homeGym
    case dumbbellsOnly
    case bodyweightOnly

    var label: String {
        switch self {
        case .fullGym: return "Full gym"
        case .homeGym: return "Home gym — dumbbells + bench"
        case .dumbbellsOnly: return "Dumbbells only"
        case .bodyweightOnly: return "Bodyweight only"
        }
    }

    /// The equipment the generator may use for this access level.
    var equipment: Set<Equipment> {
        switch self {
        case .fullGym: return Set(Equipment.allCases)
        case .homeGym: return [.dumbbell, .bench, .bodyweight, .bands, .kettlebell]
        case .dumbbellsOnly: return [.dumbbell, .bench, .bodyweight]
        case .bodyweightOnly: return [.bodyweight]
        }
    }
}

/// A limit or injury. The generator swaps exercises automatically and shows
/// the swap to the user. Empty set = no limits. Injury-aware is a real
/// selling point (Leap's "Recovery Plans") — the app adapts, it doesn't
/// just warn.
enum Limit: String, Codable, CaseIterable, Equatable, Hashable {
    case shoulder
    case lowerBack
    case knee
    case neck
    case elbow
    case wrist
    case upperBack
    case hip
    case ankle
    case chest
    case core
    case other

    var label: String {
        switch self {
        case .shoulder: return "Shoulder"
        case .lowerBack: return "Lower back"
        case .knee: return "Knee"
        case .neck: return "Neck"
        case .elbow: return "Elbow"
        case .wrist: return "Wrist"
        case .upperBack: return "Upper back"
        case .hip: return "Hip"
        case .ankle: return "Ankle"
        case .chest: return "Chest"
        case .core: return "Core"
        case .other: return "Something else"
        }
    }

    /// Short hint shown in the quiz when this limit is marked — what gets
    /// swapped and what replaces it.
    var hint: String {
        switch self {
        case .shoulder: return "No overhead press or incline press — cable fly and face pulls instead."
        case .lowerBack: return "No deadlift or RDL — hip thrust and leg press instead."
        case .knee: return "No squat — leg press and split squat instead."
        case .neck: return "No overhead press — lateral raises instead."
        case .elbow: return "No heavy extensions or curls — pushdowns and hammer curls instead."
        case .wrist: return "No push-ups or planks on your hands — machine press and dead bugs instead."
        case .upperBack: return "No heavy rows or deadlifts — cable row and hip thrust instead."
        case .hip: return "No squats or lunges — leg press instead."
        case .ankle: return "No squats or calf raises — leg press instead."
        case .chest: return "No bench press or flys — lateral raises instead."
        case .core: return "No planks or crunches — glute bridges instead."
        case .other: return ""
        }
    }
}

/// One tappable region on the body diagram. Left/right are the person's
/// own sides. Each part maps to a Limit so the program generator can swap
/// exercises for it — the same mechanism as DaRon's shoulder swap,
/// generalized to every body part.
enum BodyPart: String, Codable, CaseIterable, Equatable, Hashable {
    case neck
    case shoulderLeft, shoulderRight
    case elbowLeft, elbowRight
    case wristLeft, wristRight
    case upperBack, lowerBack
    case hipLeft, hipRight
    case kneeLeft, kneeRight
    case ankleLeft, ankleRight
    case chest, core

    var label: String {
        switch self {
        case .neck: return "Neck"
        case .shoulderLeft: return "Left shoulder"
        case .shoulderRight: return "Right shoulder"
        case .elbowLeft: return "Left elbow"
        case .elbowRight: return "Right elbow"
        case .wristLeft: return "Left wrist"
        case .wristRight: return "Right wrist"
        case .upperBack: return "Upper back"
        case .lowerBack: return "Lower back"
        case .hipLeft: return "Left hip"
        case .hipRight: return "Right hip"
        case .kneeLeft: return "Left knee"
        case .kneeRight: return "Right knee"
        case .ankleLeft: return "Left ankle"
        case .ankleRight: return "Right ankle"
        case .chest: return "Chest"
        case .core: return "Core"
        }
    }

    /// Short label shown under the zone on the diagram.
    var shortLabel: String {
        switch self {
        case .neck: return "Neck"
        case .shoulderLeft: return "L shoulder"
        case .shoulderRight: return "R shoulder"
        case .elbowLeft: return "L elbow"
        case .elbowRight: return "R elbow"
        case .wristLeft: return "L wrist"
        case .wristRight: return "R wrist"
        case .upperBack: return "Upper back"
        case .lowerBack: return "Lower back"
        case .hipLeft: return "L hip"
        case .hipRight: return "R hip"
        case .kneeLeft: return "L knee"
        case .kneeRight: return "R knee"
        case .ankleLeft: return "L ankle"
        case .ankleRight: return "R ankle"
        case .chest: return "Chest"
        case .core: return "Core"
        }
    }

    /// The Limit this part feeds into the program generator.
    var limit: Limit {
        switch self {
        case .neck: return .neck
        case .shoulderLeft, .shoulderRight: return .shoulder
        case .elbowLeft, .elbowRight: return .elbow
        case .wristLeft, .wristRight: return .wrist
        case .upperBack: return .upperBack
        case .lowerBack: return .lowerBack
        case .hipLeft, .hipRight: return .hip
        case .kneeLeft, .kneeRight: return .knee
        case .ankleLeft, .ankleRight: return .ankle
        case .chest: return .chest
        case .core: return .core
        }
    }

    /// Which diagram view(s) this part appears on.
    var sides: [BodyDiagramSide] {
        switch self {
        case .chest, .core: return [.front]
        case .upperBack, .lowerBack: return [.back]
        default: return [.front, .back]
        }
    }
}

/// The user's answers. Stored on-device only (UserDefaults). No sex, no age,
/// no email, no account — nothing leaves the device.
/// Shared animation curves — fast, Apple-like, snappy. Every animated
/// transition in the app uses one of these (short durations, native
/// spring/easeOut). No slow, laggy, or floaty animations anywhere.
enum AppAnimation {
    /// The default: a quick spring for buttons, pills, cards, toggles.
    static let snappy = Animation.spring(response: 0.25, dampingFraction: 0.8)
    /// For fades and small opacity/scale changes.
    static let quick = Animation.easeOut(duration: 0.2)
    /// For page/step transitions (quiz, FAB menu, sheet content).
    static let page = Animation.spring(response: 0.3, dampingFraction: 0.85)
    /// Fold/unfold morph: a touch longer than snappy so the body and the
    /// current card have time to glide into their new panes instead of
    /// snapping. (DaRon 21:53: the app must take full use of the
    /// open/close animation.)
    static let fold = Animation.spring(response: 0.45, dampingFraction: 0.85)
}

struct UserProfile: Codable, Equatable {
    var goal: Goal = .buildMuscle
    var experience: ExperienceLevel = .some
    var daysPerWeek: Int = 3
    /// Equipment the user HAS (the have/don't-have checklist in setup).
    /// The generator only uses exercises whose equipment is a subset of
    /// this set. Bodyweight is always in the set — it can't be unmarked.
    var equipmentHave: Set<Equipment> = Set(Equipment.allCases)
    /// Body parts marked on the body diagram. The source of truth for
    /// injuries — `limits` is derived from this.
    var injuredParts: Set<BodyPart> = []
    var otherLimitText: String = ""
    var bodyweightLb: Double? = nil
    var bodyweightIsKg: Bool = false
    var notificationsAllowed: Bool = false
    var targetAreas: Set<TargetArea> = []
    /// The user's first name, for the cold-start greeting ("Hi DaRon").
    /// Nil when the quiz never asked for one (the quiz deliberately
    /// doesn't ask for a name) — DaRon's preset sets it.
    var name: String? = nil

    /// Limits the program generator swaps for, derived from the marked
    /// body parts (plus `.other` when free text is present).
    var limits: Set<Limit> {
        var set = Set(injuredParts.map { $0.limit })
        if !otherLimitText.trimmingCharacters(in: .whitespaces).isEmpty {
            set.insert(.other)
        }
        return set
    }

    /// Short summary of the equipment the user has, for subtitles.
    /// "Full gym" when everything is marked have, "Bodyweight only"
    /// when only bodyweight is, otherwise a count.
    var equipmentLabel: String {
        if equipmentHave == Set(Equipment.allCases) { return "Full gym" }
        if equipmentHave == [.bodyweight] { return "Bodyweight only" }
        return "\(equipmentHave.count) pieces of equipment"
    }

    static let starter = UserProfile(
        goal: .buildMuscle, experience: .some, daysPerWeek: 3,
        equipmentHave: Set(Equipment.allCases), injuredParts: [], otherLimitText: "",
        bodyweightLb: nil, bodyweightIsKg: false, notificationsAllowed: false, targetAreas: []
    )

    // Custom decoder: older profiles have no `targetAreas` key, and
    // pre-diagram profiles stored `limits` instead of `injuredParts`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goal = try container.decodeIfPresent(Goal.self, forKey: .goal) ?? .buildMuscle
        experience = try container.decodeIfPresent(ExperienceLevel.self, forKey: .experience) ?? .some
        daysPerWeek = try container.decodeIfPresent(Int.self, forKey: .daysPerWeek) ?? 3
        // Have-set. Missing (a profile saved before the checklist existed)
        // defaults to everything — the user can unmark items in the quiz
        // or in Profile.
        equipmentHave = (try container.decodeIfPresent(Set<Equipment>.self, forKey: .equipmentHave) ?? Set(Equipment.allCases)).union([.bodyweight])
        if let parts = try container.decodeIfPresent(Set<BodyPart>.self, forKey: .injuredParts) {
            injuredParts = parts
        } else {
            // Migrate a pre-diagram profile: each old limit becomes the
            // matching body part(s) (both sides for a paired part).
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let oldLimits = try legacy.decodeIfPresent(Set<Limit>.self, forKey: .limits) ?? []
            var parts: Set<BodyPart> = []
            for limit in oldLimits {
                switch limit {
                case .shoulder: parts.insert(.shoulderLeft); parts.insert(.shoulderRight)
                case .lowerBack: parts.insert(.lowerBack)
                case .knee: parts.insert(.kneeLeft); parts.insert(.kneeRight)
                case .neck: parts.insert(.neck)
                case .elbow: parts.insert(.elbowLeft); parts.insert(.elbowRight)
                case .wrist: parts.insert(.wristLeft); parts.insert(.wristRight)
                case .upperBack: parts.insert(.upperBack)
                case .hip: parts.insert(.hipLeft); parts.insert(.hipRight)
                case .ankle: parts.insert(.ankleLeft); parts.insert(.ankleRight)
                case .chest: parts.insert(.chest)
                case .core: parts.insert(.core)
                case .other: break
                }
            }
            injuredParts = parts
        }
        otherLimitText = try container.decodeIfPresent(String.self, forKey: .otherLimitText) ?? ""
        bodyweightLb = try container.decodeIfPresent(Double.self, forKey: .bodyweightLb)
        bodyweightIsKg = try container.decodeIfPresent(Bool.self, forKey: .bodyweightIsKg) ?? false
        notificationsAllowed = try container.decodeIfPresent(Bool.self, forKey: .notificationsAllowed) ?? false
        // Target areas decode through the legacy map: retired raw values
        // ("armsAndBack", "buttAndThigh") split into the current areas
        // instead of failing the whole profile.
        if let stored = try container.decodeIfPresent([String].self, forKey: .targetAreas) {
            targetAreas = Set(stored.flatMap { TargetArea.fromStored($0) })
        } else {
            targetAreas = []
        }
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }

    init(goal: Goal = .buildMuscle, experience: ExperienceLevel = .some, daysPerWeek: Int = 3,
         equipmentHave: Set<Equipment> = Set(Equipment.allCases), injuredParts: Set<BodyPart> = [], otherLimitText: String = "",
         bodyweightLb: Double? = nil, bodyweightIsKg: Bool = false,
         notificationsAllowed: Bool = false, targetAreas: Set<TargetArea> = [],
         name: String? = nil) {
        self.goal = goal
        self.experience = experience
        self.daysPerWeek = daysPerWeek
        self.equipmentHave = equipmentHave.union([.bodyweight])
        self.injuredParts = injuredParts
        self.otherLimitText = otherLimitText
        self.bodyweightLb = bodyweightLb
        self.bodyweightIsKg = bodyweightIsKg
        self.notificationsAllowed = notificationsAllowed
        self.targetAreas = targetAreas
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case goal, experience, daysPerWeek, equipmentHave, injuredParts, otherLimitText,
             bodyweightLb, bodyweightIsKg, notificationsAllowed, targetAreas, name
    }

    /// Legacy key used only to migrate pre-diagram profiles.
    private enum LegacyKeys: String, CodingKey {
        case limits
    }
}

/// One exercise swapped out because of a limit, shown to the user on the
/// plan reveal so they can see what their answer changed.
struct ProgramSwap: Codable, Equatable {
    var from: String
    var to: String
    var reason: String

    /// One-line plain-language explanation for program-level lists
    /// (plan reveal, Profile, program library detail): "Barbell Back
    /// Squat → Leg Press — swapped because of your knee injury".
    /// `reason` stays the bare limit label (the stored format) — the
    /// sentence is built at display time, so programs saved before
    /// this wording still read the same way. A swap with no
    /// replacement (`to` empty) reads as a removal, never as a
    /// silent drop.
    var displayText: String {
        let isLimit = Limit.allCases.contains { $0.label == reason }
        if to.isEmpty {
            if isLimit {
                return "\(from) was removed — no safe alternative for your \(reason.lowercased()) injury"
            }
            return "\(from) was removed (\(reason))"
        }
        if isLimit {
            return "\(from) → \(to) — swapped because of your \(reason.lowercased()) injury"
        }
        return "\(from) → \(to) (\(reason))"
    }

    /// The card-level one-liner ("Swapped because of your shoulder
    /// injury") — the card already shows the replacement's name, so
    /// the from → to part is left out here.
    var shortExplanation: String {
        let isLimit = Limit.allCases.contains { $0.label == reason }
        if to.isEmpty {
            if isLimit {
                return "Removed — no safe alternative for your \(reason.lowercased()) injury"
            }
            return "Removed (\(reason))"
        }
        if isLimit {
            return "Swapped because of your \(reason.lowercased()) injury"
        }
        return "Swapped (\(reason))"
    }
}

/// A program: a named set of training days. Either generated from a
/// UserProfile or a built-in preset (DaRon's 5-Day Split).
struct UserProgram: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var days: [DayPlan]
    var swaps: [ProgramSwap]
    var isPreset: Bool

    func day(forKey key: String) -> DayPlan? {
        days.first { $0.key == key }
    }
}

// MARK: - Injury adaptation (shared program/draft layer)
//
// The ONE place a marked injury changes a program. Every surface that
// shows a program — Today, the next-workout preview, the program
// library detail, rest-day train-anyway, the weekly targets — reads the
// ADAPTED program (see `WorkoutStore.adaptedActiveProgram`), never the
// stored one, so a marked injury can never leak an exercise that loads
// the injured area into a workout. The stored program is never mutated:
// removing the injury mark restores the original exercises, because the
// adaptation is recomputed from the current marks every time it is read.
//
// Rules come from the single source the generator already uses —
// `LimitRules` in ExerciseLibrary.swift (excluded ids + substitutes)
// and `LibraryExercise.muscle` (the exercise→muscle mapping). No second
// mapping lives here: if `LimitRules` is wrong for an exercise, that is
// a data fix in ExerciseLibrary.swift, not a patch here. What this layer
// DOES add, on top of the generator's own swap path, is (1) validation
// of every substitute against ALL marked limits and the user's
// equipment, (2) adaptation of programs the generator never built —
// DaRon's preset and catalog programs — and (3) finisher strings,
// which are plain text, not templates.
//
// This is injury guidance, not medical advice: nothing here diagnoses
// anyone or clears anyone to train. That call belongs to the user's
// doctor or physical therapist, and the copy on the injuries step says
// so plainly.
enum InjuryAdaptation {

    /// The first marked limit that excludes this exercise, if any.
    /// Deterministic order (by label) so two limits excluding the same
    /// exercise always name the same one in the swap line.
    static func excludedLimit(for lib: LibraryExercise, limits: Set<Limit>) -> Limit? {
        limits.sorted { $0.label < $1.label }
            .first { LimitRules.excludedExerciseIds(for: $0).contains(lib.id) }
    }

    /// True when this exercise id is excluded by any marked limit.
    static func isExcluded(_ id: String, limits: Set<Limit>) -> Bool {
        limits.contains { LimitRules.excludedExerciseIds(for: $0).contains(id) }
    }

    /// A safe replacement for an excluded exercise: the limit's own
    /// substitute first, then the exercise's own substitutes. Every
    /// candidate must exist in the library, use only equipment the
    /// user has, NOT be excluded by ANY marked limit (a substitute
    /// that loads another injured area is no substitute), and not
    /// already be in the day. Stretches are never workout
    /// replacements. There is deliberately no same-muscle fallback
    /// here: the muscle mapping cannot tell a safe quad exercise
    /// (leg press) from a loading one (goblet squat), so when no
    /// curated substitute validates, the exercise is dropped and the
    /// drop is shown — never papered over with a guess.
    static func safeReplacement(for lib: LibraryExercise, limits: Set<Limit>,
                                available: Set<Equipment>,
                                lookup: [String: LibraryExercise],
                                usedIds: Set<String>) -> LibraryExercise? {
        var candidates: [String] = []
        for limit in limits.sorted(by: { $0.label < $1.label }) {
            if let sub = LimitRules.substitute(for: lib.id, limit: limit) {
                candidates.append(sub)
            }
        }
        candidates.append(contentsOf: lib.substitutes)
        for id in candidates {
            guard let sub = lookup[id],
                  isValidReplacement(sub, limits: limits, available: available, usedIds: usedIds) else { continue }
            return sub
        }
        return nil
    }

    private static func isValidReplacement(_ lib: LibraryExercise, limits: Set<Limit>,
                                           available: Set<Equipment>, usedIds: Set<String>) -> Bool {
        !lib.id.hasPrefix("stretch-")
        && !usedIds.contains(lib.id)
        && lib.equipment.isSubset(of: available)
        && excludedLimit(for: lib, limits: limits) == nil
    }

    /// Match a finisher string ("Leg extension 2 × 15, light") to its
    /// library exercise by name prefix — the longest matching name
    /// wins, so "Seated Leg Curl" beats "Leg Curl". Nil when no
    /// exercise name matches (drop sets, superset descriptions, and
    /// other free text are left alone).
    static func exercise(forFinisherItem item: String, pool: [LibraryExercise]) -> LibraryExercise? {
        let lower = item.lowercased()
        var best: LibraryExercise?
        for lib in pool {
            let name = lib.name.lowercased()
            guard lower.hasPrefix(name) else { continue }
            if best == nil || name.count > best!.name.count { best = lib }
        }
        return best
    }

    /// The program with the profile's marked injuries applied. With no
    /// injuries marked the program is returned unchanged — same id,
    /// same days, same swaps — so the preset is never rewritten by a
    /// no-injury read. With injuries marked, every exercise that loads
    /// an injured area is swapped for a validated safe alternative or
    /// dropped (recorded as a removal swap), the finisher strings get
    /// the same treatment, and the day keeps its shape — the program
    /// adapts, it never deletes days. Previously recorded swaps are
    /// kept; new ones are appended once (deduped by from → to).
    static func adapt(program: UserProgram, profile: UserProfile,
                      customExercises: [CustomExercise], equipment: Set<Equipment>) -> UserProgram {
        let limits = profile.limits
        guard !limits.isEmpty else { return program }
        // One pass over the library: every lookup below is a dictionary
        // hit, not a linear scan (`ExerciseLibrary.byId` scans all
        // 1,635 entries) — `adapt` runs on every program read (Today,
        // preview, each card's swap note), so it has to stay near 1 ms.
        // Built-ins win over customs on an id collision, matching
        // `ExerciseLibrary.byId`.
        var lookup: [String: LibraryExercise] = [:]
        for custom in customExercises { lookup[custom.id] = LibraryExercise(from: custom) }
        for lib in ExerciseLibrary.all { lookup[lib.id] = lib }
        let pool = ExerciseLibrary.all(plus: customExercises)
        var adapted = program
        var newSwaps = program.swaps
        var seenSwapKeys = Set(newSwaps.map { "\($0.from)→\($0.to)" })
        adapted.days = program.days.map { day in
            var seen: Set<String> = []
            var exercises: [ExerciseTemplate] = []
            for template in day.exercises {
                guard let lib = lookup[template.id] else {
                    // Unknown id (a preset superset, a custom template
                    // the library doesn't know): keep it — there is no
                    // mapping to judge it by.
                    if !seen.contains(template.id) {
                        seen.insert(template.id)
                        exercises.append(template)
                    }
                    continue
                }
                if let bad = excludedLimit(for: lib, limits: limits) {
                    if let sub = safeReplacement(for: lib, limits: limits, available: equipment,
                                                 lookup: lookup, usedIds: seen) {
                        seen.insert(sub.id)
                        exercises.append(ProgramGenerator.template(for: sub, profile: profile))
                        recordSwap(from: template.name, to: sub.name, reason: bad.label,
                                   into: &newSwaps, seenKeys: &seenSwapKeys)
                    } else {
                        recordSwap(from: template.name, to: "", reason: bad.label,
                                   into: &newSwaps, seenKeys: &seenSwapKeys)
                    }
                    continue
                }
                if !seen.contains(template.id) {
                    seen.insert(template.id)
                    exercises.append(template)
                }
            }
            // Finishers are plain strings: match the exercise name,
            // swap it the same way (the sets/reps suffix is kept), or
            // drop the item when no safe swap exists. A finisher may
            // repeat a main exercise, so it is not deduped against them.
            var finisher: [String] = []
            for item in day.finisher {
                guard let lib = exercise(forFinisherItem: item, pool: pool),
                      let bad = excludedLimit(for: lib, limits: limits) else {
                    finisher.append(item)
                    continue
                }
                if let sub = safeReplacement(for: lib, limits: limits, available: equipment,
                                             lookup: lookup, usedIds: []) {
                    let suffix = item.dropFirst(lib.name.count)
                    finisher.append("\(sub.name)\(suffix)")
                    recordSwap(from: lib.name, to: sub.name, reason: bad.label,
                               into: &newSwaps, seenKeys: &seenSwapKeys)
                } else {
                    recordSwap(from: lib.name, to: "", reason: bad.label,
                               into: &newSwaps, seenKeys: &seenSwapKeys)
                }
            }
            return DayPlan(key: day.key, title: day.title, subtitle: day.subtitle,
                           exercises: exercises, finisher: finisher)
        }
        adapted.swaps = newSwaps
        return adapted
    }

    private static func recordSwap(from: String, to: String, reason: String,
                                   into swaps: inout [ProgramSwap], seenKeys: inout Set<String>) {
        let key = "\(from)→\(to)"
        guard !seenKeys.contains(key) else { return }
        seenKeys.insert(key)
        swaps.append(ProgramSwap(from: from, to: to, reason: reason))
    }

    /// Muscle groups whose stretches are hidden while any of these
    /// limits is marked — the union of each limit's stretch muscles.
    static func stretchMuscles(for limits: Set<Limit>) -> Set<MuscleGroup> {
        limits.reduce(into: Set<MuscleGroup>()) { $0.formUnion($1.stretchMuscles) }
    }
}

extension Limit {
    /// Muscle groups whose stretches move or load this area — a stretch
    /// for one of these groups is never suggested while this limit is
    /// marked. Read off the single-source exercise→muscle mapping
    /// (`LibraryExercise.muscle`): the stretch entries carry the muscle
    /// they stretch, so the rest-day filter excludes them by muscle. A
    /// stretch loads the area when its muscle crosses the joint: a quad
    /// stretch bends the knee under load, a hamstring stretch
    /// straightens it, a cobra extends the lower back, a biceps or
    /// triceps stretch moves the elbow.
    var stretchMuscles: Set<MuscleGroup> {
        switch self {
        case .shoulder: return [.shoulders]
        case .lowerBack: return [.core]
        case .knee: return [.quads, .hamstrings]
        case .neck: return [.neck]
        case .elbow: return [.biceps, .triceps]
        case .wrist: return [.wrists, .forearms]
        case .upperBack: return [.back]
        case .hip: return [.glutes]
        case .ankle: return [.calves, .ankles, .feet]
        case .chest: return [.chest]
        case .core: return [.core]
        case .other: return []
        }
    }
}

// MARK: - Custom exercises (user-created, on-device only)

/// A user-created exercise. Free tier caps the count (leaders cap it; the
/// exact cap is a pricing decision — 3 free here); Pro is unlimited.
struct CustomExercise: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var muscle: MuscleGroup
    var equipment: Set<Equipment>
    var type: CustomExerciseType
    var defaultSets: Int
    var repRange: String
    var topReps: Int
    var isPair: Bool
    var cues: String?
    var someWeightLb: Double?

    init(id: String = UUID().uuidString, name: String, muscle: MuscleGroup,
         equipment: Set<Equipment>, type: CustomExerciseType = .weightReps,
         defaultSets: Int = 3, repRange: String = "8–12", topReps: Int = 12,
         isPair: Bool = false, cues: String? = nil, someWeightLb: Double? = nil) {
        self.id = id
        self.name = name
        self.muscle = muscle
        self.equipment = equipment
        self.type = type
        self.defaultSets = defaultSets
        self.repRange = repRange
        self.topReps = topReps
        self.isPair = isPair
        self.cues = cues
        self.someWeightLb = someWeightLb
    }
}

enum CustomExerciseType: String, Codable, CaseIterable, Equatable {
    case weightReps
    case bodyweightReps
    case duration

    var label: String {
        switch self {
        case .weightReps: return "Weight + reps"
        case .bodyweightReps: return "Bodyweight + reps"
        case .duration: return "Duration"
        }
    }
}

// MARK: - Exercise preferences (Recommend More / Less / Exclude — Fitbod pattern)

enum ExercisePreference: String, Codable, CaseIterable, Equatable {
    case more
    case less
    case exclude
    case none

    var label: String {
        switch self {
        case .more: return "Recommend more"
        case .less: return "Recommend less"
        case .exclude: return "Exclude"
        case .none: return "No preference"
        }
    }
}

// MARK: - Gym Profiles (Fitbod pattern: one profile per location)

/// One location with its own equipment checklist. Home / gym / travel.
struct GymProfile: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var equipment: Set<Equipment>

    init(id: String = UUID().uuidString, name: String, equipment: Set<Equipment>) {
        self.id = id
        self.name = name
        self.equipment = equipment
    }
}

// MARK: - App settings (on-device only, UserDefaults)

enum ColorSchemeSetting: String, Codable, CaseIterable, Equatable {
    case auto
    case light
    case dark

    var label: String {
        switch self {
        case .auto: return "Auto (system)"
        case .light: return "Light"
        case .dark: return "Dark (OLED)"
        }
    }
}

enum AccentColorName: String, Codable, CaseIterable, Equatable {
    case blue
    case green
    case orange
    case red
    case purple
    case pink
    case teal
    case yellow

    var label: String { rawValue.capitalized }

    /// The SwiftUI color for this accent name — the ONE mapping from
    /// accent name to color. The app (GymTrackerApp) and the rest-timer
    /// Live Activity both resolve through here, so a name always means
    /// the same color everywhere. (Free users never pick a name — they
    /// get Theme.accent, the vivid blue.)
    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        case .pink: return .pink
        case .teal: return .teal
        case .yellow: return .yellow
        }
    }

    /// The accents the picker offers. Yellow and teal are NOT offered —
    /// contrast-checked (WCAG ratios, iOS system values, dark + light
    /// variants): yellow is effectively invisible on light surfaces in
    /// both modes (1.41–1.51:1 as text on white, 1.41–1.51:1 white text
    /// on a yellow fill), and dark-mode teal fails as a button fill
    /// with white text (1.72:1). Everything offered stays at or above
    /// 2.02:1 in every use (text on black, text on white, white text on
    /// the fill). The cases stay in the enum so a stored yellow/teal
    /// choice from before still decodes and renders — they just can't
    /// be newly picked.
    static let offeredCases: [AccentColorName] = [.blue, .green, .orange, .red, .purple, .pink]
}

struct AppSettings: Codable, Equatable {
    // Rest timer
    var restSecondsDefault: TimeInterval = 90
    var restSoundEnabled: Bool = true
    var restHapticEnabled: Bool = true
    /// Flashlight Morse "STATUS" when a rest ends. Off by default;
    /// turning it on asks for camera access (the torch needs it).
    /// Stored under gymtracker.settings.v1 like the other rest settings;
    /// a stored settings blob from before this field decodes with the
    /// default (false) — nobody's rest ever starts flashing unasked.
    var restFlashlightEnabled: Bool = false
    // Units
    var weightUnit: WeightUnit = .lb
    // Comfort
    var hapticsEnabled: Bool = true
    var keepScreenAwake: Bool = false
    // Appearance — theme is free for everyone; accent colors are Pro.
    // Default is OLED dark (DaRon, 2026-11-09).
    var colorScheme: ColorSchemeSetting = .auto
    var accentColor: AccentColorName = .blue
    // Reminders
    var reminderTimeHour: Int = 17
    var reminderTimeMinute: Int = 30
    var missedDayNudgeEnabled: Bool = true
    // Plate calculator (barbell only)
    var barWeightLb: Double = 45
    var plateInventoryLb: [Double] = [45, 35, 25, 10, 5, 2.5]
    // History stats the user chose to lead with
    var historyStat: HistoryStatChoice = .volume

    static let `default` = AppSettings()
}

enum HistoryStatChoice: String, Codable, CaseIterable, Equatable {
    case volume
    case bestWeight
    case oneRepMax
    case streak

    var label: String {
        switch self {
        case .volume: return "Volume"
        case .bestWeight: return "Best lift"
        case .oneRepMax: return "Max lift"
        case .streak: return "Streak"
        }
    }
}

// MARK: - 1RM (Epley formula, JEFIT pattern)

/// Bottom of a rep range ("8–12" -> 8, "20–40 sec" -> 20, "7–7–7" -> 7).
/// Falls back to topReps when the range doesn't parse. Shared by
/// LibraryExercise.bottomReps and ExerciseTemplate.bottomReps.
func bottomReps(forRepRange repRange: String, topReps: Int) -> Int {
    let first = repRange.components(separatedBy: CharacterSet(charactersIn: "–-"))
        .first?.trimmingCharacters(in: .whitespaces) ?? ""
    guard let bottom = Int(first), bottom > 0, bottom <= topReps else { return topReps }
    return bottom
}

/// Most reps a set may have and still feed a 1RM estimate. Prediction
/// equations are only valid to ~10 reps (Mayhew et al. 1995; Reynolds
/// et al. 2006) — a 12–15 rep set never produces a 1RM here, it is
/// ignored, not capped into one (Gap 7).
let oneRepMaxMaxReps = 10

/// The Epley formula itself. Raw: callers must go through
/// `validOneRepMax` / `bestValidOneRepMax` so the validity gate
/// (≤10 reps, compound lifts only) is never bypassed.
func estimatedOneRepMax(weightLb: Double, reps: Int) -> Double {
    guard weightLb > 0, reps > 0 else { return 0 }
    if reps == 1 { return weightLb }
    // Reps are already gated to ≤10 by validOneRepMax; the min() is a
    // belt-and-braces guard so a direct call can never inflate either.
    let cappedReps = min(reps, oneRepMaxMaxReps)
    return weightLb * (1 + Double(cappedReps) / 30.0)
}

/// Shared 1RM validity gate (Gap 7): a 1RM estimate exists only for a
/// compound lift from a set of 1–10 reps. Isolation lifts (curls,
/// pushdowns, raises, flyes) have no meaningful 1RM, and sets above
/// 10 reps are outside every prediction equation's valid range — both
/// return nil instead of a made-up number.
func validOneRepMax(weightLb: Double, reps: Int, isCompound: Bool) -> Double? {
    guard isCompound, weightLb > 0, reps > 0, reps <= oneRepMaxMaxReps else { return nil }
    return estimatedOneRepMax(weightLb: weightLb, reps: reps)
}

/// Best valid Epley 1RM among done working sets (compound lifts only).
/// The ONE place that picks which set a 1RM comes from: the heaviest
/// set is not automatically the best — a 100 lb × 15 set is ignored
/// and a 90 lb × 8 set wins (Gap 7).
func bestValidOneRepMax(in sets: [SetLog], isCompound: Bool) -> Double? {
    guard isCompound else { return nil }
    var best: Double = 0
    for set in sets where set.done && set.kind != .warmup {
        guard let weight = set.weightLb else { continue }
        if let oneRM = validOneRepMax(weightLb: weight, reps: set.reps, isCompound: true),
           oneRM > best {
            best = oneRM
        }
    }
    return best > 0 ? best : nil
}

/// Start of the calendar week containing `date` — the ONE week
/// boundary for every weekly number (volume, targets, streak, best
/// lift). Previously each view recomputed it inline; identical text,
/// but a second definition waiting to drift.
func weekStartDate(for date: Date) -> Date {
    Calendar.current.date(
        from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    ) ?? date
}

/// Total load moved by one done working set. Per-hand dumbbell loads
/// are doubled: a pair of 40s × 10 moves 800 lb, the same as a
/// 80 lb barbell × 10 — counting the per-hand 400 would make DB
/// volume look half a barbell's for the same work.
func setVolumeLb(_ set: SetLog, isPair: Bool) -> Double {
    guard set.done, set.kind != .warmup else { return 0 }
    return (set.weightLb ?? 0) * (isPair ? 2 : 1) * Double(set.reps)
}

/// Total volume (weight × reps, done working sets only) for logged
/// exercises — the ONE volume formula for the store, History rows,
/// and the graph. Bodyweight sets (nil weight) contribute 0: their
/// load is the user's bodyweight, which is not known at log time,
/// so no number is invented for them.
func volumeLb(for exercises: [ExerciseLog]) -> Double {
    var total: Double = 0
    for exercise in exercises {
        for set in exercise.sets {
            total += setVolumeLb(set, isPair: exercise.isPair)
        }
    }
    return total
}

/// The ONE volume formatter ("12.5k lb" / "850 lb"), shared by the
/// weekly stat and every session row so the same volume never renders
/// two different ways.
func formattedVolumeLb(_ volume: Double) -> String {
    if volume >= 1000 {
        return String(format: "%.1fk lb", volume / 1000)
    }
    return "\(Int(volume)) lb"
}

/// Round a display weight to 1 decimal, trimming ".0" ("39.7", "40").
/// D32 (2026-11-10): kg→lb conversions (39.6832 lb etc.) printed
/// verbatim via "%g" — every user-visible weight formatter routes
/// through here so the decimals can never resurface elsewhere.
func roundedWeightText(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    return String(format: "%g", rounded)
}

/// "1 set done" / "3 sets done"; fraction form "1 of 3 sets done".
/// D5 (2026-11-10): History, intents, MCP and export all said
/// "1 sets done" — one shared helper, used everywhere.
func setsDoneText(done: Int, total: Int? = nil) -> String {
    if let total { return "\(done) of \(total) set\(total == 1 ? "" : "s") done" }
    return "\(done) set\(done == 1 ? "" : "s") done"
}

/// "1 workout" / "3 workouts" — the generic singular/plural form.
func pluralised(_ count: Int, singular: String, plural: String? = nil) -> String {
    count == 1 ? "1 \(singular)" : "\(count) \(plural ?? singular + "s")"
}

/// "1 day/week" / "3 days/week". D27 (2026-11-10).
func daysPerWeekText(_ n: Int) -> String { n == 1 ? "1 day/week" : "\(n) days/week" }

/// Projection honesty constants (evidence-review "also checked").
/// The least-squares fit uses only the last 12 weeks, so stale
/// novice gains don't carry forward, and the monthly cap scales
/// with experience — novice 4%/mo is honest, intermediate ~2%/mo
/// and advanced ~1%/mo (12-week gains run ~8–15% intermediate,
/// ~3–7% well-trained). The +30% total cap applies at every level.
/// Unknown experience defaults to the novice 4% ceiling.
/// The cap is also goal-dependent: hypertrophy (Build muscle) work
/// progresses strength more slowly than max-strength work — it sits
/// at the lower end of the same 8–15% intermediate band, so its
/// monthly cap is 0.75x the experience rate. The taper and the +30%
/// total cap are unchanged; only the rate is goal-dependent.
let projectionFitWindowDays = 84
let projectionMaxTotalGain = 0.30

func projectionMonthlyCapRate(for experience: ExperienceLevel?, goal: Goal? = nil) -> Double {
    let base: Double
    switch experience {
    case .new, nil: base = 0.04
    case .some: base = 0.02
    case .experienced: base = 0.01
    }
    if goal == .buildMuscle { return base * 0.75 }
    return base
}

// MARK: - Plate calculator (barbell only)

/// Plates per side for a target barbell weight, from the user's plate
/// inventory. Returns the plates per side (largest first) and the closest
/// achievable weight if the exact weight isn't loadable.
func platesPerSide(targetLb: Double, barWeightLb: Double, inventoryLb: [Double]) -> (plates: [Double], achievedLb: Double) {
    var remaining = max(0, (targetLb - barWeightLb) / 2)
    var plates: [Double] = []
    for plate in inventoryLb.sorted(by: >) {
        while remaining >= plate - 0.001 {
            plates.append(plate)
            remaining -= plate
        }
    }
    let achieved = barWeightLb + plates.reduce(0, +) * 2
    return (plates, achieved)
}

/// Suggested warm-up sets for a working weight (Strong / LiftStrong pattern).
/// Returns (weight, reps) pairs, light to heavy. Barbell: warm-ups start
/// at the empty 45 lb bar. Dumbbells (`isPair`): there is no bar — a 45 lb
/// "warm-up" for a pair of 40s would be heavier than the working set
/// (Gap 14) — so warm-ups are per-hand at 40/60/80% of the working
/// weight, rounded to the nearest 2.5 lb per hand.
func warmUpSets(for workingWeightLb: Double, isPair: Bool = false) -> [(weightLb: Double, reps: Int)] {
    guard workingWeightLb > 0 else { return [] }
    let increment = isPair ? 2.5 : 5.0
    let floor = isPair ? increment : 45.0
    var sets: [(Double, Int)] = []
    let w1 = max(floor, (workingWeightLb * 0.4 / increment).rounded() * increment)
    let w2 = max(floor, (workingWeightLb * 0.6 / increment).rounded() * increment)
    let w3 = max(floor, (workingWeightLb * 0.8 / increment).rounded() * increment)
    sets.append((w1, 5))
    if w2 > w1 { sets.append((w2, 3)) }
    if w3 > w2 { sets.append((w3, 1)) }
    return sets
}

// MARK: - Weekly set targets (Gap 2)

/// Planned working sets/week, split into push / pull / legs / core.
/// `total` is always the sum of the four parts by construction.
struct WeeklyTargets: Equatable {
    var push: Int
    var pull: Int
    var legs: Int
    var core: Int
    var total: Int
}

enum WeeklyTargetGroup {
    case push, pull, legs, core

    /// The session title for a day that trained mostly this group.
    var sessionTitle: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .core: return "Core"
        }
    }
}

extension MuscleGroup {
    /// Which weekly-target group a muscle counts toward. Exhaustive: every
    /// muscle lands in exactly one group, so the target total is the sum
    /// of its parts. Full-body lifts (farmer's carry, thrusters, cleans,
    /// snatches, burpees) are leg-driven compounds — they count toward legs.
    var weeklyTargetGroup: WeeklyTargetGroup {
        switch self {
        case .chest, .shoulders, .triceps: return .push
        case .back, .biceps, .forearms, .neck, .wrists: return .pull
        case .quads, .hamstrings, .glutes, .calves, .feet, .ankles, .fullBody: return .legs
        case .core, .obliques: return .core
        }
    }

    /// Hours a muscle needs before it reads fresh again (Gap 15):
    /// large muscles ~72 h, small muscles ~48 h. The ONE threshold
    /// behind `recoveryState`, `recoveryCaption`, and the fresh-muscle
    /// count — never re-derive it inline anywhere else.
    var recoveryHours: Double {
        switch self {
        case .chest, .back, .shoulders, .quads, .hamstrings, .glutes, .fullBody: return 72
        case .biceps, .triceps, .forearms, .calves, .core, .obliques, .neck, .wrists, .feet, .ankles: return 48
        }
    }
}

// MARK: - Store

final class WorkoutStore: ObservableObject {
    @Published var sessions: [SessionLog] = []
    /// User notes for the Notes page: workout notes saved from the
    /// per-exercise note field on Today, plus free notes written on
    /// the Notes page. On-device only.
    @Published var userNotes: [UserNote] = []
    /// Note categories the user created, plus the defaults. A note's
    /// `category` is one of these names (or nil = Uncategorized).
    /// On-device only. (DaRon 22:42.)
    @Published var noteCategories: [String] = ["Workout", "Food", "General"]
    @Published var bodyWeightLb: Double?

    // MARK: - Onboarding + program (on-device only)

    /// The user's setup answers. Nil until they finish the quiz (or skip it).
    @Published var profile: UserProfile?
    /// The program Today renders: the user's active program.
    @Published var activeProgram: UserProgram?
    /// The program generated from the user's quiz, kept so they can switch
    /// back to it.
    @Published var generatedProgram: UserProgram?
    /// Extra user-created programs (Pro: unlimited; free: one extra —
    /// the paywall's "2 programs" total: the generated program + one
    /// extra). Catalog picks, duplicates, and builder saves all land here.
    @Published var extraPrograms: [UserProgram] = []
    /// Favorite program + exercise ids, on-device only, per device.
    /// Favorites never touch the preset or any other user's data — they
    /// are just id sets, persisted under gymtracker.favorites.v1.
    @Published var favoriteProgramIDs: Set<String> = []
    @Published var favoriteExerciseIDs: Set<String> = []
    /// First-launch gate. False until onboarding completes (or a returning
    /// user from before onboarding is adopted — see init).
    @Published var hasCompletedOnboarding: Bool = false
    /// The day this user first set up the app — the "account creation"
    /// date (the app has no accounts; setup is the account). Stamped
    /// when onboarding completes, or at adoption for a returning user
    /// from before onboarding existed. The calendar never goes back
    /// before this month. Nil only until setup finishes.
    @Published var setupDate: Date?
    /// The one-time privacy screen. Once seen it never appears again.
    @Published var hasSeenPrivacy: Bool = false

    // MARK: - DaRon's preset (his device only — never offered to others)

    /// Unlock for DaRon's personal 5-day split. False for every other
    /// user: the preset is never seeded, listed, or offered unless this
    /// flag is set, which only happens when it is explicitly claimed on
    /// his device (a stored unlock from an earlier claim) or when a
    /// pre-onboarding install is adopted. Persisted in
    /// UserDefaults so a retake still offers the restore.
    @Published var isDaronPresetUnlocked: Bool = false
    /// The program that was active when setup was retaken, so finishing
    /// the retake can offer "Keep my current program" instead of silently
    /// overwriting it. Nil when no retake is in progress. Persisted so a
    /// retake survives a relaunch mid-flow.
    @Published var preRetakeProgram: UserProgram?
    /// A program switch that is waiting on the user to confirm replacing
    /// the preset. Set by `setActiveProgram` when the preset is active;
    /// the switch only happens when `confirmPendingProgramSwitch` runs.
    /// Nil when no switch is pending. In-memory only — a relaunch drops
    /// it, leaving the preset active (the safe default).
    @Published var pendingProgramSwitch: UserProgram?
    /// A finished onboarding result waiting on the user to choose between
    /// keeping the preset and switching to the new program. Set by
    /// `completeOnboarding` when the preset is active; resolved by
    /// `resolvePendingOnboarding`. In-memory only, like
    /// `pendingProgramSwitch`.
    @Published var pendingOnboarding: PendingOnboarding?

    /// True when DaRon's preset is the active program (matched by id —
    /// the stored copy decodes with the same id).
    var isPresetActive: Bool { activeProgram?.id == Program.daronPreset.id }

    /// The active program with the user's marked injuries applied — the
    /// program every screen reads (Today, next-workout preview,
    /// train-anyway, weekly targets). The stored program is never
    /// mutated (see `InjuryAdaptation`): with no injuries marked this
    /// IS the stored program, so DaRon's preset reads exactly as saved
    /// until he marks an injury, and marking one never rewrites the
    /// preset. Removing a mark restores the original exercises.
    var adaptedActiveProgram: UserProgram? {
        guard let program = activeProgram else { return nil }
        guard let profile else { return program }
        return InjuryAdaptation.adapt(program: program, profile: profile,
                                      customExercises: customExercises,
                                      equipment: effectiveEquipment)
    }

    /// One-line swap note for one exercise in the adapted program, for
    /// the exercise card and the next-workout preview ("Swapped because
    /// of your shoulder injury"). Nil when the exercise wasn't swapped.
    func swapNote(for template: ExerciseTemplate) -> String? {
        adaptedActiveProgram?.swaps.first { $0.to == template.name }?.shortExplanation
    }

    /// True when this exercise id is excluded by a marked injury — the
    /// swap pickers use it to never offer a loader as a replacement.
    func isExcludedByInjury(_ id: String) -> Bool {
        guard let limits = profile?.limits, !limits.isEmpty else { return false }
        return InjuryAdaptation.isExcluded(id, limits: limits)
    }

    /// A finished onboarding (quiz) result whose program switch is still
    /// awaiting the user's choice. See `pendingOnboarding`.
    struct PendingOnboarding: Equatable {
        var profile: UserProfile
        var program: UserProgram
    }
    /// Cold-start greeting: true when the app just cold-started (the
    /// loading screen showed) and the Today title should greet the user
    /// ("Hi DaRon") for 5 seconds before becoming "Today". Set by
    /// GymTrackerApp when the loading screen dismisses; cleared by
    /// TodayView once the greeting starts, so it only ever fires once
    /// per cold start. Not persisted — a fresh process starts false.
/// Today's calendar dropdown is open (the corner buttons step aside).
    @Published var calendarDropdownOpen = false
    /// Bumped by the Notes compose button in the corner (Notes opens a new note).
    @Published var composeNoteRequest = 0
        @Published var showColdStartGreeting = false

    // MARK: - Customization (on-device only)

    @Published var customExercises: [CustomExercise] = []
    @Published var exercisePreferences: [String: ExercisePreference] = [:]
    @Published var gymProfiles: [GymProfile] = []
    @Published var activeGymProfileID: String?
    @Published var settings: AppSettings = .default

    /// All programs the user can switch between: generated + extras.
    /// DaRon's personal split joins this list ONLY once his device is
    /// unlocked (`isDaronPresetUnlocked`) — it is never offered to other
    /// users. (His own device keeps it as the active program even before
    /// unlock; that stored program is untouched by this list.)
    var allPrograms: [UserProgram] {
        var list: [UserProgram] = []
        if isDaronPresetUnlocked { list.append(Program.daronPreset) }
        if let generatedProgram { list.append(generatedProgram) }
        list.append(contentsOf: extraPrograms)
        return list
    }

    /// Free tier caps custom exercises at 3; Pro is unlimited.
    static let freeCustomExerciseCap = 3

    func canAddCustomExercise(isPro: Bool) -> Bool {
        isPro || customExercises.count < Self.freeCustomExerciseCap
    }

    func addCustomExercise(_ exercise: CustomExercise) {
        customExercises.append(exercise)
        persistCustomization()
    }

    func deleteCustomExercise(id: String) {
        customExercises.removeAll { $0.id == id }
        persistCustomization()
    }

    func preference(for exerciseId: String) -> ExercisePreference {
        exercisePreferences[exerciseId] ?? .none
    }

    func setPreference(_ preference: ExercisePreference, for exerciseId: String) {
        if preference == .none {
            exercisePreferences.removeValue(forKey: exerciseId)
        } else {
            exercisePreferences[exerciseId] = preference
        }
        persistCustomization()
    }

    /// The equipment the generator may use right now: the active Gym Profile's
    /// checklist if one is set, else the profile's have-set (bodyweight
    /// always included).
    var effectiveEquipment: Set<Equipment> {
        if let id = activeGymProfileID,
           let gymProfile = gymProfiles.first(where: { $0.id == id }) {
            return gymProfile.equipment
        }
        return profile?.equipmentHave ?? Set(Equipment.allCases)
    }

    // MARK: - Draft (in-progress workout)

    @Published var draftDayKey: String? {
        didSet { persistDraft() }
    }
    @Published var draftDate: Date? {
        didSet { persistDraft() }
    }
    @Published var draftLogs: [String: [SetLog]] = [:] {
        didSet { persistDraft() }
    }
    @Published var draftFinisherChecks: [Bool] = [] {
        didSet { persistDraft() }
    }
    /// The ordered exercise list for today (user-reordered / added / swapped).
    @Published var draftExercises: [ExerciseTemplate] = [] {
        didSet { persistDraft() }
    }
    /// The plan the in-progress draft was built from (see DraftSession.sourcePlan).
    /// Nil for drafts saved before this field existed.
    @Published var draftSourcePlan: DayPlan? {
        didSet { persistDraft() }
    }
    @Published var draftSessionMod: SessionMod? {
        didSet { persistDraft() }
    }
    @Published var draftNotes: [String: String] = [:] {
        didSet { persistDraft() }
    }
    /// When each draft note was first typed, keyed by exercise id.
    /// Recorded at type-time (not save-time) so the Notes page stamps
    /// the note with the moment it was written. (DaRon 21:51.)
    @Published var draftNoteTimes: [String: Date] = [:] {
        didSet { persistDraft() }
    }

    // Rest timer. Set when a set is marked done; nil when no rest is running.
    // Persisted so it survives an app restart (and so the Start Rest Timer
    // App Intent can set it from Siri / Shortcuts).
    @Published var restEndsAt: Date? {
        didSet {
            if let restEndsAt {
                SharedDefaults.store.set(restEndsAt.timeIntervalSince1970, forKey: restEndsAtKey)
            } else {
                SharedDefaults.store.removeObject(forKey: restEndsAtKey)
            }
            // Keep the lock screen / Dynamic Island Live Activity in step:
            // start, pause, resume, stop and expiry all flow through here
            // (expiry and the Siri intent set this directly).
            syncRestLiveActivity()
        }
    }
    /// The exercise this rest belongs to. Persisted like `restEndsAt` so
    /// a rest (and its Live Activity label) survives an app restart — and
    /// so a Live Activity intent can set it when a set is checked from
    /// the lock screen.
    @Published var restTemplateID: String? {
        didSet {
            if let restTemplateID {
                SharedDefaults.store.set(restTemplateID, forKey: restTemplateIDKey)
            } else {
                SharedDefaults.store.removeObject(forKey: restTemplateIDKey)
            }
        }
    }
    /// Exercise the lock-screen Live Activity is showing, when the user
    /// tapped Next there (DaRon 22:27). The intent persists the id; the
    /// store applies it to the activity display and TodayView applies it
    /// to the current exercise. Cleared when a new rest starts (the
    /// display follows the new rest's exercise) or the rest ends.
    @Published var liveActivitySelectedExerciseID: String? {
        didSet {
            if let liveActivitySelectedExerciseID {
                SharedDefaults.store.set(liveActivitySelectedExerciseID, forKey: liveActivitySelectedExerciseKey)
            } else {
                SharedDefaults.store.removeObject(forKey: liveActivitySelectedExerciseKey)
            }
        }
    }
    /// When the rest timer is PAUSED, this holds the remaining seconds
    /// and `restEndsAt` is nil. Persisted like `restEndsAt` so a pause
    /// survives an app restart. Nil when the timer is running or stopped.
    @Published var restPausedRemaining: TimeInterval? {
        didSet {
            if let restPausedRemaining {
                SharedDefaults.store.set(restPausedRemaining, forKey: restPausedKey)
            } else {
                SharedDefaults.store.removeObject(forKey: restPausedKey)
            }
        }
    }

    /// True while the rest timer is paused (countdown frozen).
    var isRestPaused: Bool { restPausedRemaining != nil }

    /// True while a rest is running (counting down) or paused — the
    /// floating rest-timer panel is on screen above the menu button
    /// (ContentView's bottomStack). Screens read this for their bottom
    /// clearance (LayoutClearance): while a rest is active the panel
    /// would otherwise cover the last row / primary button at
    /// scroll-bottom. Same check ContentView uses for the panel itself.
    var isRestActive: Bool { restEndsAt != nil || restPausedRemaining != nil }

    /// Seconds left on the rest timer, whether running or paused.
    var restRemainingSeconds: TimeInterval? {
        if let restPausedRemaining { return restPausedRemaining }
        guard let restEndsAt else { return nil }
        return max(0, restEndsAt.timeIntervalSinceNow)
    }

    private let restEndsAtKey = "gymtracker.restEndsAt.v1"
    private let restPausedKey = "gymtracker.restPaused.v1"
    private let restTemplateIDKey = "gymtracker.restTemplateID.v1"
    private let liveActivitySelectedExerciseKey = "gymtracker.liveActivitySelectedExercise.v1"

    private let sessionsKey = "gymtracker.sessions.v1"
    private let userNotesKey = "gymtracker.userNotes.v1"
    private let noteCategoriesKey = "gymtracker.noteCategories.v1"
    private let weightKey = "gymtracker.bodyweight.v1"
    private let draftKey = "gymtracker.draft.v1"
    private let profileKey = "gymtracker.profile.v1"
    private let programKey = "gymtracker.program.v1"
    private let generatedKey = "gymtracker.generated.v1"
    private let onboardingKey = "gymtracker.onboarding.v1"
    private let setupDateKey = "gymtracker.setupDate.v1"
    private let privacyKey = "gymtracker.privacy.v1"
    private let customExercisesKey = "gymtracker.customExercises.v1"
    private let preferencesKey = "gymtracker.exercisePreferences.v1"
    private let gymProfilesKey = "gymtracker.gymProfiles.v1"
    private let activeGymProfileKey = "gymtracker.activeGymProfile.v1"
    private let settingsKey = "gymtracker.settings.v1"
    private let extraProgramsKey = "gymtracker.extraPrograms.v1"
    /// Favorite program + exercise ids (see FavoriteIDs below).
    private let favoritesKey = "gymtracker.favorites.v1"
    /// Unlock flag for DaRon's preset — see `isDaronPresetUnlocked`.
    static let daronPresetUnlockKey = "gymtracker.daronPresetUnlocked.v1"
    private let preRetakeProgramKey = "gymtracker.preRetakeProgram.v1"
    /// One-time App Group migration flag (P0-2). Lives in the shared suite
    /// once set; never set in .standard.
    private static let appGroupMigrationKey = "gymtracker.appGroupMigrated.v1"
    /// One-time mislabeled-session fix flag (P1-5).
    private static let mislabeledLegsSessionKey = "gymtracker.mislabeledLegsSessionFixed.v1"

    /// One-time move of ALL gymtracker.* keys from UserDefaults.standard
    /// into the shared App Group suite (P0-2), so the app, the widget,
    /// and the Live Activity intents all read the same store. Idempotent:
    /// the flag lives in the shared suite once set. If the suite is
    /// unavailable (group not registered yet) the migration aborts and
    /// everything keeps working from .standard — data is never deleted
    /// without a successful copy first. MCP keys (gymtracker.mcp.*) are
    /// EXCLUDED: the grant/token must stay in .standard, readable only
    /// by the app, never by the extension (long-term: Keychain).
    private func migrateToAppGroupIfNeeded() {
        guard let shared = SharedDefaults.shared else { return }
        guard !shared.bool(forKey: Self.appGroupMigrationKey) else { return }
        let standard = UserDefaults.standard
        let keys = standard.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("gymtracker.") && !$0.hasPrefix("gymtracker.mcp.")
        }
        for key in keys {
            shared.set(standard.object(forKey: key), forKey: key)
        }
        for key in keys {
            standard.removeObject(forKey: key)
        }
        shared.set(true, forKey: Self.appGroupMigrationKey)
    }

    init() {
        migrateToAppGroupIfNeeded()
        load()
        loadDraft()
        loadProfileAndProgram()
        loadCustomization()
        adoptReturningUserIfNeeded()
        ensureSetupDate()
        loadRestTimer()
        // Restore the Live Activity if a rest was running/paused when the
        // app closed (loadRestTimer restored it above).
        syncRestLiveActivity()
        // Listen for Live Activity intents mutating state from the lock
        // screen (set checked / next exercise).
        observeLiveActivityChanges()
    }

    deinit {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            nil, nil)
    }

    // MARK: - Sessions + history helpers

    func saveSession(_ session: SessionLog) {
        sessions.removeAll { $0.id == session.id }
        sessions.append(session)
        sessions.sort { $0.date > $1.date }
        persistSessions()
    }

    /// Delete a saved session (P1-5). The caller confirms before calling
    /// — this just deletes and persists.
    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        persistSessions()
    }

    /// Rename a saved session's title (P1-5). Rename-only — per-set
    /// editing is not supported. Blank titles are ignored.
    func renameSession(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].dayTitle = trimmed
        persistSessions()
    }

    /// One-time relabel (P1-5): the 2026-11-09 17:39 "Mon · Legs" session
    /// holds the morning's upper-body exercises — the draft's source plan
    /// changed under the same day key that day, so the save took the new
    /// plan's title. Relabel it "Upper" — only when exactly ONE session
    /// matches (dayKey Mon, title "Legs", within ±10 min of 17:39, zero
    /// leg-muscle exercises). No match means nothing to fix (flag set,
    /// done); an ambiguous match (2+) does nothing and leaves the flag
    /// unset, so a later delete can still disambiguate it.
    private func migrateMislabeledLegsSessionIfNeeded() {
        let flagKey = Self.mislabeledLegsSessionKey
        guard !SharedDefaults.store.bool(forKey: flagKey) else { return }
        let reference = Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: 9, hour: 17, minute: 39)) ?? Date()
        let legMuscles: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves]
        let matches = sessions.filter { session in
            session.dayKey == "Mon" && session.dayTitle == "Legs"
                && abs(session.date.timeIntervalSince(reference)) <= 10 * 60
                && !session.exercises.contains { exercise in
                    guard let muscle = ExerciseLibrary.byId(exercise.exerciseId, plus: customExercises)?.muscle else { return false }
                    return legMuscles.contains(muscle)
                }
        }
        if matches.isEmpty {
            SharedDefaults.store.set(true, forKey: flagKey)
            return
        }
        guard matches.count == 1, let match = matches.first,
              let index = sessions.firstIndex(where: { $0.id == match.id }) else { return }
        sessions[index].dayTitle = "Upper"
        persistSessions()
        SharedDefaults.store.set(true, forKey: flagKey)
    }

    /// Label for a saved session, derived from the session itself —
    /// never copied from a plan. THE choke point for session labels:
    /// every save path (Today, MCP, Siri intent) must go through here
    /// so a label can never again lie about its contents.
    ///
    /// `dayKey` is the weekday of the session's DATE. A "train anyway"
    /// session done Sunday with Monday's plan is a Sunday session, not
    /// a Monday one — the old code copied the plan's key.
    ///
    /// `dayTitle` is the plan's title when the logged exercises agree
    /// with it, else the title of the muscle family the session
    /// actually trained (a Legs day whose exercises were all swapped
    /// to push work saves as Push, not Legs). The family is the
    /// plurality of done working sets, by the same
    /// `MuscleGroup.weeklyTargetGroup` grouping the weekly targets
    /// use; a tie, no done sets, or an unmapped exercise (a superset
    /// with no library entry) keeps the plan title. Titles with no
    /// family ("Upper Mix", "Full Body A", catalog names) never
    /// contradict — they always stand.
    static func sessionLabel(date: Date, plan: DayPlan, exercises: [ExerciseLog],
                             customs: [CustomExercise] = []) -> (dayKey: String, dayTitle: String) {
        let dayKey = Program.dayKey(for: date) ?? plan.key
        var counts: [WeeklyTargetGroup: Int] = [:]
        for log in exercises {
            guard let lib = ExerciseLibrary.byId(log.exerciseId, plus: customs) else { continue }
            let done = log.sets.filter { $0.done && $0.kind != .warmup }.count
            guard done > 0 else { continue }
            counts[lib.muscle.weeklyTargetGroup, default: 0] += done
        }
        var dayTitle = plan.title
        if let topCount = counts.values.max(), topCount > 0,
           counts.values.filter({ $0 == topCount }).count == 1,
           let top = counts.first(where: { $0.value == topCount })?.key,
           let planFamily = planFamily(for: plan.title),
           planFamily != top {
            dayTitle = top.sessionTitle
        }
        return (dayKey, dayTitle)
    }

    /// The muscle family a plan title names, if it names one.
    private static func planFamily(for title: String) -> WeeklyTargetGroup? {
        switch title {
        case "Legs": return .legs
        case "Push": return .push
        case "Pull": return .pull
        case "Core": return .core
        default: return nil
        }
    }

    // MARK: - Notes

    /// Add a note (workout note or free note). Blank notes are ignored.
    /// Newest first — the note just written is always on top.
    func addUserNote(title: String, body: String, workoutTitle: String? = nil, date: Date = Date(), category: String? = nil) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedBody.isEmpty else { return }
        let note = UserNote(
            id: UUID(),
            title: trimmedTitle,
            body: trimmedBody,
            createdAt: date,
            updatedAt: date,
            workoutTitle: workoutTitle,
            isPinned: false,
            category: category
        )
        userNotes.insert(note, at: 0)
        persistUserNotes()
    }

    /// A note written in the per-exercise note field on Today: title is
    /// the exercise, `workoutTitle` is the day it came from. Called when
    /// a workout is saved, so only saved workouts land on the Notes page.
    func addWorkoutNote(exerciseName: String, dayTitle: String, text: String, date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        addUserNote(title: exerciseName, body: trimmed, workoutTitle: dayTitle, date: date)
    }

    /// Save edits from the note editor. The edited note jumps to the top
    /// (most recently edited first).
    func updateUserNote(_ note: UserNote, title: String, body: String, category: String?, isPinned: Bool) {
        guard let index = userNotes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = note
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.category = category
        // The pin state comes from the editor, not the pre-edit
        // snapshot: copying the snapshot back reverted a pin toggled
        // during the edit.
        updated.isPinned = isPinned
        updated.updatedAt = Date()
        userNotes[index] = updated
        userNotes.sort { $0.updatedAt > $1.updatedAt }
        persistUserNotes()
    }

    /// Compose (Apple Notes style, Nov 12): a new blank note opens
    /// straight away and is typed into in place. The Notes page deletes
    /// it again if it is left blank.
    @discardableResult
    func createBlankNote(category: String? = nil) -> UUID {
        let now = Date()
        let note = UserNote(id: UUID(), title: "", body: "", createdAt: now, updatedAt: now,
                            workoutTitle: nil, isPinned: false, category: category)
        userNotes.insert(note, at: 0)
        persistUserNotes()
        return note.id
    }

    /// Live autosave while typing: stores the text exactly as typed
    /// (no trimming, so a trailing space or newline is kept) and moves
    /// the note to the top, like Apple Notes.
    func editUserNote(id: UUID, title: String, body: String) {
        guard let index = userNotes.firstIndex(where: { $0.id == id }) else { return }
        guard userNotes[index].title != title || userNotes[index].body != body else { return }
        userNotes[index].title = title
        userNotes[index].body = body
        userNotes[index].updatedAt = Date()
        userNotes.sort { $0.updatedAt > $1.updatedAt }
        persistUserNotes()
    }

    /// File a note in a category (nil = Uncategorized).
    func setNoteCategory(id: UUID, category: String?) {
        guard let index = userNotes.firstIndex(where: { $0.id == id }) else { return }
        userNotes[index].category = category
        persistUserNotes()
    }

    func deleteUserNote(id: UUID) {
        userNotes.removeAll { $0.id == id }
        persistUserNotes()
    }

    /// Pin or unpin a note. Pinned notes sort to the top of the list.
    /// (DaRon 22:42.)
    func setNotePinned(_ note: UserNote, pinned: Bool) {
        guard let index = userNotes.firstIndex(where: { $0.id == note.id }) else { return }
        userNotes[index].isPinned = pinned
        persistUserNotes()
    }

    /// Add a user-made note category. Duplicates (case-insensitive)
    /// and blanks are ignored. (DaRon 22:42.)
    func addNoteCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !noteCategories.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        noteCategories.append(trimmed)
        persistNoteCategories()
    }

    private func persistNoteCategories() {
        SharedDefaults.store.set(noteCategories, forKey: noteCategoriesKey)
    }

    private func persistUserNotes() {
        if let data = try? JSONEncoder().encode(userNotes) {
            SharedDefaults.store.set(data, forKey: userNotesKey)
        }
    }

    func lastLog(for exerciseId: String) -> ExerciseLog? {
        // Explicit loop — the sorted/flatMap/first chain timed out the
        // type checker (Swift 6 is slow inferring chained closures).
        let sorted = sessions.sorted { $0.date > $1.date }
        for session in sorted {
            for exercise in session.exercises where exercise.exerciseId == exerciseId {
                return exercise
            }
        }
        return nil
    }

    func lastWeight(for template: ExerciseTemplate) -> Double? {
        lastLog(for: template.id)?.sets.compactMap { $0.weightLb }.first
    }

    /// Best (heaviest) working set ever logged for an exercise.
    func bestSet(for exerciseId: String) -> SetLog? {
        // Explicit loop — the flatMap/filter/max chain timed out the
        // type checker (Swift 6 is slow inferring chained closures).
        var best: SetLog?
        for session in sessions {
            for exercise in session.exercises where exercise.exerciseId == exerciseId {
                for set in exercise.sets where set.done && set.kind != .warmup && (set.weightLb ?? 0) > 0 {
                    if best == nil || (set.weightLb ?? 0) > (best!.weightLb ?? 0) {
                        best = set
                    }
                }
            }
        }
        return best
    }

    /// Estimated 1RM for an exercise — the shared validity gate
    /// (`bestValidOneRepMax`): compound lifts only, done working sets
    /// of ≤10 reps. An isolation lift, or a lift whose only logged
    /// sets are 11+ reps, has no 1RM (nil), never a capped-up guess
    /// from a 15-rep set (Gap 7).
    func oneRepMax(for exerciseId: String) -> Double? {
        guard ExerciseLibrary.byId(exerciseId, plus: customExercises)?.isCompound == true else { return nil }
        var best: Double = 0
        for session in sessions {
            for exercise in session.exercises where exercise.exerciseId == exerciseId {
                if let oneRM = bestValidOneRepMax(in: exercise.sets, isCompound: true), oneRM > best {
                    best = oneRM
                }
            }
        }
        return best > 0 ? best : nil
    }

    /// Best valid 1RM for one exercise in one session — the same gate
    /// as `oneRepMax(for:)`, so the strength graph and History can
    /// never disagree about what a session's max was.
    func sessionOneRepMax(session: SessionLog, exerciseId: String) -> Double? {
        guard ExerciseLibrary.byId(exerciseId, plus: customExercises)?.isCompound == true else { return nil }
        var best: Double = 0
        for exercise in session.exercises where exercise.exerciseId == exerciseId {
            if let oneRM = bestValidOneRepMax(in: exercise.sets, isCompound: true), oneRM > best {
                best = oneRM
            }
        }
        return best > 0 ? best : nil
    }

    /// The most recent logs for an exercise, newest first (one per
    /// session). The 2-for-2 progression gate reads the first two.
    private func recentLogs(for exerciseId: String, count: Int) -> [ExerciseLog] {
        var logs: [ExerciseLog] = []
        for session in sessions.sorted(by: { $0.date > $1.date }) {
            for exercise in session.exercises where exercise.exerciseId == exerciseId {
                logs.append(exercise)
                if logs.count >= count { return logs }
            }
        }
        return logs
    }

    /// True when a log finished every working set at the top of the range.
    private func hitTopReps(_ log: ExerciseLog, template: ExerciseTemplate) -> Bool {
        let working = log.sets.filter { $0.kind != .warmup }
        return !working.isEmpty && working.allSatisfy { $0.done && $0.reps >= template.topReps }
    }

    /// Bodyweight progression ladders: ordered rungs per movement family,
    /// easiest first. A bodyweight exercise never progresses by a weight
    /// bump — it steps to the next rung of its ladder (or a harder rep
    /// target at the top). Data, not per-screen logic: the draft, the
    /// hint, and the MCP server all read this one table. An id in two
    /// ladders resolves to the earlier ladder's successor (weighted
    /// pull-up is the gateway to the muscle-up, so it sits in the
    /// muscle-up ladder first).
    enum BodyweightLadder {
        static let ladders: [(family: String, rungs: [String])] = [
            ("muscle-up", ["weighted-pull-up", "muscle-up"]),
            ("push-up", ["wall-push-up", "knee-push-up", "push-up-incline", "push-up",
                         "push-up-close", "push-up-decline", "push-up-diamond",
                         "push-up-archer", "pseudo-planche-push-up", "one-arm-push-up"]),
            ("pull-up", ["scapular-pull-up", "band-assisted-pull-up", "assisted-pull-up",
                         "negative-pull-up", "pull-up", "wide-grip-pull-up",
                         "archer-pull-up", "one-arm-pull-up", "weighted-pull-up"]),
            ("dip", ["dip-assisted", "bench-dip", "dips", "ring-dip", "weighted-dip"]),
            ("squat", ["chair-squat", "bodyweight-squat", "split-squat-bodyweight",
                       "squat-pistol-box", "squat-pistol-assisted", "pistol-squat",
                       "shrimp-squat"]),
            ("handstand", ["wall-handstand", "handstand-hold", "pike-push-up",
                           "wall-handstand-push-up", "handstand-push-up"]),
            ("leg raise", ["leg-raise-bent-knee", "leg-raise", "hanging-knee-raise",
                           "hanging-leg-raise", "toes-to-bar", "l-sit", "dragon-flag"]),
            ("plank", ["plank-knee", "plank", "side-plank-knee", "side-plank",
                       "hollow-body", "hollow-rock"]),
            ("front lever", ["tuck-front-lever", "front-lever"]),
        ]

        /// The next rung after `id`, or nil at the top of its ladder (or
        /// when the exercise is not on any ladder).
        static func nextStep(after id: String) -> String? {
            for ladder in ladders {
                if let i = ladder.rungs.firstIndex(of: id), i + 1 < ladder.rungs.count {
                    return ladder.rungs[i + 1]
                }
            }
            return nil
        }

        /// The ladder family an exercise belongs to, for hint wording.
        static func familyName(for id: String) -> String? {
            ladders.first { $0.rungs.contains(id) }?.family
        }
    }

    /// Next session's weight + reps for a template (Gap 3: progression is
    /// actually applied, not hint-only). 2-for-2 rule: the last TWO logged
    /// sessions for this exercise both finished every working set at
    /// topReps. Then the weight bumps 5% (compound) / 2.5% (isolation),
    /// rounded UP to the next loadable increment (2.5 lb per dumbbell or
    /// barbell, 5 lb machine/cable stack), and reps reset to the bottom
    /// of the range. Bodyweight exercises never bump weight: on a ladder
    /// rung the draft stays at the same reps (the hint names the next
    /// rung to swap in); at the top of a ladder, or off-ladder, the rep
    /// target goes up by 2 instead. The effort gate is two consecutive
    /// sessions — no RIR capture.
    func nextWeightAndReps(for template: ExerciseTemplate) -> (weightLb: Double?, reps: Int) {
        let baseWeight = lastWeight(for: template) ?? template.defaultWeightLb
        guard let lib = ExerciseLibrary.byId(template.id, plus: customExercises) else {
            return (baseWeight, template.topReps)
        }
        if template.isBodyweight || lib.isBodyweight {
            let recent = recentLogs(for: template.id, count: 2)
            guard recent.count == 2, recent.allSatisfy({ hitTopReps($0, template: template) }) else {
                return (baseWeight, template.topReps)
            }
            if BodyweightLadder.nextStep(after: template.id) != nil {
                return (baseWeight, template.topReps)
            }
            return (baseWeight, template.topReps + 2)
        }
        guard let weight = baseWeight, weight > 0 else {
            return (baseWeight, template.topReps)
        }
        let recent = recentLogs(for: template.id, count: 2)
        guard recent.count == 2, recent.allSatisfy({ hitTopReps($0, template: template) }) else {
            return (baseWeight, template.topReps)
        }
        let percent = lib.isCompound ? 0.05 : 0.025
        let increment: Double = (lib.equipment.contains(.machine) || lib.equipment.contains(.cable)) ? 5 : 2.5
        let raw = weight * (1 + percent)
        // Round UP to the next loadable increment (the 1e-9 guard keeps an
        // exact multiple from floating-point noise pushing it a step high).
        let bumped = ((raw - 1e-9) / increment).rounded(.up) * increment
        return (bumped, template.bottomReps)
    }

    func progressionHint(for template: ExerciseTemplate) -> String {
        guard let last = lastLog(for: template.id) else {
            return "First time logging this one. Use the weight shown and see how it feels."
        }
        let working = last.sets.filter { $0.kind != .warmup }
        let doneSets = working.filter { $0.done }
        if doneSets.count < working.count {
            return "Last time you finished \(doneSets.count) of \(working.count) sets. Stay at this weight or go lighter."
        }
        guard !working.isEmpty else {
            return "Last time: no working sets logged. Stay at this weight."
        }
        if working.allSatisfy({ $0.reps >= template.topReps }) {
            let lib = ExerciseLibrary.byId(template.id, plus: customExercises)
            if template.isBodyweight || lib?.isBodyweight == true {
                // Bodyweight progression is a ladder step, never a weight
                // bump. Two sessions at the top of the range names the
                // next rung; one session says how close the step is.
                let recent = recentLogs(for: template.id, count: 2)
                let nextId = BodyweightLadder.nextStep(after: template.id)
                let nextName = nextId.flatMap { ExerciseLibrary.byId($0, plus: customExercises)?.name }
                if recent.count == 2, recent.allSatisfy({ hitTopReps($0, template: template) }) {
                    if let nextName {
                        let family = BodyweightLadder.familyName(for: template.id).map { " on the \($0) ladder" } ?? ""
                        return "Two sessions in a row at \(template.topReps) reps — next step\(family): \(nextName). Swap it in with Replace on this exercise."
                    }
                    return "Two sessions in a row at \(template.topReps) reps — add 2 reps next time."
                }
                if let nextName {
                    return "Last time every set hit \(template.topReps) reps. Hit them once more and you'll step up to \(nextName) next time."
                }
                return "Last time every set hit \(template.topReps) reps. Try a harder variation or add reps next time."
            }
            let percentText = (lib?.isCompound ?? false) ? "5%" : "2.5%"
            let recent = recentLogs(for: template.id, count: 2)
            if recent.count == 2, recent.allSatisfy({ hitTopReps($0, template: template) }) {
                let next = nextWeightAndReps(for: template)
                if let weight = next.weightLb {
                    return "Two sessions in a row at \(template.topReps) reps — weight went up ~\(percentText) to \(displayWeightLabel(weight, isPair: template.isPair, for: template)) this time. Reps back to \(template.bottomReps)."
                }
                return "Two sessions in a row at \(template.topReps) reps — hold this weight and hit \(template.bottomReps) reps."
            }
            return "Last time every set hit \(template.topReps) reps. Hit them once more and the weight goes up ~\(percentText) next time."
        }
        let repsText = doneSets.map { String($0.reps) }.joined(separator: ", ")
        return "Last time: \(repsText) reps. Stay at this weight."
    }

    /// Total volume (weight × reps, working sets only) for sessions in a range.
    /// One formula (`volumeLb(for:)`) — per-hand DB loads doubled, warm-ups
    /// excluded — shared with History's session rows.
    func volume(from start: Date, to end: Date) -> Double {
        var total: Double = 0
        for session in sessions where session.date >= start && session.date <= end {
            total += volumeLb(for: session.exercises)
        }
        return total
    }

    /// Sets done per muscle group this week (Fitbod weekly-set-targets pattern).
    func setsByMuscleThisWeek() -> [MuscleGroup: Int] {
        let start = weekStartDate(for: Date())
        var counts: [MuscleGroup: Int] = [:]
        for session in sessions where session.date >= start {
            for exercise in session.exercises {
                let muscle = ExerciseLibrary.byId(exercise.exerciseId, plus: customExercises)?.muscle
                    ?? ExerciseLibrary.byId(exercise.exerciseId)?.muscle
                guard let muscle else { continue }
                counts[muscle, default: 0] += exercise.sets.filter { $0.done && $0.kind != .warmup }.count
            }
        }
        return counts
    }

    /// Planned working sets/week from the active program, split into
    /// push / pull / legs / core (Gap 2). Derived live — never a fixed
    /// constant — so a 3-day Full Body program targets ~48, not 60.
    /// Every planned set lands in exactly one group (see
    /// MuscleGroup.weeklyTargetGroup), so the total IS the sum of its
    /// parts by construction; the assert catches any future muscle that
    /// escapes the grouping. No program (or an empty one) falls back to
    /// 30 (10 push / 10 pull / 10 legs).
    func plannedWeeklyTargets() -> WeeklyTargets {
        let fallback = WeeklyTargets(push: 10, pull: 10, legs: 10, core: 0, total: 30)
        guard let program = adaptedActiveProgram, !program.days.isEmpty else { return fallback }
        var counts: [MuscleGroup: Int] = [:]
        for day in program.days {
            for template in day.exercises {
                guard let muscle = ExerciseLibrary.byId(template.id, plus: customExercises)?.muscle else { continue }
                counts[muscle, default: 0] += template.sets
            }
        }
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return fallback }
        var push = 0, pull = 0, legs = 0, core = 0
        for (muscle, count) in counts {
            switch muscle.weeklyTargetGroup {
            case .push: push += count
            case .pull: pull += count
            case .legs: legs += count
            case .core: core += count
            }
        }
        assert(push + pull + legs + core == total,
               "plannedWeeklyTargets: every planned set must land in exactly one target group")
        return WeeklyTargets(push: push, pull: pull, legs: legs, core: core,
                             total: push + pull + legs + core)
    }

    /// Sets done this week per target group — the same grouping as
    /// plannedWeeklyTargets, so done counts and targets always compare
    /// like with like.
    func setsByTargetGroupThisWeek() -> (push: Int, pull: Int, legs: Int, core: Int) {
        let counts = setsByMuscleThisWeek()
        var push = 0, pull = 0, legs = 0, core = 0
        for (muscle, count) in counts {
            switch muscle.weeklyTargetGroup {
            case .push: push += count
            case .pull: pull += count
            case .legs: legs += count
            case .core: core += count
            }
        }
        return (push, pull, legs, core)
    }

    /// Consecutive weeks with at least one session (streak). A week
    /// still in progress doesn't break the streak: if nothing is
    /// logged yet this week, counting starts from last week — a streak
    /// must not read 0 on Monday morning before the week's workout.
    var weeklyStreak: Int {
        var streak = 0
        var weekStart = weekStartDate(for: Date())
        if !sessions.contains(where: { weekStartDate(for: $0.date) == weekStart }) {
            weekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        }
        while sessions.contains(where: { weekStartDate(for: $0.date) == weekStart }) {
            streak += 1
            weekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        }
        return streak
    }

    // MARK: - Recovery (Body screen: fresh vs recovering, from logged history)

    /// One pass over saved sessions: the latest date each muscle group was
    /// trained (a done working set). Primary + secondary muscles
    /// (`LibraryExercise.trainedMuscles`) — the same list the body
    /// diagram lights — so recovery, the Body screen, and rest-day
    /// stretches all agree with the diagram: a bench press marks
    /// shoulders and triceps trained, not just chest. Set/volume counts
    /// (`setsByMuscleThisWeek` / `plannedWeeklyTargets`) stay
    /// primary-only: one set is one set, and counting it toward two
    /// muscles would inflate a group total.
    func lastTrainedDates() -> [MuscleGroup: Date] {
        var trainedById: [String: [MuscleGroup]] = [:]
        for lib in ExerciseLibrary.all(plus: customExercises) {
            trainedById[lib.id] = lib.trainedMuscles
        }
        var dates: [MuscleGroup: Date] = [:]
        let sorted = sessions.sorted { $0.date > $1.date }
        for session in sorted {
            for log in session.exercises {
                guard log.sets.contains(where: { $0.done && $0.kind == .working }) else { continue }
                guard let groups = trainedById[log.exerciseId] else { continue }
                for muscle in groups where dates[muscle] == nil {
                    dates[muscle] = session.date
                }
            }
        }
        return dates
    }

    /// Recovery state of a muscle group from logged history — the ONE
    /// recovery rule for the Body screen, Today, and the fresh-muscle
    /// count, so they can never disagree. Large muscles need ~72 h,
    /// small muscles ~48 h (Gap 15). Previously this was a flat 48 h
    /// here, "days ≤ 2" in `recoveryCaption`, and "3+ days" in the Body
    /// screen's own docs — the same 60-hour-old leg session read
    /// fresh on the diagram and recovering in the caption.
    func recoveryState(for muscle: MuscleGroup, dates: [MuscleGroup: Date]? = nil) -> MuscleRecovery {
        let dates = dates ?? lastTrainedDates()
        guard let last = dates[muscle] else { return .fresh }
        let hours = Date().timeIntervalSince(last) / 3600
        return hours <= muscle.recoveryHours ? .recovering : .fresh
    }

    /// Days since the most recent saved session (nil when no sessions yet).
    var daysSinceLastWorkout: Int? {
        guard let last = sessions.map({ $0.date }).max() else { return nil }
        return Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: last),
            to: Calendar.current.startOfDay(for: Date())).day
    }

    /// Muscle groups not trained recently — fresh and ready. Derived
    /// from `recoveryState`, not a second inline hour threshold, so
    /// this count and the Body diagram always agree.
    var freshMuscleGroups: [MuscleGroup] {
        let tracked: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps, .forearms, .quads, .hamstrings, .glutes, .calves, .core, .obliques, .neck, .wrists, .feet, .ankles]
        let dates = lastTrainedDates()
        return tracked.filter { recoveryState(for: $0, dates: dates) == .fresh }
    }

    /// A one-line caption for a muscle group on the Body screen.
    /// The recovering/fresh word comes from `recoveryState` (same
    /// muscle-aware rule as the diagram), never from a day bucket —
    /// a small muscle trained 2 days ago is fresh here exactly when
    /// the diagram shows it fresh.
    func recoveryCaption(for muscle: MuscleGroup) -> String {
        let dates = lastTrainedDates()
        guard let last = dates[muscle] else {
            return "Not trained yet — fresh and ready."
        }
        let days = Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: last),
            to: Calendar.current.startOfDay(for: Date())).day ?? 0
        let word = recoveryState(for: muscle, dates: dates) == .recovering ? "recovering" : "fresh"
        if days == 0 { return "Trained today — \(word)." }
        if days == 1 { return "Trained yesterday — \(word)." }
        if word == "recovering" { return "Trained \(days) days ago — recovering." }
        return "Last trained \(days) days ago — fresh."
    }

    func saveBodyWeight(_ value: Double?) {
        bodyWeightLb = value
        if let value = value {
            SharedDefaults.store.set(value, forKey: weightKey)
        } else {
            SharedDefaults.store.removeObject(forKey: weightKey)
        }
    }

    // MARK: - Units

    /// The unit in effect for an exercise: its override, else the global unit.
    func unit(for template: ExerciseTemplate) -> WeightUnit {
        template.unitOverride ?? settings.weightUnit
    }

    /// Format a stored lb weight in the unit in effect for an exercise.
    func displayWeightLabel(_ weightLb: Double?, isPair: Bool, for template: ExerciseTemplate? = nil) -> String {
        let unit = template.map { unit(for: $0) } ?? settings.weightUnit
        guard let display = unit.displayValue(for: weightLb), display > 0 else { return "Set weight" }
        // Pairs read the same as any weight ("40 lb", not the old "40s").
        return "\(formatNumber(display)) \(unit.label)"
    }

    /// Weight text for one logged set — the ONE formatter History's
    /// session detail and Calendar's day detail both use (P1-1 rule):
    /// a logged weight as usual, in the unit in effect for the
    /// exercise (the unit override saved with the log, else the global
    /// unit); "—" for a weighted exercise with no weight logged;
    /// "Bodyweight" for a bodyweight exercise. Bodyweight comes from
    /// the library entry's `isBodyweight` flag.
    func setWeightText(_ set: SetLog, exercise: ExerciseLog) -> String {
        if let weight = set.weightLb, weight > 0 {
            let unit = exercise.unitOverride ?? settings.weightUnit
            return "\(weightLabel(weight, isPair: exercise.isPair, unit: unit)) × \(set.reps)"
        }
        let isBodyweight = ExerciseLibrary.byId(exercise.exerciseId, plus: customExercises)?.isBodyweight ?? false
        return isBodyweight
            ? "Bodyweight × \(set.reps)"
            : "— × \(set.reps)"
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return roundedWeightText(value)
    }

    // MARK: - Onboarding + program

    /// Finish the intro flow: store the answers and the program, flip the
    /// first-launch gate. The main app appears immediately after.
    ///
    /// Preset gate: when DaRon's preset is active, finishing onboarding
    /// NEVER silently replaces it. The result is stashed in
    /// `pendingOnboarding` and the user lands back in the app with the
    /// preset intact; the "Keep my current program" / "Switch to the new
    /// program" choice resolves it via `resolvePendingOnboarding`. The
    /// only way past the gate here is `keepCurrentProgram: true` (keep
    /// the preset, store the new program as the generated one) or
    /// resolving the pending result. First-time onboarding is unaffected
    /// — there is no active program to protect yet.
    func completeOnboarding(profile: UserProfile, program: UserProgram, keepCurrentProgram: Bool = false) {
        if !keepCurrentProgram, isPresetActive, program.id != Program.daronPreset.id {
            pendingOnboarding = PendingOnboarding(profile: profile, program: program)
            hasCompletedOnboarding = true
            stampSetupDate()
            persistOnboarding()
            return
        }
        applyOnboarding(profile: profile, program: program, keepCurrentProgram: keepCurrentProgram)
    }

    /// Resolve a stashed onboarding result (see `completeOnboarding`).
    /// `keepCurrentProgram: true` keeps the preset active and stores the
    /// new program as the generated one; false switches to it.
    func resolvePendingOnboarding(keepCurrentProgram: Bool) {
        guard let pending = pendingOnboarding else { return }
        pendingOnboarding = nil
        applyOnboarding(profile: pending.profile, program: pending.program, keepCurrentProgram: keepCurrentProgram)
    }

    /// Drop a stashed onboarding result without applying it. The preset
    /// stays active and the quiz result is discarded (retaking setup
    /// rebuilds it).
    func cancelPendingOnboarding() {
        pendingOnboarding = nil
    }

    /// The actual onboarding apply step, shared by `completeOnboarding`
    /// and `resolvePendingOnboarding`. Callers go through those two —
    /// never call this directly with a program that would silently
    /// replace the preset.
    private func applyOnboarding(profile: UserProfile, program: UserProgram, keepCurrentProgram: Bool) {
        self.profile = profile
        if !program.isPreset {
            generatedProgram = program
        }
        if !keepCurrentProgram || activeProgram == nil {
            activeProgram = program
        }
        hasCompletedOnboarding = true
        stampSetupDate()
        if let bodyweight = profile.bodyweightLb {
            saveBodyWeight(bodyweight)
        }
        clearPreRetakeProgram()
        persistProfileAndProgram()
        persistOnboarding()
    }

    /// Switch back to the program generated from the user's quiz.
    /// Goes through `setActiveProgram`, so switching away from the
    /// preset waits on confirmation instead of happening silently.
    func useGeneratedProgram() {
        if let generatedProgram {
            setActiveProgram(generatedProgram)
        }
    }

    /// Update the injuries marked on the body diagram (Profile → Body &
    /// injuries). Persists the profile and regenerates the generated
    /// program so the new swaps apply. If the generated program is the
    /// active one it is swapped in place; DaRon's preset is never touched.
    func updateInjuries(parts: Set<BodyPart>, otherText: String) {
        guard var profile else { return }
        profile.injuredParts = parts
        profile.otherLimitText = otherText
        self.profile = profile
        let regenerated = ProgramGenerator.generate(
            profile: profile, customExercises: customExercises,
            preferences: exercisePreferences, equipment: effectiveEquipment)
        let wasGeneratedActive = activeProgram?.id == generatedProgram?.id
        generatedProgram = regenerated
        if wasGeneratedActive { activeProgram = regenerated }
        persistProfileAndProgram()
    }

    /// Make a program the active one. THE choke point for program
    /// switches — every overwrite path funnels through here.
    ///
    /// Preset gate: when DaRon's preset is active, switching to any other
    /// program NEVER happens silently. The requested program is stashed
    /// in `pendingProgramSwitch` and the preset stays active until the
    /// user confirms (`confirmPendingProgramSwitch`) or cancels
    /// (`cancelPendingProgramSwitch`) — the Programs screen presents that
    /// choice. Switching TO the preset is always immediate (restoring it
    /// needs no confirmation).
    func setActiveProgram(_ program: UserProgram) {
        if isPresetActive, program.id != Program.daronPreset.id {
            pendingProgramSwitch = program
            return
        }
        activeProgram = program
        persistProfileAndProgram()
    }

    /// Confirm a stashed program switch (see `setActiveProgram`).
    func confirmPendingProgramSwitch() {
        guard let program = pendingProgramSwitch else { return }
        pendingProgramSwitch = nil
        activeProgram = program
        persistProfileAndProgram()
    }

    /// Cancel a stashed program switch. The preset stays active.
    func cancelPendingProgramSwitch() {
        pendingProgramSwitch = nil
    }

    func addExtraProgram(_ program: UserProgram) {
        extraPrograms.append(program)
        persistCustomization()
    }

    /// Free tier: one extra program (the paywall's "2 programs": the
    /// generated program + one extra). Pro: unlimited. Same gate the
    /// catalog "Use this program" button and Duplicate already use.
    func canAddExtraProgram(isPro: Bool) -> Bool {
        isPro || extraPrograms.isEmpty
    }

    /// Replace an extra program in place (the builder's edit save):
    /// same id, new content. The active program follows if it was the
    /// one edited. A no-op when the id isn't an extra.
    func updateExtraProgram(_ program: UserProgram) {
        guard let index = extraPrograms.firstIndex(where: { $0.id == program.id }) else { return }
        extraPrograms[index] = program
        if activeProgram?.id == program.id { activeProgram = program }
        persistProfileAndProgram()
        persistCustomization()
    }

    // MARK: - Favorites (on-device only)

    /// On-disk shape for favorites (sets encode as arrays, sorted so
    /// the stored JSON is stable).
    private struct FavoriteIDs: Codable {
        var programs: [String] = []
        var exercises: [String] = []
    }

    func isFavoriteProgram(_ id: String) -> Bool { favoriteProgramIDs.contains(id) }
    func isFavoriteExercise(_ id: String) -> Bool { favoriteExerciseIDs.contains(id) }

    func toggleFavoriteProgram(_ id: String) {
        if favoriteProgramIDs.contains(id) { favoriteProgramIDs.remove(id) }
        else { favoriteProgramIDs.insert(id) }
        persistCustomization()
    }

    func toggleFavoriteExercise(_ id: String) {
        if favoriteExerciseIDs.contains(id) { favoriteExerciseIDs.remove(id) }
        else { favoriteExerciseIDs.insert(id) }
        persistCustomization()
    }

    func duplicateProgram(_ program: UserProgram) -> UserProgram {
        let copy = UserProgram(
            id: UUID().uuidString,
            name: program.name + " (copy)",
            days: program.days,
            swaps: program.swaps,
            isPreset: false
        )
        extraPrograms.append(copy)
        persistCustomization()
        return copy
    }

    func renameProgram(_ program: UserProgram, to name: String) {
        if program.id == generatedProgram?.id {
            generatedProgram?.name = name
            if activeProgram?.id == program.id { activeProgram?.name = name }
        } else if let index = extraPrograms.firstIndex(where: { $0.id == program.id }) {
            extraPrograms[index].name = name
            if activeProgram?.id == program.id { activeProgram?.name = name }
        }
        persistProfileAndProgram()
        persistCustomization()
    }

    func deleteExtraProgram(id: String) {
        extraPrograms.removeAll { $0.id == id }
        if activeProgram?.id == id {
            // Fall back to DaRon's preset when this device is unlocked
            // for it — the store must never be left with no program when
            // a known-good one exists. Otherwise the generated program;
            // if there is none, Today shows its rest-day view until the
            // user picks a program.
            activeProgram = isDaronPresetUnlocked ? Program.daronPreset : generatedProgram
        }
        persistProfileAndProgram()
        persistCustomization()
    }

    /// Start the setup flow again from Profile. The privacy screen does not
    /// reappear (hasSeenPrivacy stays true). Snapshots the program that was
    /// active before the retake, so finishing the retake can offer "Keep
    /// my current program" instead of silently overwriting it. Any
    /// unresolved pending switch/decision from an earlier retake is
    /// dropped — the new retake starts clean.
    func resetOnboarding() {
        preRetakeProgram = activeProgram
        persistPreRetakeProgram()
        pendingProgramSwitch = nil
        pendingOnboarding = nil
        hasCompletedOnboarding = false
        persistOnboarding()
    }

    /// Clear the pre-retake snapshot (the retake finished or was
    /// abandoned by claiming the preset).
    private func clearPreRetakeProgram() {
        preRetakeProgram = nil
        SharedDefaults.store.removeObject(forKey: preRetakeProgramKey)
    }

    private func persistPreRetakeProgram() {
        if let preRetakeProgram, let data = try? JSONEncoder().encode(preRetakeProgram) {
            SharedDefaults.store.set(data, forKey: preRetakeProgramKey)
        } else {
            SharedDefaults.store.removeObject(forKey: preRetakeProgramKey)
        }
    }

    /// Claim DaRon's 5-day split on HIS device only. Sets the active
    /// program to the preset, marks the device unlocked (so the preset
    /// joins `allPrograms` and the Welcome card offers it on a retake),
    /// and clears a stale draft for today so the old program's weights
    /// (e.g. a catalog 130 lb lat pulldown) can never linger under the
    /// preset's day. A draft already built from the preset's today plan
    /// — real work in progress — is kept.
    ///
    /// Also completes onboarding when it hasn't finished: claiming the
    /// preset IS finishing setup with a program, so the Welcome claim
    /// card lands straight on Today instead of dropping the user back
    /// into the quiz (which would then overwrite the preset). Never
    /// called for other users — the only callers are the gated Welcome
    /// card and the Profile/Settings restore buttons (all shown only once
    /// the device is already unlocked).
    func restoreDaronPreset() {
        SharedDefaults.store.set(true, forKey: Self.daronPresetUnlockKey)
        isDaronPresetUnlocked = true
        pendingProgramSwitch = nil
        pendingOnboarding = nil
        clearPreRetakeProgram()
        activeProgram = Program.daronPreset
        if let key = Program.dayKey(for: Date()),
           let todayPlan = Program.daronPreset.day(forKey: key) {
            let draftIsToday = draftDayKey == key
                && (draftDate.map { Calendar.current.isDateInToday($0) } ?? false)
            if draftIsToday,
               draftSourcePlan?.exercises.map(\.id) != todayPlan.exercises.map(\.id) {
                clearDraft()
            }
        }
        if !hasCompletedOnboarding {
            hasCompletedOnboarding = true
            stampSetupDate()
        }
        persistProfileAndProgram()
        persistOnboarding()
    }

    /// Today's plan from the active program (generated or preset),
    /// with the user's marked injuries applied (see
    /// `adaptedActiveProgram`). Nil on a rest day or when no program
    /// is set yet.
    func programDay(for date: Date) -> DayPlan? {
        guard let key = Program.dayKey(for: date) else { return nil }
        return adaptedActiveProgram?.day(forKey: key)
    }

    /// Whether a date has a workout scheduled in the active program.
    /// A rest day (no plan) is never scheduled.
    func isScheduledWorkout(on date: Date) -> Bool {
        programDay(for: date) != nil
    }

    /// Whether any session was logged on a date, whatever the plan was.
    /// A session logged on a rest day still counts as completed that day.
    func isCompletedWorkout(on date: Date) -> Bool {
        sessions.contains { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    /// Whether a date is a MISSED workout (calendar rule, DaRon 2026-11-10):
    /// missed(date) = scheduled(date) AND NOT completed(date) AND past(date).
    /// A day with NO scheduled workout (rest day, unscheduled day) is NEVER
    /// missed, whatever its completion state — it is neutral, with no missed
    /// marker and no penalty in any count. Today and future days are never
    /// missed either: a planned workout can only be missed once its day has
    /// passed. This is the ONE definition every screen uses — the calendar
    /// dots, the day detail, and the missed-day nudge all agree with it
    /// (the nudge already gates on a scheduled yesterday; the calendar dots
    /// already encode session==nil && hasPlan && isPast).
    func isMissedWorkout(on date: Date) -> Bool {
        guard isScheduledWorkout(on: date), !isCompletedWorkout(on: date) else { return false }
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }

    /// The missed workout dates in the current week. Rest days never appear
    /// here; future days never appear here — only past scheduled days with
    /// no logged session. The single source for any missed count.
    func missedWorkoutsThisWeek() -> [Date] {
        let start = weekStartDate(for: Date())
        var missed: [Date] = []
        for offset in 0..<7 {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: start) else { continue }
            if isMissedWorkout(on: day) { missed.append(day) }
        }
        return missed
    }

    func nextWorkout(after date: Date) -> (key: String, plan: DayPlan, date: Date)? {
        var candidate = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        for _ in 0..<7 {
            if let key = Program.dayKey(for: candidate),
               let plan = adaptedActiveProgram?.day(forKey: key) {
                return (key, plan, candidate)
            }
            candidate = Calendar.current.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return nil
    }

    /// A user from before onboarding existed has saved workouts, a bodyweight,
    /// or an in-progress draft — but no onboarding flag. Adopt them: keep
    /// their program (DaRon's split, the only program the old build had) and
    /// never show them the intro flow. This can only fire for a device that
    /// ran the pre-onboarding build (DaRon's own device); a fresh install
    /// has no saved data, so no new user is ever given his split here.
    private func adoptReturningUserIfNeeded() {
        guard !hasCompletedOnboarding else { return }
        let hasExistingData = !sessions.isEmpty || bodyWeightLb != nil || draftDayKey != nil
        guard hasExistingData else { return }
        // This device ran the pre-onboarding build — that is DaRon's
        // device by definition — so unlock the preset here too, not just
        // activate it: the restore stays offered on a retake.
        SharedDefaults.store.set(true, forKey: Self.daronPresetUnlockKey)
        isDaronPresetUnlocked = true
        activeProgram = Program.daronPreset
        hasCompletedOnboarding = true
        stampSetupDate()
        persistProfileAndProgram()
        persistOnboarding()
    }

    private func persistProfileAndProgram() {
        if let profile, let data = try? JSONEncoder().encode(profile) {
            SharedDefaults.store.set(data, forKey: profileKey)
        } else if profile == nil {
            SharedDefaults.store.removeObject(forKey: profileKey)
        }
        if let activeProgram, let data = try? JSONEncoder().encode(activeProgram) {
            SharedDefaults.store.set(data, forKey: programKey)
        } else {
            SharedDefaults.store.removeObject(forKey: programKey)
        }
        if let generatedProgram, let data = try? JSONEncoder().encode(generatedProgram) {
            SharedDefaults.store.set(data, forKey: generatedKey)
        } else {
            SharedDefaults.store.removeObject(forKey: generatedKey)
        }
    }

    private func persistOnboarding() {
        SharedDefaults.store.set(hasCompletedOnboarding, forKey: onboardingKey)
        SharedDefaults.store.set(hasSeenPrivacy, forKey: privacyKey)
    }

    /// Record the account-creation date — the moment the user first
    /// sets up the app. Once-only: an existing stamp is never moved,
    /// so retaking setup keeps the original creation date. Called at
    /// onboarding completion and at adoption. Never backfilled from
    /// session history (a user can create the account before their
    /// first logged workout).
    private func stampSetupDate() {
        guard setupDate == nil else { return }
        setupDate = Date()
        persistSetupDate()
    }

    /// Legacy onboarded users (onboarding completed before this key
    /// existed) have no stamp yet. Record one at first launch of a
    /// build that tracks it — the first moment the app can verify the
    /// account exists — so the calendar still has a bound.
    private func ensureSetupDate() {
        guard setupDate == nil, hasCompletedOnboarding else { return }
        stampSetupDate()
    }

    private func persistSetupDate() {
        if let setupDate {
            SharedDefaults.store.set(setupDate.timeIntervalSince1970, forKey: setupDateKey)
        } else {
            SharedDefaults.store.removeObject(forKey: setupDateKey)
        }
    }

    private func loadProfileAndProgram() {
        if let data = SharedDefaults.store.data(forKey: profileKey),
           let decoded = SafeDecode.value(UserProfile.self, from: data, key: profileKey) {
            profile = decoded
        }
        if let data = SharedDefaults.store.data(forKey: programKey),
           let decoded = SafeDecode.value(UserProgram.self, from: data, key: programKey) {
            activeProgram = decoded
        }
        if let data = SharedDefaults.store.data(forKey: generatedKey),
           let decoded = SafeDecode.value(UserProgram.self, from: data, key: generatedKey) {
            generatedProgram = decoded
        }
        hasCompletedOnboarding = SharedDefaults.store.bool(forKey: onboardingKey)
        isDaronPresetUnlocked = SharedDefaults.store.bool(forKey: Self.daronPresetUnlockKey)
        if let data = SharedDefaults.store.data(forKey: preRetakeProgramKey),
           let decoded = SafeDecode.value(UserProgram.self, from: data, key: preRetakeProgramKey) {
            preRetakeProgram = decoded
        }
        let storedSetup = SharedDefaults.store.double(forKey: setupDateKey)
        setupDate = storedSetup > 0 ? Date(timeIntervalSince1970: storedSetup) : nil
        hasSeenPrivacy = SharedDefaults.store.bool(forKey: privacyKey)
    }

    /// Mark the one-time privacy screen as seen so it never appears again.
    func markPrivacySeen() {
        hasSeenPrivacy = true
        persistOnboarding()
    }

    // MARK: - Customization persistence

    func persistCustomization() {
        if let data = try? JSONEncoder().encode(customExercises) {
            SharedDefaults.store.set(data, forKey: customExercisesKey)
        }
        if let data = try? JSONEncoder().encode(exercisePreferences) {
            SharedDefaults.store.set(data, forKey: preferencesKey)
        }
        if let data = try? JSONEncoder().encode(gymProfiles) {
            SharedDefaults.store.set(data, forKey: gymProfilesKey)
        }
        if let id = activeGymProfileID {
            SharedDefaults.store.set(id, forKey: activeGymProfileKey)
        } else {
            SharedDefaults.store.removeObject(forKey: activeGymProfileKey)
        }
        if let data = try? JSONEncoder().encode(settings) {
            SharedDefaults.store.set(data, forKey: settingsKey)
        }
        if let data = try? JSONEncoder().encode(extraPrograms) {
            SharedDefaults.store.set(data, forKey: extraProgramsKey)
        }
        if let data = try? JSONEncoder().encode(FavoriteIDs(programs: favoriteProgramIDs.sorted(),
                                                           exercises: favoriteExerciseIDs.sorted())) {
            SharedDefaults.store.set(data, forKey: favoritesKey)
        }
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        persistCustomization()
        // A mid-rest accent change recolours the Live Activity.
        syncRestLiveActivity()
    }

    private func loadCustomization() {
        if let data = SharedDefaults.store.data(forKey: customExercisesKey),
           let decoded = SafeDecode.array(CustomExercise.self, from: data, key: customExercisesKey) {
            customExercises = decoded
        }
        if let data = SharedDefaults.store.data(forKey: preferencesKey),
           let decoded = SafeDecode.value([String: ExercisePreference].self, from: data, key: preferencesKey) {
            exercisePreferences = decoded
        }
        if let data = SharedDefaults.store.data(forKey: gymProfilesKey),
           let decoded = SafeDecode.array(GymProfile.self, from: data, key: gymProfilesKey) {
            gymProfiles = decoded
        }
        activeGymProfileID = SharedDefaults.store.string(forKey: activeGymProfileKey)
        if let data = SharedDefaults.store.data(forKey: settingsKey),
           let decoded = SafeDecode.value(AppSettings.self, from: data, key: settingsKey) {
            settings = decoded
            // Appearance follows the system (Nov 12: "app should respect
            // all system settings"). The Nov 9 OLED migration forced every
            // Auto to Dark on every launch, so a stored Dark was never a
            // real choice: turn it back to Auto once. A Light choice, or a
            // Dark picked after this, is kept.
            let followsSystemKey = "gymtracker.themeFollowsSystem.v1"
            if !SharedDefaults.store.bool(forKey: followsSystemKey) {
                if settings.colorScheme == .dark {
                    settings.colorScheme = .auto
                    persistCustomization()
                }
                SharedDefaults.store.set(true, forKey: followsSystemKey)
            }
        }
        if let data = SharedDefaults.store.data(forKey: extraProgramsKey),
           let decoded = SafeDecode.array(UserProgram.self, from: data, key: extraProgramsKey) {
            extraPrograms = decoded
        }
        if let data = SharedDefaults.store.data(forKey: favoritesKey),
           let decoded = SafeDecode.value(FavoriteIDs.self, from: data, key: favoritesKey) {
            favoriteProgramIDs = Set(decoded.programs)
            favoriteExerciseIDs = Set(decoded.exercises)
        }
    }

    // MARK: - Draft session (autosaved in-progress workout)

    /// Make sure a draft exists for today's plan. Keeps an in-progress draft
    /// for today (so fold/unfold and app restarts lose nothing); starts a
    /// fresh one when the day or plan changes.
    func ensureDraft(for plan: DayPlan) {
        if draftDayKey == plan.key,
           let draftDate, Calendar.current.isDateInToday(draftDate) {
            // Same weekday, same day — but the PLAN may have changed
            // under the same key (dayKey is only the weekday: a
            // legs→push swap and back leaves the key as "Mon"). Compare
            // the draft's source plan against the current plan's
            // exercise set, not the key.
            let planIDs = plan.exercises.map(\.id)
            if let sourcePlan = draftSourcePlan,
               sourcePlan.exercises.map(\.id) != planIDs {
                // The underlying plan changed mid-day.
                let anyDone = draftLogs.values.flatMap { $0 }.contains { $0.done }
                if anyDone {
                    // Real work is already logged against the old plan —
                    // keep the draft exactly as it is (the workout being
                    // done is the draft's, not the new plan's) and let
                    // saving use the draft's source plan for its title.
                    return
                }
                // Nothing logged yet: fall through to the fresh branch
                // below and rebuild the draft from the new plan.
            } else {
                // Keep the in-progress draft; fill in any exercise the plan
                // gained since the draft was created.
                var updated = draftLogs
                var changed = false
                for template in plan.exercises where updated[template.id] == nil {
                    let next = nextWeightAndReps(for: template)
                    updated[template.id] = (0..<template.sets).map { _ in
                        SetLog(weightLb: next.weightLb, reps: next.reps, done: false)
                    }
                    changed = true
                }
                if changed { draftLogs = updated }
                if draftFinisherChecks.count != plan.finisher.count {
                    // Preserve already-ticked finisher checks by index
                    // (a plan change must not un-tick finished work).
                    let kept = draftFinisherChecks
                    draftFinisherChecks = plan.finisher.indices.map { kept.indices.contains($0) ? kept[$0] : false }
                }
                if draftExercises.isEmpty {
                    draftExercises = plan.exercises
                }
                if draftSourcePlan == nil {
                    draftSourcePlan = plan
                }
                return
            }
        }
        var fresh: [String: [SetLog]] = [:]
        for template in plan.exercises {
            let next = nextWeightAndReps(for: template)
            fresh[template.id] = (0..<template.sets).map { _ in
                SetLog(weightLb: next.weightLb, reps: next.reps, done: false)
            }
        }
        draftDayKey = plan.key
        draftDate = Date()
        draftLogs = fresh
        draftFinisherChecks = plan.finisher.map { _ in false }
        draftExercises = plan.exercises
        draftSourcePlan = plan
        draftSessionMod = nil
        draftNotes = [:]
        draftNoteTimes = [:]
    }

    /// Reorder / add / remove / swap mid-workout (Hevy pattern). Mutates only
    /// today's draft — the saved program is untouched.
    func moveDraftExercise(from source: IndexSet, to destination: Int) {
        draftExercises.move(fromOffsets: source, toOffset: destination)
    }

    func removeDraftExercise(id: String) {
        draftExercises.removeAll { $0.id == id }
        draftLogs.removeValue(forKey: id)
        draftNotes.removeValue(forKey: id)
        draftNoteTimes.removeValue(forKey: id)
    }

    func addDraftExercise(_ template: ExerciseTemplate) {
        guard !draftExercises.contains(where: { $0.id == template.id }) else { return }
        draftExercises.append(template)
        let next = nextWeightAndReps(for: template)
        draftLogs[template.id] = (0..<template.sets).map { _ in
            SetLog(weightLb: next.weightLb, reps: next.reps, done: false)
        }
    }

    func swapDraftExercise(id: String, with template: ExerciseTemplate) {
        guard let index = draftExercises.firstIndex(where: { $0.id == id }) else { return }
        draftLogs.removeValue(forKey: id)
        draftExercises[index] = template
        let next = nextWeightAndReps(for: template)
        draftLogs[template.id] = (0..<template.sets).map { _ in
            SetLog(weightLb: next.weightLb, reps: next.reps, done: false)
        }
    }

    func addSet(to template: ExerciseTemplate) {
        var sets = draftLogs[template.id] ?? []
        let last = sets.last
        sets.append(SetLog(weightLb: last?.weightLb ?? template.defaultWeightLb,
                           reps: last?.reps ?? template.topReps, done: false))
        draftLogs[template.id] = sets
    }

    func removeSet(at index: Int, for template: ExerciseTemplate) {
        var sets = draftLogs[template.id] ?? []
        guard sets.indices.contains(index), sets.count > 1 else { return }
        sets.remove(at: index)
        draftLogs[template.id] = sets
    }

    func clearDraft() {
        draftDayKey = nil
        draftDate = nil
        draftLogs = [:]
        draftFinisherChecks = []
        draftExercises = []
        draftSourcePlan = nil
        draftSessionMod = nil
        draftNotes = [:]
        draftNoteTimes = [:]
        restEndsAt = nil
        restPausedRemaining = nil
        restTemplateID = nil
        liveActivitySelectedExerciseID = nil
    }

    private func persistDraft() {
        guard let dayKey = draftDayKey, let date = draftDate else {
            SharedDefaults.store.removeObject(forKey: draftKey)
            return
        }
        let draft = DraftSession(dayKey: dayKey, date: date, logs: draftLogs,
                                 finisherChecks: draftFinisherChecks,
                                 templates: draftExercises,
                                 sessionMod: draftSessionMod, notes: draftNotes,
                                 noteTimes: draftNoteTimes, sourcePlan: draftSourcePlan)
        if let data = try? JSONEncoder().encode(draft) {
            SharedDefaults.store.set(data, forKey: draftKey)
        }
    }

    private func loadDraft() {
        guard let data = SharedDefaults.store.data(forKey: draftKey),
              let draft = try? JSONDecoder().decode(DraftSession.self, from: data),
              Calendar.current.isDateInToday(draft.date) else {
            return
        }
        draftDayKey = draft.dayKey
        draftDate = draft.date
        draftLogs = draft.logs
        draftFinisherChecks = draft.finisherChecks
        draftExercises = draft.templates
        draftSourcePlan = draft.sourcePlan
        draftSessionMod = draft.sessionMod
        draftNotes = draft.notes
        draftNoteTimes = draft.noteTimes
    }

    // MARK: - Rest timer (custom default + per-exercise override)

    /// Rest length for an exercise: its override, else the global default.
    func restSeconds(for template: ExerciseTemplate? = nil) -> TimeInterval {
        template?.restSeconds ?? settings.restSecondsDefault
    }

    /// Start (or restart) the rest countdown when a working set is marked done.
    func startRest(for template: ExerciseTemplate? = nil) {
        // A new rest supersedes any flash still running from the last
        // one — never leave a stale STATUS sequence going. (Hop to the
        // main actor: WorkoutStore isn't @MainActor, FlashlightSignal is.)
        Task { @MainActor in FlashlightSignal.shared.cancel() }
        // Template first: the restEndsAt didSet fires the Live Activity
        // sync, which reads the template for the exercise name.
        restTemplateID = template?.id
        // A new rest belongs to this exercise — drop any lock-screen
        // "Next" override so the activity follows the new rest.
        liveActivitySelectedExerciseID = nil
        restPausedRemaining = nil
        restEndsAt = Date().addingTimeInterval(restSeconds(for: template))
    }

    func adjustRest(by seconds: TimeInterval) {
        if let paused = restPausedRemaining {
            restPausedRemaining = max(0, paused + seconds)
            // A paused adjust doesn't touch restEndsAt, so its didSet
            // never fires — sync explicitly.
            syncRestLiveActivity()
            return
        }
        guard let endsAt = restEndsAt else { return }
        restEndsAt = endsAt.addingTimeInterval(seconds)
    }

    /// Freeze the countdown. Tap again (resumeRest) to keep counting down
    /// from where it stopped.
    func pauseRest() {
        guard let endsAt = restEndsAt else { return }
        restPausedRemaining = max(0, endsAt.timeIntervalSinceNow)
        restEndsAt = nil
    }

    /// Resume a paused countdown from where it stopped.
    func resumeRest() {
        guard let remaining = restPausedRemaining else { return }
        restPausedRemaining = nil
        restEndsAt = Date().addingTimeInterval(remaining)
    }

    func cancelRest() {
        // Stopping the rest stops its flash too (main-actor hop — see startRest).
        Task { @MainActor in FlashlightSignal.shared.cancel() }
        restEndsAt = nil
        restPausedRemaining = nil
        restTemplateID = nil
        liveActivitySelectedExerciseID = nil
    }

    /// Flash "STATUS" in Morse on the torch, ONCE, when a rest ends.
    /// Called from the rest timer's completion point (RestTimerCard in
    /// TodayView, alongside the existing sound/haptic feedback) — the
    /// completion itself lives there, this is just the callable hook.
    /// Additive only: it never replaces sound, haptic, or the Live
    /// Activity. No-ops when the toggle is off, when camera access was
    /// denied, when the app is in the background, or when the device
    /// has no torch (simulator, iPad).
    func flashRestCompleteSignalIfEnabled() {
        guard settings.restFlashlightEnabled else { return }
        Task { @MainActor in
            FlashlightSignal.shared.flash(word: FlashlightSignal.statusWord)
        }
    }

    /// Restore a rest timer that was running when the app closed (only if it
    /// hasn't expired yet).
    private func loadRestTimer() {
        let paused = SharedDefaults.store.double(forKey: restPausedKey)
        if paused > 0 {
            restPausedRemaining = paused
        } else {
            let stored = SharedDefaults.store.double(forKey: restEndsAtKey)
            if stored > 0 {
                let endsAt = Date(timeIntervalSince1970: stored)
                if endsAt > Date() {
                    restEndsAt = endsAt
                } else {
                    SharedDefaults.store.removeObject(forKey: restEndsAtKey)
                }
            }
        }
        // The exercise the rest belongs to (and any lock-screen "Next"
        // override) — restored alongside the timer so the Live Activity
        // label is right after a relaunch.
        if let templateID = SharedDefaults.store.string(forKey: restTemplateIDKey) {
            restTemplateID = templateID
        }
        if let selectedID = SharedDefaults.store.string(forKey: liveActivitySelectedExerciseKey) {
            liveActivitySelectedExerciseID = selectedID
        }
    }

    // MARK: - Rest-timer Live Activity (lock screen + Dynamic Island)

    /// Whether the user has Pro. Set by GymTrackerApp from
    /// SubscriptionState — the store never talks to StoreKit itself.
    /// Only affects the Live Activity accent: free users get the vivid
    /// blue, Pro users get their chosen accent color.
    var isPro = false {
        didSet {
            if oldValue != isPro { syncRestLiveActivity() }
        }
    }

    /// The app's effective accent color as "#RRGGBB" — the ONE shared
    /// accent source for the Live Activity (DaRon, 2026-11-09: "same
    /// color as the accent color"). Free users get Theme.accent (the
    /// vivid blue); Pro users get the accent they picked in Settings.
    /// When accent colors become user-interchangeable at the paid tier,
    /// this is where the new choice flows in — the Live Activity just
    /// renders the hex it is handed, no rework in the extension.
    var effectiveAccentHex: String {
        (isPro ? settings.accentColor.color : Theme.accent).hexString
    }

    /// The exercise the Live Activity shows. Normally the exercise the
    /// rest belongs to — but when the user tapped Next on the lock screen
    /// (liveActivitySelectedExerciseID), the activity follows the new
    /// current exercise while the countdown keeps running. The timing
    /// (totalSeconds) still comes from the rest's own exercise.
    private var restDisplayExerciseID: String? {
        liveActivitySelectedExerciseID ?? restTemplateID
    }

    /// The exercise this rest belongs to, for the Live Activity label.
    private var restExerciseName: String {
        guard let displayID = restDisplayExerciseID else { return "Rest" }
        if let draft = draftExercises.first(where: { $0.id == displayID }) {
            return draft.name
        }
        if let lib = ExerciseLibrary.byId(displayID, plus: customExercises) {
            return lib.name
        }
        return "Rest"
    }

    /// Done flags, in order, for the displayed exercise's sets — the
    /// checkboxes the Live Activity draws.
    private var restDisplayExerciseSets: [Bool] {
        guard let displayID = restDisplayExerciseID else { return [] }
        return (draftLogs[displayID] ?? []).map { $0.done }
    }

    /// Name of the exercise after the displayed one in today's plan, or
    /// nil when it is the last — the Live Activity's Next button hides
    /// when nil.
    private var restDisplayNextExerciseName: String? {
        guard let displayID = restDisplayExerciseID,
              let index = draftExercises.firstIndex(where: { $0.id == displayID }),
              draftExercises.indices.contains(index + 1) else { return nil }
        return draftExercises[index + 1].name
    }

    /// Full length of this rest, for the Live Activity's progress text.
    private var restExerciseTotalSeconds: TimeInterval {
        if let restTemplateID,
           let draft = draftExercises.first(where: { $0.id == restTemplateID }) {
            return restSeconds(for: draft)
        }
        return settings.restSecondsDefault
    }

    /// The running rest-timer Live Activity, while one exists.
    private var restLiveActivity: Activity<RestTimerAttributes>?

    /// Coalescing task for activity sync: rapid state churn (pause then
    /// resume, or the didSet + explicit call pair) collapses into one
    /// system call, and cancelling the previous task keeps only the
    /// latest state from ever reaching the system.
    private var restLiveActivityTask: Task<Void, Never>?

    /// Reconcile the Live Activity with the current rest state. Called
    /// from `restEndsAt`'s didSet (start / pause / resume / cancel /
    /// expiry / Siri), from `adjustRest` (a paused adjust doesn't touch
    /// `restEndsAt`), from `updateSettings` (accent change mid-rest),
    /// from `isPro`'s didSet, and once at launch. Safe to call any time:
    /// it no-ops when Live Activities are off, ends a stale activity
    /// when no rest is running, and never throws into the UI.
    func syncRestLiveActivity() {
        restLiveActivityTask?.cancel()
        restLiveActivityTask = Task { [weak self] in
            try? await Task.sleep(for: .nanoseconds(50_000_000))
            guard !Task.isCancelled else { return }
            await self?.applyRestLiveActivity()
        }
    }

    /// One sync step: build the current state from the store and either
    /// start, update, or end the activity.
    private func applyRestLiveActivity() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let remaining = restRemainingSeconds {
            let state = RestTimerAttributes.ContentState(
                exerciseName: restExerciseName,
                endsAt: restEndsAt,
                remainingSeconds: remaining,
                totalSeconds: max(restExerciseTotalSeconds, 1),
                isPaused: isRestPaused,
                accentHex: effectiveAccentHex,
                exerciseId: restDisplayExerciseID ?? "",
                sets: restDisplayExerciseSets,
                nextExerciseName: restDisplayNextExerciseName
            )
            if let activity = restLiveActivity {
                await activity.update(ActivityContent(state: state, staleDate: state.endsAt))
            } else {
                // Sweep any activity left over from a crash/kill first, so
                // there is never more than one rest activity.
                for stale in Activity<RestTimerAttributes>.activities {
                    await stale.end(nil, dismissalPolicy: .immediate)
                }
                do {
                    restLiveActivity = try await Activity<RestTimerAttributes>.request(
                        attributes: RestTimerAttributes(),
                        content: ActivityContent(state: state, staleDate: state.endsAt),
                        pushType: nil)
                } catch {
                    restLiveActivity = nil
                }
            }
        } else if let activity = restLiveActivity {
            await activity.end(nil, dismissalPolicy: .immediate)
            restLiveActivity = nil
        } else {
            // No reference (e.g. after a relaunch) — sweep stale ones.
            for stale in Activity<RestTimerAttributes>.activities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Re-read the draft + rest state from UserDefaults and apply it to
    /// the in-memory store. Called when the app foregrounds (GymTrackerApp
    /// scenePhase .active) and when a Live Activity intent mutates the
    /// draft from the lock screen (Darwin notification
    /// `com.daronbarkley.GymTracker.draftChanged`), so a set checked on
    /// the lock screen shows up in the app without a relaunch. Only
    /// applies state that differs, so a reconcile never clobbers an
    /// in-flight edit the user is making in the app itself (disk and
    /// memory agree in the normal case, so the checks no-op).
    func reconcileFromDefaults() {
        // Draft (only today's — a stale draft from another day is the
        // next launch's problem, not this reconcile's).
        if let data = SharedDefaults.store.data(forKey: draftKey),
           let draft = try? JSONDecoder().decode(DraftSession.self, from: data),
           Calendar.current.isDateInToday(draft.date) {
            if draft.logs != draftLogs { draftLogs = draft.logs }
            if draft.templates != draftExercises { draftExercises = draft.templates }
            if draft.sourcePlan != draftSourcePlan { draftSourcePlan = draft.sourcePlan }
            if draft.dayKey != draftDayKey { draftDayKey = draft.dayKey }
            if draft.date != draftDate { draftDate = draft.date }
            if draft.finisherChecks != draftFinisherChecks { draftFinisherChecks = draft.finisherChecks }
            if draft.sessionMod != draftSessionMod { draftSessionMod = draft.sessionMod }
            if draft.notes != draftNotes { draftNotes = draft.notes }
            if draft.noteTimes != draftNoteTimes { draftNoteTimes = draft.noteTimes }
        }
        // Rest state.
        let paused = SharedDefaults.store.double(forKey: restPausedKey)
        let pausedRemaining: TimeInterval? = paused > 0 ? paused : nil
        if pausedRemaining != restPausedRemaining { restPausedRemaining = pausedRemaining }
        let storedEnds = SharedDefaults.store.double(forKey: restEndsAtKey)
        if storedEnds > 0 {
            let endsAt = Date(timeIntervalSince1970: storedEnds)
            if endsAt > Date() {
                if endsAt != restEndsAt { restEndsAt = endsAt }
            } else {
                // Expired while the app was away — drop the stale key so
                // a later reconcile doesn't keep seeing it.
                SharedDefaults.store.removeObject(forKey: restEndsAtKey)
                if restEndsAt != nil { restEndsAt = nil }
            }
        } else if restEndsAt != nil {
            restEndsAt = nil
        }
        if let templateID = SharedDefaults.store.string(forKey: restTemplateIDKey),
           templateID != restTemplateID {
            restTemplateID = templateID
        }
        // Lock-screen "Next" request (TodayView applies it to the
        // current exercise via its onChange).
        if let nextID = SharedDefaults.store.string(forKey: liveActivitySelectedExerciseKey),
           nextID != liveActivitySelectedExerciseID {
            liveActivitySelectedExerciseID = nextID
        }
        syncRestLiveActivity()
    }

    /// Listen for Live Activity intents mutating state from the lock
    /// screen (set checked / next exercise). The Darwin notification
    /// fires even when the app is suspended; the callback hops to the
    /// main queue because the store's @Published properties are
    /// main-thread state.
    func observeLiveActivityChanges() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let store = Unmanaged<WorkoutStore>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { store.reconcileFromDefaults() }
            },
            LiveActivityDraftKeys.draftChangedNotification as CFString,
            nil,
            .deliverImmediately)
    }

    private func persistSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            SharedDefaults.store.set(data, forKey: sessionsKey)
        }
    }

    private func load() {
        if let data = SharedDefaults.store.data(forKey: sessionsKey),
           let decoded = SafeDecode.array(SessionLog.self, from: data, key: sessionsKey) {
            sessions = decoded.sorted { $0.date > $1.date }
        }
        migrateMislabeledLegsSessionIfNeeded()
        if let data = SharedDefaults.store.data(forKey: userNotesKey),
           let decoded = SafeDecode.array(UserNote.self, from: data, key: userNotesKey) {
            userNotes = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
        if let saved = SharedDefaults.store.stringArray(forKey: noteCategoriesKey), !saved.isEmpty {
            noteCategories = saved
        }
        let stored = SharedDefaults.store.double(forKey: weightKey)
        bodyWeightLb = stored > 0 ? stored : nil
    }
}

// MARK: - Safe persistence

/// Loading that can never cost the user their data.
///
/// Every blob is JSON in the App Group `UserDefaults`. A plain
/// `try? JSONDecoder().decode` silently returns nil when *anything* in the
/// blob fails to decode (one malformed session, or a field added in a later
/// version), the store starts empty, and the next save overwrites the only
/// copy. Instead:
/// - arrays keep every element that still decodes and drop only the bad ones;
/// - whenever anything is dropped, the original bytes are first copied to a
///   backup key (`<key>.unreadable.<unix time>`, listed under
///   `gymtracker.unreadableBackups`) so they can be recovered by a later fix.
enum SafeDecode {
    private static let backupIndexKey = "gymtracker.unreadableBackups"

    static func array<T: Decodable>(_ type: T.Type, from data: Data, key: String) -> [T]? {
        if let all = try? JSONDecoder().decode([T].self, from: data) { return all }
        backUp(data, forKey: key)
        guard let items = try? JSONDecoder().decode([LossyElement<T>].self, from: data) else { return nil }
        return items.compactMap(\.value)
    }

    static func value<T: Decodable>(_ type: T.Type, from data: Data, key: String) -> T? {
        if let value = try? JSONDecoder().decode(T.self, from: data) { return value }
        backUp(data, forKey: key)
        return nil
    }

    /// Copy unreadable bytes aside. Skips the copy when the newest backup for
    /// this key already holds the same bytes, so a blob that stays unreadable
    /// across launches is backed up once, not on every launch.
    private static func backUp(_ data: Data, forKey key: String) {
        let store = SharedDefaults.store
        var index = store.stringArray(forKey: backupIndexKey) ?? []
        if let latest = index.last(where: { $0.hasPrefix(key + ".unreadable.") }),
           store.data(forKey: latest) == data {
            return
        }
        let backupKey = "\(key).unreadable.\(Int(Date().timeIntervalSince1970))"
        store.set(data, forKey: backupKey)
        index.append(backupKey)
        store.set(index, forKey: backupIndexKey)
    }
}

/// Decodes one array element, yielding nil instead of failing the whole array.
private struct LossyElement<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? decoder.singleValueContainer().decode(T.self)
    }
}

// MARK: - Formatting helpers

/// Format a stored lb weight in a given unit (for History / Profile rows).
func weightLabel(_ weightLb: Double?, isPair: Bool, unit: WeightUnit) -> String {
    guard let display = unit.displayValue(for: weightLb), display > 0 else { return "Set weight" }
    if display == display.rounded() {
        return isPair ? "\(Int(display))s" : "\(Int(display)) \(unit.label)"
    }
    return isPair ? "\(roundedWeightText(display))s" : "\(roundedWeightText(display)) \(unit.label)"
}
