import Foundation

/// DaRon's 5-day program, from his goal file (~/workspace/goals/gain-muscle-and-look-hulk-like/GOAL.md).
/// Mon legs, Tue push, Wed legs, Thu pull, Fri upper mix. Mornings only, weekends rest.
/// Every session ends with a pump finisher so he leaves fully pumped.
enum Program {

    static func dayKey(for date: Date) -> String? {
        switch Calendar.current.component(.weekday, from: date) {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return nil
        }
    }

    /// DaRon's exact 5-day split + calibrated weights, as a built-in preset.
    /// His personal program — kept for his device only, never offered to
    /// other users. It does NOT activate on its own: a fresh install
    /// opens to onboarding (quiz or catalog), and the preset only becomes
    /// active when explicitly claimed on a device that is already unlocked
    /// for it (see `WorkoutStore.restoreDaronPreset`).
    static let daronPreset: UserProgram = {
        let orderedKeys = ["Mon", "Tue", "Wed", "Thu", "Fri"]
        let days = orderedKeys.compactMap { plans[$0] }
        return UserProgram(
            id: "daron-preset",
            name: "DaRon's 5-Day Split",
            days: days,
            swaps: [],
            isPreset: true
        )
    }()

    static let plans: [String: DayPlan] = {
        var plans: [String: DayPlan] = [:]
        plans["Mon"] = DayPlan(
            key: "Mon",
            title: "Legs",
            subtitle: "Monday · Squat, hinge, press, curl, calves",
            exercises: [squat, hipThrust, legPress, legCurl, calfRaise],
            finisher: ["Leg extension 2 × 15, light", "Calf raise 1 × 20, slow"]
        )
        plans["Wed"] = DayPlan(
            key: "Wed",
            title: "Legs",
            subtitle: "Wednesday · Squat, hinge, press, curl, calves",
            exercises: [squat, hipThrust, legPress, legCurl, calfRaise],
            finisher: ["Leg extension 2 × 15, light", "Calf raise 1 × 20, slow"]
        )
        plans["Tue"] = DayPlan(
            key: "Tue",
            title: "Push",
            subtitle: "Tuesday · Chest, shoulders, triceps",
            exercises: [chestFly, flatBench, lateralRaise, facePull, hammerCurl, tricepsPushdown],
            finisher: ["Cable chest fly 2 × 15, light", "Triceps pushdown 2 × 15, light"]
        )
        plans["Thu"] = DayPlan(
            key: "Thu",
            title: "Pull",
            subtitle: "Thursday · Back, rear delts, biceps",
            exercises: [latPulldown, cableRow, facePull, hammerCurl],
            finisher: ["Lat pulldown drop set: 100 × 8 → 70 × 8 → 50 × 10", "Cable curls 2 × 15, light"]
        )
        plans["Fri"] = DayPlan(
            key: "Fri",
            title: "Upper Mix",
            subtitle: "Friday · Chest, back, shoulders, arms",
            exercises: [flatBench, cableRow, lateralRaise, chestFly, armSuperset],
            finisher: ["Cable fly 2 × 15, light", "Pushdown 2 × 15 + curls 2 × 15"]
        )
        return plans
    }()

    // MARK: - Exercise templates (calibrated weights from live sessions)

    static let squat = ExerciseTemplate(
        id: "squat", name: "Barbell Back Squat", sets: 3, repRange: "8–12", topReps: 12,
        defaultWeightLb: 85, isPair: false, weightNote: nil,
        cues: "Screw feet into the floor, knees out over toes."
    )

    static let hipThrust = ExerciseTemplate(
        id: "hip-thrust", name: "DB Hip Thrust", sets: 3, repRange: "10–12", topReps: 12,
        defaultWeightLb: nil, isPair: false, weightNote: nil,
        cues: "Shoulders on a flat bench, dumbbell on hips. No machine needed. Replaces RDLs."
    )

    static let legPress = ExerciseTemplate(
        id: "leg-press", name: "Leg Press", sets: 3, repRange: "10–12", topReps: 12,
        defaultWeightLb: nil, isPair: false, weightNote: nil,
        cues: "Feet middle of the platform, shoulder-width. Wear shoes."
    )

    static let legCurl = ExerciseTemplate(
        id: "leg-curl", name: "Seated Leg Curl", sets: 3, repRange: "10–12", topReps: 12,
        defaultWeightLb: nil, isPair: false, weightNote: nil, cues: nil
    )

    static let calfRaise = ExerciseTemplate(
        id: "calf-raise", name: "Standing Calf Raise", sets: 3, repRange: "12–15", topReps: 15,
        defaultWeightLb: nil, isPair: false, weightNote: nil, cues: nil
    )

    static let chestFly = ExerciseTemplate(
        id: "chest-fly", name: "Cable Chest Fly", sets: 3, repRange: "12–15", topReps: 15,
        defaultWeightLb: nil, isPair: false, weightNote: nil,
        cues: "Light and slow, squeeze in the middle. Replaces incline DB press — easier on the left shoulder."
    )

    static let flatBench = ExerciseTemplate(
        id: "flat-bench", name: "Flat DB Bench Press", sets: 3, repRange: "8–12", topReps: 12,
        defaultWeightLb: 40, isPair: true, weightNote: nil,
        cues: "40s — the 45s were too heavy."
    )

    static let lateralRaise = ExerciseTemplate(
        id: "lateral-raise", name: "DB Lateral Raise", sets: 3, repRange: "12–15", topReps: 15,
        defaultWeightLb: 15, isPair: true, weightNote: nil,
        cues: "Stop at shoulder height, no shrugging."
    )

    static let facePull = ExerciseTemplate(
        id: "face-pull", name: "Cable Face Pull", sets: 3, repRange: "12–15", topReps: 15,
        defaultWeightLb: 25, isPair: false, weightNote: nil,
        cues: "Rear delts — good for the left shoulder."
    )

    static let hammerCurl = ExerciseTemplate(
        id: "hammer-curl", name: "DB Hammer Curl", sets: 2, repRange: "10–12", topReps: 12,
        defaultWeightLb: 20, isPair: true, weightNote: nil,
        cues: "25s were too heavy — 20s."
    )

    static let tricepsPushdown = ExerciseTemplate(
        id: "triceps-pushdown", name: "Cable Triceps Pushdown", sets: 2, repRange: "10–12", topReps: 12,
        defaultWeightLb: nil, isPair: false, weightNote: nil, cues: nil
    )

    static let latPulldown = ExerciseTemplate(
        id: "lat-pulldown", name: "Lat Pulldown", sets: 3, repRange: "8–12", topReps: 12,
        defaultWeightLb: 100, isPair: false, weightNote: nil, cues: nil
    )

    static let cableRow = ExerciseTemplate(
        id: "cable-row", name: "Cable Row", sets: 3, repRange: "10–12", topReps: 12,
        defaultWeightLb: 50, isPair: false, weightNote: "25–30 per side",
        cues: "Straight bar across both cable stacks. Overhand grip, pull with your elbows."
    )

    static let armSuperset = ExerciseTemplate(
        id: "arm-superset", name: "Arm Superset: Pushdown + Hammer Curl", sets: 2, repRange: "10–12", topReps: 12,
        defaultWeightLb: nil, isPair: false, weightNote: nil,
        cues: "Cable pushdown, then hammer curls, back to back."
    )

    // MARK: - Calibrated weights reference (Profile tab)
    // Deleted 2026-11-10 (consistency pass): this hardcoded name+weight
    // list duplicated the preset templates and drifted from them
    // (it still listed "Seated DB overhead press", which the preset no
    // longer contains). Profile's working weights read the live program
    // + last logged weight instead — one source, no copy.
}
