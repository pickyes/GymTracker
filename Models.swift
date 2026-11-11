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

    init(dayKey: String, date: Date, logs: [String: [SetLog]], finisherChecks: [Bool],
         templates: [ExerciseTemplate] = [], sessionMod: SessionMod? = nil, notes: [String: String] = [:],
         noteTimes: [String: Date] = [:]) {
        self.dayKey = dayKey
        self.date = date
        self.logs = logs
        self.finisherChecks = finisherChecks
        self.templates = templates
        self.sessionMod = sessionMod
        self.notes = notes
        self.noteTimes = noteTimes
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
    }

    private enum CodingKeys: String, CodingKey {
        case dayKey, date, logs, finisherChecks, templates, sessionMod, notes, noteTimes
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
}

struct DayPlan: Identifiable, Codable, Equatable {
    var key: String
    var title: String
    var subtitle: String
    var exercises: [ExerciseTemplate]
    var finisher: [String]
    var id: String { key }

    /// Estimated session length in minutes (Fitbod / Leap weekly-plan pattern).
    var estimatedMinutes: Int {
        // ~2 min per set (lift + rest) + 5 min finisher + 5 min warm-up.
        let setCount = exercises.reduce(0) { $0 + $1.sets }
        return max(15, setCount * 2 + 10)
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
        case .getLean: return "10–15 reps, finisher every session"
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
}

struct AppSettings: Codable, Equatable {
    // Rest timer
    var restSecondsDefault: TimeInterval = 90
    var restSoundEnabled: Bool = true
    var restHapticEnabled: Bool = true
    // Units
    var weightUnit: WeightUnit = .lb
    // Comfort
    var hapticsEnabled: Bool = true
    var keepScreenAwake: Bool = false
    // Appearance — theme is free for everyone; accent colors are Pro.
    // Default is OLED dark (DaRon, 2026-11-09).
    var colorScheme: ColorSchemeSetting = .dark
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

func estimatedOneRepMax(weightLb: Double, reps: Int) -> Double {
    guard weightLb > 0, reps > 0 else { return 0 }
    if reps == 1 { return weightLb }
    return weightLb * (1 + Double(reps) / 30.0)
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
/// Returns (weight, reps) pairs, light to heavy.
func warmUpSets(for workingWeightLb: Double) -> [(weightLb: Double, reps: Int)] {
    guard workingWeightLb > 0 else { return [] }
    let bar = 45.0
    var sets: [(Double, Int)] = []
    let w1 = max(bar, (workingWeightLb * 0.4 / 5).rounded() * 5)
    let w2 = max(bar, (workingWeightLb * 0.6 / 5).rounded() * 5)
    let w3 = max(bar, (workingWeightLb * 0.8 / 5).rounded() * 5)
    sets.append((w1, 5))
    if w2 > w1 { sets.append((w2, 3)) }
    if w3 > w2 { sets.append((w3, 1)) }
    return sets
}

// MARK: - Store

final class WorkoutStore: ObservableObject {
    @Published var sessions: [SessionLog] = []
    /// User notes for the Notes page: workout notes saved from the
    /// per-exercise note field on Today, plus free notes written on
    /// the Notes page. On-device only.
    @Published var userNotes: [UserNote] = []
    @Published var bodyWeightLb: Double?

    // MARK: - Onboarding + program (on-device only)

    /// The user's setup answers. Nil until they finish the quiz (or skip it).
    @Published var profile: UserProfile?
    /// The program Today renders: the user's active program.
    @Published var activeProgram: UserProgram?
    /// The program generated from the user's quiz, kept so they can switch
    /// back to it.
    @Published var generatedProgram: UserProgram?
    /// Extra user-created programs (Pro: unlimited; free: none beyond the generated program).
    @Published var extraPrograms: [UserProgram] = []
    /// First-launch gate. False until onboarding completes (or a returning
    /// user from before onboarding is adopted — see init).
    @Published var hasCompletedOnboarding: Bool = false
    /// The one-time privacy screen. Once seen it never appears again.
    @Published var hasSeenPrivacy: Bool = false
    /// Cold-start greeting: true when the app just cold-started (the
    /// loading screen showed) and the Today title should greet the user
    /// ("Hi DaRon") for 5 seconds before becoming "Today". Set by
    /// GymTrackerApp when the loading screen dismisses; cleared by
    /// TodayView once the greeting starts, so it only ever fires once
    /// per cold start. Not persisted — a fresh process starts false.
    @Published var showColdStartGreeting = false

    // MARK: - Customization (on-device only)

    @Published var customExercises: [CustomExercise] = []
    @Published var exercisePreferences: [String: ExercisePreference] = [:]
    @Published var gymProfiles: [GymProfile] = []
    @Published var activeGymProfileID: String?
    @Published var settings: AppSettings = .default

    /// All programs the user can switch between: generated + extras.
    /// DaRon's personal split is NOT in this list — it is never offered
    /// to other users. (His own device keeps it as the active program;
    /// that stored program is untouched by this list.)
    var allPrograms: [UserProgram] {
        var list: [UserProgram] = []
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
                UserDefaults.standard.set(restEndsAt.timeIntervalSince1970, forKey: restEndsAtKey)
            } else {
                UserDefaults.standard.removeObject(forKey: restEndsAtKey)
            }
            // Keep the lock screen / Dynamic Island Live Activity in step:
            // start, pause, resume, stop and expiry all flow through here
            // (expiry and the Siri intent set this directly).
            syncRestLiveActivity()
        }
    }
    @Published var restTemplateID: String?
    /// When the rest timer is PAUSED, this holds the remaining seconds
    /// and `restEndsAt` is nil. Persisted like `restEndsAt` so a pause
    /// survives an app restart. Nil when the timer is running or stopped.
    @Published var restPausedRemaining: TimeInterval? {
        didSet {
            if let restPausedRemaining {
                UserDefaults.standard.set(restPausedRemaining, forKey: restPausedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: restPausedKey)
            }
        }
    }

    /// True while the rest timer is paused (countdown frozen).
    var isRestPaused: Bool { restPausedRemaining != nil }

    /// Seconds left on the rest timer, whether running or paused.
    var restRemainingSeconds: TimeInterval? {
        if let restPausedRemaining { return restPausedRemaining }
        guard let restEndsAt else { return nil }
        return max(0, restEndsAt.timeIntervalSinceNow)
    }

    private let restEndsAtKey = "gymtracker.restEndsAt.v1"
    private let restPausedKey = "gymtracker.restPaused.v1"

    private let sessionsKey = "gymtracker.sessions.v1"
    private let userNotesKey = "gymtracker.userNotes.v1"
    private let weightKey = "gymtracker.bodyweight.v1"
    private let draftKey = "gymtracker.draft.v1"
    private let profileKey = "gymtracker.profile.v1"
    private let programKey = "gymtracker.program.v1"
    private let generatedKey = "gymtracker.generated.v1"
    private let onboardingKey = "gymtracker.onboarding.v1"
    private let privacyKey = "gymtracker.privacy.v1"
    private let customExercisesKey = "gymtracker.customExercises.v1"
    private let preferencesKey = "gymtracker.exercisePreferences.v1"
    private let gymProfilesKey = "gymtracker.gymProfiles.v1"
    private let activeGymProfileKey = "gymtracker.activeGymProfile.v1"
    private let settingsKey = "gymtracker.settings.v1"
    private let extraProgramsKey = "gymtracker.extraPrograms.v1"

    init() {
        load()
        loadDraft()
        loadProfileAndProgram()
        loadCustomization()
        adoptReturningUserIfNeeded()
        loadRestTimer()
        // Restore the Live Activity if a rest was running/paused when the
        // app closed (loadRestTimer restored it above).
        syncRestLiveActivity()
    }

    // MARK: - Sessions + history helpers

    func saveSession(_ session: SessionLog) {
        sessions.removeAll { $0.id == session.id }
        sessions.append(session)
        sessions.sort { $0.date > $1.date }
        persistSessions()
    }

    // MARK: - Notes

    /// Add a note (workout note or free note). Blank notes are ignored.
    /// Newest first — the note just written is always on top.
    func addUserNote(title: String, body: String, workoutTitle: String? = nil, date: Date = Date()) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty || !trimmedBody.isEmpty else { return }
        let note = UserNote(
            id: UUID(),
            title: trimmedTitle,
            body: trimmedBody,
            createdAt: date,
            updatedAt: date,
            workoutTitle: workoutTitle
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
    func updateUserNote(_ note: UserNote, title: String, body: String) {
        guard let index = userNotes.firstIndex(where: { $0.id == note.id }) else { return }
        var updated = note
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = Date()
        userNotes[index] = updated
        userNotes.sort { $0.updatedAt > $1.updatedAt }
        persistUserNotes()
    }

    func deleteUserNote(id: UUID) {
        userNotes.removeAll { $0.id == id }
        persistUserNotes()
    }

    private func persistUserNotes() {
        if let data = try? JSONEncoder().encode(userNotes) {
            UserDefaults.standard.set(data, forKey: userNotesKey)
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

    /// Estimated 1RM for an exercise from the best set (Epley).
    func oneRepMax(for exerciseId: String) -> Double? {
        guard let best = bestSet(for: exerciseId),
              let weight = best.weightLb else { return nil }
        return estimatedOneRepMax(weightLb: weight, reps: best.reps)
    }

    func progressionHint(for template: ExerciseTemplate) -> String {
        guard let last = lastLog(for: template.id) else {
            return "First time logging this one. Use the weight shown and see how it feels."
        }
        let doneSets = last.sets.filter { $0.done }
        if doneSets.count < last.sets.count {
            return "Last time you finished \(doneSets.count) of \(last.sets.count) sets. Stay at this weight or go lighter."
        }
        if doneSets.allSatisfy({ $0.reps >= template.topReps }) {
            return "Last time every set hit \(template.topReps) reps. Go up 5 lb next time."
        }
        let repsText = doneSets.map { String($0.reps) }.joined(separator: ", ")
        return "Last time: \(repsText) reps. Stay at this weight."
    }

    /// Total volume (weight × reps, working sets only) for sessions in a range.
    func volume(from start: Date, to end: Date) -> Double {
        // Explicit loop — the filter/flatMap/reduce chain timed out the
        // type checker (Swift 6 is slow inferring chained closures).
        var total: Double = 0
        for session in sessions where session.date >= start && session.date <= end {
            for exercise in session.exercises {
                for set in exercise.sets where set.done && set.kind != .warmup {
                    total += (set.weightLb ?? 0) * Double(set.reps)
                }
            }
        }
        return total
    }

    /// Sets done per muscle group this week (Fitbod weekly-set-targets pattern).
    func setsByMuscleThisWeek() -> [MuscleGroup: Int] {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
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

    /// Consecutive weeks with at least one session (streak).
    var weeklyStreak: Int {
        var streak = 0
        var weekStart = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        while sessions.contains(where: { session in
            let sessionWeek = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: session.date)) ?? session.date
            return sessionWeek == weekStart
        }) {
            streak += 1
            weekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        }
        return streak
    }

    // MARK: - Recovery (Body screen: fresh vs recovering, from logged history)

    /// One pass over saved sessions: the latest date each muscle group was
    /// trained (a done working set). Builds the id→muscle map once so the
    /// 1,583-exercise library isn't re-scanned per log.
    func lastTrainedDates() -> [MuscleGroup: Date] {
        var muscleById: [String: MuscleGroup] = [:]
        for lib in ExerciseLibrary.all(plus: customExercises) {
            muscleById[lib.id] = lib.muscle
        }
        var dates: [MuscleGroup: Date] = [:]
        let sorted = sessions.sorted { $0.date > $1.date }
        for session in sorted {
            for log in session.exercises {
                guard log.sets.contains(where: { $0.done && $0.kind == .working }) else { continue }
                guard let muscle = muscleById[log.exerciseId] else { continue }
                if dates[muscle] == nil { dates[muscle] = session.date }
            }
        }
        return dates
    }

    /// Recovery state of a muscle group from logged history. Trained in
    /// the last 48 hours = recovering; not trained for 3+ days (or never)
    /// = fresh.
    func recoveryState(for muscle: MuscleGroup, dates: [MuscleGroup: Date]? = nil) -> MuscleRecovery {
        let dates = dates ?? lastTrainedDates()
        guard let last = dates[muscle] else { return .fresh }
        let hours = Date().timeIntervalSince(last) / 3600
        return hours <= 48 ? .recovering : .fresh
    }

    /// Days since the most recent saved session (nil when no sessions yet).
    var daysSinceLastWorkout: Int? {
        guard let last = sessions.map({ $0.date }).max() else { return nil }
        return Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: last),
            to: Calendar.current.startOfDay(for: Date())).day
    }

    /// Muscle groups not trained in the last 48 hours — fresh and ready.
    var freshMuscleGroups: [MuscleGroup] {
        let tracked: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps, .forearms, .quads, .hamstrings, .glutes, .calves, .core, .obliques, .neck, .wrists, .feet, .ankles]
        let dates = lastTrainedDates()
        var fresh: [MuscleGroup] = []
        for group in tracked {
            if let last = dates[group] {
                let hours = Date().timeIntervalSince(last) / 3600
                if hours > 48 { fresh.append(group) }
            } else {
                fresh.append(group)
            }
        }
        return fresh
    }

    /// A one-line caption for a muscle group on the Body screen.
    func recoveryCaption(for muscle: MuscleGroup) -> String {
        guard let last = lastTrainedDates()[muscle] else {
            return "Not trained yet — fresh and ready."
        }
        let days = Calendar.current.dateComponents([.day],
            from: Calendar.current.startOfDay(for: last),
            to: Calendar.current.startOfDay(for: Date())).day ?? 0
        if days == 0 { return "Trained today — recovering." }
        if days == 1 { return "Trained yesterday — recovering." }
        if days <= 2 { return "Trained \(days) days ago — recovering." }
        return "Last trained \(days) days ago — fresh."
    }

    func saveBodyWeight(_ value: Double?) {
        bodyWeightLb = value
        if let value = value {
            UserDefaults.standard.set(value, forKey: weightKey)
        } else {
            UserDefaults.standard.removeObject(forKey: weightKey)
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
        if isPair {
            return "\(formatNumber(display))s"
        }
        return "\(formatNumber(display)) \(unit.label)"
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%g", value)
    }

    // MARK: - Onboarding + program

    /// Finish the intro flow: store the answers and the program, flip the
    /// first-launch gate. The main app appears immediately after.
    func completeOnboarding(profile: UserProfile, program: UserProgram) {
        self.profile = profile
        if !program.isPreset {
            generatedProgram = program
        }
        activeProgram = program
        hasCompletedOnboarding = true
        if let bodyweight = profile.bodyweightLb {
            saveBodyWeight(bodyweight)
        }
        persistProfileAndProgram()
        persistOnboarding()
    }

    /// Switch back to the program generated from the user's quiz.
    func useGeneratedProgram() {
        if let generatedProgram {
            activeProgram = generatedProgram
            persistProfileAndProgram()
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

    func setActiveProgram(_ program: UserProgram) {
        activeProgram = program
        persistProfileAndProgram()
    }

    func addExtraProgram(_ program: UserProgram) {
        extraPrograms.append(program)
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
            // Fall back to the generated program only — never to DaRon's
            // personal split. If there is no generated program, Today
            // shows its rest-day view until the user picks a program.
            activeProgram = generatedProgram
        }
        persistProfileAndProgram()
        persistCustomization()
    }

    /// Start the setup flow again from Profile. The privacy screen does not
    /// reappear (hasSeenPrivacy stays true).
    func resetOnboarding() {
        hasCompletedOnboarding = false
        persistOnboarding()
    }

    /// Today's plan from the active program (generated or preset). Nil on a
    /// rest day or when no program is set yet.
    func programDay(for date: Date) -> DayPlan? {
        guard let key = Program.dayKey(for: date) else { return nil }
        return activeProgram?.day(forKey: key)
    }

    func nextWorkout(after date: Date) -> (key: String, plan: DayPlan, date: Date)? {
        var candidate = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        for _ in 0..<7 {
            if let key = Program.dayKey(for: candidate),
               let plan = activeProgram?.day(forKey: key) {
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
        activeProgram = Program.daronPreset
        hasCompletedOnboarding = true
        persistProfileAndProgram()
        persistOnboarding()
    }

    private func persistProfileAndProgram() {
        if let profile, let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        } else if profile == nil {
            UserDefaults.standard.removeObject(forKey: profileKey)
        }
        if let activeProgram, let data = try? JSONEncoder().encode(activeProgram) {
            UserDefaults.standard.set(data, forKey: programKey)
        } else {
            UserDefaults.standard.removeObject(forKey: programKey)
        }
        if let generatedProgram, let data = try? JSONEncoder().encode(generatedProgram) {
            UserDefaults.standard.set(data, forKey: generatedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: generatedKey)
        }
    }

    private func persistOnboarding() {
        UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey)
        UserDefaults.standard.set(hasSeenPrivacy, forKey: privacyKey)
    }

    private func loadProfileAndProgram() {
        if let data = UserDefaults.standard.data(forKey: profileKey),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = decoded
        }
        if let data = UserDefaults.standard.data(forKey: programKey),
           let decoded = try? JSONDecoder().decode(UserProgram.self, from: data) {
            activeProgram = decoded
        }
        if let data = UserDefaults.standard.data(forKey: generatedKey),
           let decoded = try? JSONDecoder().decode(UserProgram.self, from: data) {
            generatedProgram = decoded
        }
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)
        hasSeenPrivacy = UserDefaults.standard.bool(forKey: privacyKey)
    }

    /// Mark the one-time privacy screen as seen so it never appears again.
    func markPrivacySeen() {
        hasSeenPrivacy = true
        persistOnboarding()
    }

    // MARK: - Customization persistence

    func persistCustomization() {
        if let data = try? JSONEncoder().encode(customExercises) {
            UserDefaults.standard.set(data, forKey: customExercisesKey)
        }
        if let data = try? JSONEncoder().encode(exercisePreferences) {
            UserDefaults.standard.set(data, forKey: preferencesKey)
        }
        if let data = try? JSONEncoder().encode(gymProfiles) {
            UserDefaults.standard.set(data, forKey: gymProfilesKey)
        }
        if let id = activeGymProfileID {
            UserDefaults.standard.set(id, forKey: activeGymProfileKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeGymProfileKey)
        }
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
        if let data = try? JSONEncoder().encode(extraPrograms) {
            UserDefaults.standard.set(data, forKey: extraProgramsKey)
        }
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        persistCustomization()
        // A mid-rest accent change recolours the Live Activity.
        syncRestLiveActivity()
    }

    private func loadCustomization() {
        if let data = UserDefaults.standard.data(forKey: customExercisesKey),
           let decoded = try? JSONDecoder().decode([CustomExercise].self, from: data) {
            customExercises = decoded
        }
        if let data = UserDefaults.standard.data(forKey: preferencesKey),
           let decoded = try? JSONDecoder().decode([String: ExercisePreference].self, from: data) {
            exercisePreferences = decoded
        }
        if let data = UserDefaults.standard.data(forKey: gymProfilesKey),
           let decoded = try? JSONDecoder().decode([GymProfile].self, from: data) {
            gymProfiles = decoded
        }
        activeGymProfileID = UserDefaults.standard.string(forKey: activeGymProfileKey)
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
            // OLED migration (2026-11-09): the old default was Auto and the
            // theme picker was Pro-gated, so no user ever deliberately
            // chose Auto — a stored Auto means "never chose", so it
            // becomes the new default, OLED dark. A deliberate Light
            // choice is untouched.
            if settings.colorScheme == .auto {
                settings.colorScheme = .dark
                persistCustomization()
            }
        }
        if let data = UserDefaults.standard.data(forKey: extraProgramsKey),
           let decoded = try? JSONDecoder().decode([UserProgram].self, from: data) {
            extraPrograms = decoded
        }
    }

    // MARK: - Draft session (autosaved in-progress workout)

    /// Make sure a draft exists for today's plan. Keeps an in-progress draft
    /// for today (so fold/unfold and app restarts lose nothing); starts a
    /// fresh one when the day or plan changes.
    func ensureDraft(for plan: DayPlan) {
        if draftDayKey == plan.key,
           let draftDate, Calendar.current.isDateInToday(draftDate) {
            // Keep the in-progress draft; fill in any exercise the plan
            // gained since the draft was created.
            var updated = draftLogs
            var changed = false
            for template in plan.exercises where updated[template.id] == nil {
                let weight = lastWeight(for: template) ?? template.defaultWeightLb
                updated[template.id] = (0..<template.sets).map { _ in
                    SetLog(weightLb: weight, reps: template.topReps, done: false)
                }
                changed = true
            }
            if changed { draftLogs = updated }
            if draftFinisherChecks.count != plan.finisher.count {
                draftFinisherChecks = plan.finisher.map { _ in false }
            }
            if draftExercises.isEmpty {
                draftExercises = plan.exercises
            }
            return
        }
        var fresh: [String: [SetLog]] = [:]
        for template in plan.exercises {
            let weight = lastWeight(for: template) ?? template.defaultWeightLb
            fresh[template.id] = (0..<template.sets).map { _ in
                SetLog(weightLb: weight, reps: template.topReps, done: false)
            }
        }
        draftDayKey = plan.key
        draftDate = Date()
        draftLogs = fresh
        draftFinisherChecks = plan.finisher.map { _ in false }
        draftExercises = plan.exercises
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
        let weight = lastWeight(for: template) ?? template.defaultWeightLb
        draftLogs[template.id] = (0..<template.sets).map { _ in
            SetLog(weightLb: weight, reps: template.topReps, done: false)
        }
    }

    func swapDraftExercise(id: String, with template: ExerciseTemplate) {
        guard let index = draftExercises.firstIndex(where: { $0.id == id }) else { return }
        let oldLogs = draftLogs[id] ?? []
        draftLogs.removeValue(forKey: id)
        draftExercises[index] = template
        let weight = lastWeight(for: template) ?? template.defaultWeightLb
        draftLogs[template.id] = (0..<template.sets).map { i in
            let old = oldLogs.indices.contains(i) ? oldLogs[i] : nil
            return SetLog(weightLb: weight, reps: old?.reps ?? template.topReps, done: false)
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
        draftSessionMod = nil
        draftNotes = [:]
        draftNoteTimes = [:]
        restEndsAt = nil
        restTemplateID = nil
    }

    private func persistDraft() {
        guard let dayKey = draftDayKey, let date = draftDate else {
            UserDefaults.standard.removeObject(forKey: draftKey)
            return
        }
        let draft = DraftSession(dayKey: dayKey, date: date, logs: draftLogs,
                                 finisherChecks: draftFinisherChecks,
                                 templates: draftExercises,
                                 sessionMod: draftSessionMod, notes: draftNotes,
                                 noteTimes: draftNoteTimes)
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: draftKey)
        }
    }

    private func loadDraft() {
        guard let data = UserDefaults.standard.data(forKey: draftKey),
              let draft = try? JSONDecoder().decode(DraftSession.self, from: data),
              Calendar.current.isDateInToday(draft.date) else {
            return
        }
        draftDayKey = draft.dayKey
        draftDate = draft.date
        draftLogs = draft.logs
        draftFinisherChecks = draft.finisherChecks
        draftExercises = draft.templates
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
        // Template first: the restEndsAt didSet fires the Live Activity
        // sync, which reads the template for the exercise name.
        restTemplateID = template?.id
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
        restEndsAt = nil
        restPausedRemaining = nil
        restTemplateID = nil
    }

    /// Restore a rest timer that was running when the app closed (only if it
    /// hasn't expired yet).
    private func loadRestTimer() {
        let paused = UserDefaults.standard.double(forKey: restPausedKey)
        if paused > 0 {
            restPausedRemaining = paused
            return
        }
        let stored = UserDefaults.standard.double(forKey: restEndsAtKey)
        guard stored > 0 else { return }
        let endsAt = Date(timeIntervalSince1970: stored)
        if endsAt > Date() {
            restEndsAt = endsAt
        } else {
            UserDefaults.standard.removeObject(forKey: restEndsAtKey)
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

    /// The exercise this rest belongs to, for the Live Activity label.
    private var restExerciseName: String {
        guard let restTemplateID else { return "Rest" }
        if let draft = draftExercises.first(where: { $0.id == restTemplateID }) {
            return draft.name
        }
        if let lib = ExerciseLibrary.byId(restTemplateID, plus: customExercises) {
            return lib.name
        }
        return "Rest"
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
                accentHex: effectiveAccentHex
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

    private func persistSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([SessionLog].self, from: data) {
            sessions = decoded.sorted { $0.date > $1.date }
        }
        if let data = UserDefaults.standard.data(forKey: userNotesKey),
           let decoded = try? JSONDecoder().decode([UserNote].self, from: data) {
            userNotes = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
        let stored = UserDefaults.standard.double(forKey: weightKey)
        bodyWeightLb = stored > 0 ? stored : nil
    }
}

// MARK: - Formatting helpers

func weightLabel(_ weightLb: Double?, isPair: Bool) -> String {
    guard let weightLb = weightLb, weightLb > 0 else { return "Set weight" }
    if isPair {
        return "\(Int(weightLb))s"
    }
    return "\(Int(weightLb)) lb"
}

/// Format a stored lb weight in a given unit (for History / Profile rows).
func weightLabel(_ weightLb: Double?, isPair: Bool, unit: WeightUnit) -> String {
    guard let display = unit.displayValue(for: weightLb), display > 0 else { return "Set weight" }
    if display == display.rounded() {
        return isPair ? "\(Int(display))s" : "\(Int(display)) \(unit.label)"
    }
    return isPair ? "\(String(format: "%g", display))s" : "\(String(format: "%g", display)) \(unit.label)"
}
