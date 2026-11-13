import SwiftUI
import UIKit

// MARK: - Workout export (CSV / PDF / plain text / JSON)
//
// "Export workouts in all way possible" (DaRon, 2026-11-10).
//
// Everything here is USER-INITIATED only: these builders run when the
// user taps Export, and nothing leaves the device until the user picks
// a destination in the share sheet (or taps Copy). The app collects no
// data; an export is a local file the user chooses to send somewhere.
//
// Correlation rule (same as the screens): every number in every format
// comes from the store's shared formatters — `volumeLb(for:)` for
// volume, `formattedVolumeLb` for its text, `store.setWeightText` for
// each set's "100 lb × 8" line, `store.sessionOneRepMax` /
// `store.oneRepMax(for:)` for max lifts, `WeightUnit.displayValue`
// for unit conversion. No formula is re-implemented here: no second
// volume math, no second 1RM math. The text export and the PDF are
// rendered from the SAME summary lines, so they can never disagree
// with each other either.
//
// Rules inherited from the store (not restated as new math):
// - A bodyweight set contributes 0 lb volume (`volumeLb(for:)`).
// - Per-hand dumbbell loads are doubled in volume (`setVolumeLb`);
//   the CSV says so in its `per_hand` column.
// - The per-exercise unit override travels with the set
//   (`ExerciseLog.unitOverride`); display goes through that unit.

/// The four export formats.
enum ExportFormat: String, CaseIterable, Identifiable {
    case csv
    case pdf
    case text
    case json

    var id: String { rawValue }

    var label: String {
        switch self {
        case .csv: return "CSV"
        case .pdf: return "PDF"
        case .text: return "Text"
        case .json: return "JSON"
        }
    }

    /// What the format is for, shown under the picker.
    var detail: String {
        switch self {
        case .csv: return "Spreadsheet — one row per set, plus a totals row."
        case .pdf: return "Printable summary — clean layout for paper or files."
        case .text: return "Plain text — paste it into a message."
        case .json: return "Full structured data — sessions, sets, notes, dates."
        }
    }

    var fileExtension: String { self == .text ? "txt" : rawValue }

    /// True when the format's content is text the user can paste.
    /// PDF is the exception: copying a PDF copies its plain-text
    /// summary instead (see `WorkoutExport.copyText`).
    var isTextBased: Bool { self != .pdf }
}

/// What the user chose to export.
enum ExportScope: Equatable {
    /// One workout, from a session's detail page.
    case session(SessionLog)
    /// All sessions whose date falls in the range (both ends inclusive).
    case range(from: Date, to: Date)
    /// Every logged workout.
    case all
    /// Every session that logged this exercise, narrowed to that
    /// exercise only (other exercises in those sessions are left out —
    /// the totals are for this exercise, which is what per-exercise
    /// history means).
    case exercise(id: String, name: String)

    var label: String {
        switch self {
        case .session: return "This workout"
        case .range: return "Date range"
        case .all: return "All history"
        case .exercise(_, let name): return name
        }
    }

    /// The sessions this scope covers, newest first (the store's order).
    func sessions(from store: WorkoutStore) -> [SessionLog] {
        sessions(in: store.sessions)
    }

    /// Same, over a snapshot of the store's sessions (newest first).
    func sessions(in all: [SessionLog]) -> [SessionLog] {
        switch self {
        case .session(let session):
            return [session]
        case .range(let from, let to):
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: from)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to)) ?? to
            return all.filter { $0.date >= start && $0.date < end }
        case .all:
            return all
        case .exercise(let id, _):
            var out: [SessionLog] = []
            for session in all {
                let matches = session.exercises.filter { $0.exerciseId == id }
                guard !matches.isEmpty else { continue }
                var narrowed = session
                narrowed.exercises = matches
                out.append(narrowed)
            }
            return out
        }
    }

    /// Human title for the export header ("All history",
    /// "Lat Pulldown — all history", "Nov 1 – Nov 10, 2026").
    func titleText() -> String {
        switch self {
        case .session(let session):
            return "\(session.dayKey) · \(session.dayTitle) — \(WorkoutExport.shortDate(session.date))"
        case .range(let from, let to):
            return "\(WorkoutExport.shortDate(from)) – \(WorkoutExport.shortDate(to))"
        case .all:
            return "All history"
        case .exercise(_, let name):
            return "\(name) — all history"
        }
    }

    /// Filename-safe slug for this scope.
    var fileSlug: String {
        switch self {
        case .session(let session):
            return WorkoutExport.slug("\(session.dayKey)-\(session.dayTitle)")
        case .range(let from, let to):
            return "\(WorkoutExport.fileDate(from))-to-\(WorkoutExport.fileDate(to))"
        case .all:
            return "All-history"
        case .exercise(_, let name):
            return WorkoutExport.slug(name)
        }
    }

    /// True when this scope is the same CHOICE as `other` (a range
    /// matches any range regardless of its dates — the pickers own the
    /// dates; a session matches only its own session).
    func isSameChoice(as other: ExportScope) -> Bool {
        switch (self, other) {
        case (.session(let a), .session(let b)): return a.id == b.id
        case (.range, .range): return true
        case (.all, .all): return true
        case (.exercise(let a, _), .exercise(let b, _)): return a == b
        default: return false
        }
    }
}

/// What a sheet presentation carries: the scope to start on and the
/// scopes the user may switch between on that sheet. One option = no
/// scope picker is shown (session detail, per-exercise view).
struct ExportRequest: Identifiable {
    let id = UUID()
    let initialScope: ExportScope
    let scopeOptions: [ExportScope]

    init(initialScope: ExportScope, scopeOptions: [ExportScope]? = nil) {
        self.initialScope = initialScope
        self.scopeOptions = scopeOptions ?? [initialScope]
    }
}

/// One exported file: the bytes, the filename, and the format.
struct ExportedFile {
    let data: Data
    let filename: String
    let format: ExportFormat

    /// Write to the app's temp directory so the share sheet gets a
    /// real file (AirDrop, Save to Files, Mail, Print all want a URL
    /// with a filename, not raw bytes). The temp directory is
    /// on-device and the system clears it; nothing is uploaded.
    func temporaryURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }
}

// MARK: - Shared summary model (one source for text + PDF)

/// One styled line of the printable summary. The text export joins
/// the texts; the PDF draws them with the style's font. One model, so
/// the two formats can never disagree.
struct ExportLine {
    enum Style {
        case title       // "Gym Tracker — Workout Export"
        case heading     // per-session heading + the TOTAL line
        case subheading  // exercise name
        case body        // set lines, totals, notes
        case muted       // the "Exported …" line
    }

    let text: String
    let style: Style
}

/// One exercise's export numbers, all from the shared formatters.
struct ExportExerciseSummary {
    let name: String
    /// One line per set, exactly as History shows it
    /// (`store.setWeightText`) plus its done state.
    let setLines: [String]
    /// "1.2k lb" — `formattedVolumeLb(volumeLb(for: [exercise]))`.
    let volumeText: String
    /// Best valid max lift for this exercise in this session, if the
    /// shared 1RM gate allows one (compound, ≤10-rep set).
    let bestOneRMText: String?
}

/// One session's export numbers, all from the shared formatters.
struct ExportSessionSummary {
    let session: SessionLog
    let heading: String
    let exercises: [ExportExerciseSummary]
    /// "8.5k lb" — `formattedVolumeLb(volumeLb(for: exercises))`.
    let totalVolumeText: String
    let doneSets: Int
    let totalSets: Int
    /// The planned finisher items (`finisherNotes` is the plan's
    /// finisher strings joined with "; "), or nil when none.
    let finisherText: String?
    /// User notes for this workout: the finisher note is not a user
    /// note, so these are the Notes-page notes whose `workoutTitle`
    /// is this session's day title and whose `createdAt` falls on the
    /// session's day.
    let notes: [(exercise: String, text: String)]
}

/// Everything an export needs from the store, copied on the main
/// thread so the file can be built on a background queue (3 years of
/// history froze the sheet when it was built inline). Value types only.
///
/// The per-set / per-weight text mirrors the store's shared formatters
/// (`store.setWeightText`, `store.sessionOneRepMax`,
/// `store.oneRepMax(for:)`) — same rules, run off the main thread.
struct ExportContext {
    let weightUnit: WeightUnit
    let calendar: Calendar
    /// User notes bucketed by start of day, grouped ONCE (they were
    /// filtered per session).
    private let notesByDay: [Date: [UserNote]]
    /// Best valid 1RM per exercise id across ALL history, worked out in
    /// one pass (it was `store.oneRepMax(for:)` per exercise log — a
    /// full history scan each, O(n²)).
    let bestOneRepMaxLb: [String: Double]
    private let compoundIds: Set<String>
    private let bodyweightIds: Set<String>

    /// Snapshot the store (call on the main thread).
    init(store: WorkoutStore) {
        self.init(allSessions: store.sessions, weightUnit: store.settings.weightUnit,
                  customExercises: store.customExercises, userNotes: store.userNotes)
    }

    init(allSessions: [SessionLog], weightUnit: WeightUnit, customExercises: [CustomExercise],
         userNotes: [UserNote], calendar: Calendar = .current) {
        self.weightUnit = weightUnit
        self.calendar = calendar
        var compound = Set<String>(), bodyweight = Set<String>(), seen = Set<String>()
        var best: [String: Double] = [:]
        for session in allSessions {
            for exercise in session.exercises {
                let id = exercise.exerciseId
                if seen.insert(id).inserted, let lib = ExerciseLibrary.byId(id, plus: customExercises) {
                    if lib.isCompound { compound.insert(id) }
                    if lib.isBodyweight { bodyweight.insert(id) }
                }
                guard compound.contains(id),
                      let oneRM = bestValidOneRepMax(in: exercise.sets, isCompound: true) else { continue }
                best[id] = max(best[id] ?? 0, oneRM)
            }
        }
        compoundIds = compound
        bodyweightIds = bodyweight
        bestOneRepMaxLb = best
        var notes: [Date: [UserNote]] = [:]
        for note in userNotes {
            notes[calendar.startOfDay(for: note.createdAt), default: []].append(note)
        }
        notesByDay = notes
    }

    func unit(for exercise: ExerciseLog) -> WeightUnit { exercise.unitOverride ?? weightUnit }

    func isBodyweight(_ exerciseId: String) -> Bool { bodyweightIds.contains(exerciseId) }

    /// `store.setWeightText`'s rule: weight × reps in the exercise's
    /// unit, "Bodyweight × n" for a bodyweight lift, "— × n" otherwise.
    func setWeightText(_ set: SetLog, exercise: ExerciseLog) -> String {
        if let weight = set.weightLb, weight > 0 {
            return "\(weightLabel(weight, isPair: exercise.isPair, unit: unit(for: exercise))) × \(set.reps)"
        }
        return isBodyweight(exercise.exerciseId) ? "Bodyweight × \(set.reps)" : "— × \(set.reps)"
    }

    /// `store.sessionOneRepMax`'s rule (compound, ≤10-rep done sets).
    func sessionOneRepMax(session: SessionLog, exerciseId: String) -> Double? {
        guard compoundIds.contains(exerciseId) else { return nil }
        var best: Double = 0
        for exercise in session.exercises where exercise.exerciseId == exerciseId {
            if let oneRM = bestValidOneRepMax(in: exercise.sets, isCompound: true) { best = max(best, oneRM) }
        }
        return best > 0 ? best : nil
    }

    /// A max-lift weight in the exercise's own unit (its override).
    func liftText(_ lb: Double, exercise: ExerciseLog) -> String {
        liftWeightText(lb, isPair: exercise.isPair, unit: unit(for: exercise))
    }

    /// Volume in the user's unit ("8.5k kg").
    func volumeText(_ lb: Double) -> String { unitVolumeText(lb: lb, unit: weightUnit) }

    /// The Notes-page notes for a workout: same day, same day title.
    func notes(for session: SessionLog) -> [UserNote] {
        (notesByDay[calendar.startOfDay(for: session.date)] ?? []).filter { $0.workoutTitle == session.dayTitle }
    }
}

/// One export to build: the scope's sessions plus the context, both
/// snapshotted on the main thread; `file` / `copyText` are safe to run
/// on a background queue.
struct ExportJob {
    let scope: ExportScope
    // Plain value copies (copy-on-write: no work on the main thread).
    private let allSessions: [SessionLog]
    private let weightUnit: WeightUnit
    private let customExercises: [CustomExercise]
    private let userNotes: [UserNote]

    init(store: WorkoutStore, scope: ExportScope) {
        self.scope = scope
        allSessions = store.sessions
        weightUnit = store.settings.weightUnit
        customExercises = store.customExercises
        userNotes = store.userNotes
    }

    /// Scope filtering + the one-pass context, on the calling queue.
    private func prepare() -> (sessions: [SessionLog], context: ExportContext) {
        (scope.sessions(in: allSessions),
         ExportContext(allSessions: allSessions, weightUnit: weightUnit,
                       customExercises: customExercises, userNotes: userNotes))
    }

    func file(format: ExportFormat) throws -> ExportedFile {
        let (sessions, context) = prepare()
        return try WorkoutExport.file(sessions: sessions, scope: scope, format: format, context: context)
    }

    func copyText(format: ExportFormat) -> String {
        let (sessions, context) = prepare()
        return WorkoutExport.copyText(sessions: sessions, scope: scope, format: format, context: context)
    }
}

enum WorkoutExport {

    // MARK: - Dates

    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Fixed-format dates for CSV and filenames: POSIX locale and the
    /// Gregorian calendar, so a Buddhist / Japanese calendar or a
    /// 12-hour locale can't change the digits; the device's time zone,
    /// stated explicitly (the CSV's day and time are local).
    private static func fixedFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = format
        return f
    }

    private static let csvDateFormatter = fixedFormatter("yyyy-MM-dd")
    private static let csvTimeFormatter = fixedFormatter("HH:mm")

    static func shortDate(_ date: Date) -> String { shortDateFormatter.string(from: date) }

    static func fileDate(_ date: Date) -> String { csvDateFormatter.string(from: date) }

    /// Filename-safe: letters, digits and "-" only.
    static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let parts = text.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        let slug = parts.joined(separator: "-")
        return slug.isEmpty ? "Workout" : slug
    }

    // MARK: - Entry point

    /// Build the file for a scope + format on the calling thread
    /// (main). The sheet uses `ExportJob` to build off the main thread.
    static func file(scope: ExportScope, format: ExportFormat, store: WorkoutStore) throws -> ExportedFile {
        try ExportJob(store: store, scope: scope).file(format: format)
    }

    /// Build the file from snapshotted data. Throws only when the JSON
    /// encoder fails — the other formats cannot fail.
    static func file(sessions: [SessionLog], scope: ExportScope, format: ExportFormat, context: ExportContext) throws -> ExportedFile {
        let data: Data
        switch format {
        case .csv: data = Data(csvString(sessions: sessions, context: context).utf8)
        case .text: data = Data(textString(sessions: sessions, scope: scope, context: context).utf8)
        case .json: data = try jsonData(sessions: sessions, scope: scope, context: context)
        case .pdf: data = pdfData(sessions: sessions, scope: scope, context: context)
        }
        let filename = "GymTracker-\(scope.fileSlug)-\(fileDate(Date())).\(format.fileExtension)"
        return ExportedFile(data: data, filename: filename, format: format)
    }

    /// The text the Copy button puts on the clipboard. For PDF there
    /// is no pasteable file content, so it copies the plain-text
    /// summary of the same scope (the sheet labels the button
    /// "Copy as text" in that case).
    static func copyText(scope: ExportScope, format: ExportFormat, store: WorkoutStore) -> String {
        ExportJob(store: store, scope: scope).copyText(format: format)
    }

    static func copyText(sessions: [SessionLog], scope: ExportScope, format: ExportFormat, context: ExportContext) -> String {
        switch format {
        case .csv: return csvString(sessions: sessions, context: context)
        case .json: return (try? String(data: jsonData(sessions: sessions, scope: scope, context: context), encoding: .utf8)) ?? ""
        case .pdf, .text: return textString(sessions: sessions, scope: scope, context: context)
        }
    }

    // MARK: - Shared summaries (text + PDF source)

    /// One summary per session, built only from shared formatters.
    static func summaries(for sessions: [SessionLog], context: ExportContext) -> [ExportSessionSummary] {
        sessions.map { session in
            let exercises = session.exercises.map { exercise -> ExportExerciseSummary in
                let setLines = exercise.sets.enumerated().map { index, set -> String in
                    var line = "Set \(index + 1)"
                    if set.kind != .working { line += " (\(set.kind.label))" }
                    line += ": \(context.setWeightText(set, exercise: exercise))"
                    line += set.done ? " — done" : " — not done"
                    return line
                }
                // In the exercise's own unit (its saved override).
                let oneRMText = context.sessionOneRepMax(session: session, exerciseId: exercise.exerciseId)
                    .map { context.liftText($0, exercise: exercise) }
                return ExportExerciseSummary(
                    name: exercise.name,
                    setLines: setLines,
                    volumeText: context.volumeText(volumeLb(for: [exercise])),
                    bestOneRMText: oneRMText
                )
            }
            let doneSets = session.exercises.flatMap { $0.sets }.filter { $0.done }.count
            let totalSets = session.exercises.flatMap { $0.sets }.count
            let finisher = session.finisherNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = context.notes(for: session).map { (exercise: $0.title, text: $0.body) }
            return ExportSessionSummary(
                session: session,
                heading: "\(session.dayKey) · \(session.dayTitle) — \(shortDate(session.date))",
                exercises: exercises,
                totalVolumeText: context.volumeText(volumeLb(for: session.exercises)),
                doneSets: doneSets,
                totalSets: totalSets,
                finisherText: finisher.isEmpty ? nil : finisher,
                notes: notes
            )
        }
    }

    /// The printable summary as styled lines. Shared by the text
    /// export and the PDF — one model, two renderers.
    static func summaryLines(sessions: [SessionLog], scope: ExportScope, context: ExportContext) -> [ExportLine] {
        let summaries = summaries(for: sessions, context: context)
        var lines: [ExportLine] = [
            ExportLine(text: "Status — Workout Export", style: .title),
            ExportLine(text: "Exported \(shortDate(Date())) · \(scope.titleText())", style: .muted),
            ExportLine(text: "", style: .body),
        ]
        if summaries.isEmpty {
            lines.append(ExportLine(text: "No workouts in this scope yet — finish a workout from Today and it will show up here.", style: .body))
            return lines
        }
        for summary in summaries {
            lines.append(ExportLine(text: summary.heading, style: .heading))
            for exercise in summary.exercises {
                lines.append(ExportLine(text: exercise.name, style: .subheading))
                for setLine in exercise.setLines {
                    lines.append(ExportLine(text: setLine, style: .body))
                }
                var volumeLine = "Volume: \(exercise.volumeText)"
                if let oneRM = exercise.bestOneRMText {
                    volumeLine += " · Best max lift: \(oneRM)"
                }
                lines.append(ExportLine(text: volumeLine, style: .body))
            }
            if summary.session.finisherDone {
                lines.append(ExportLine(text: "Pump finisher: done", style: .body))
            }
            if let finisher = summary.finisherText {
                lines.append(ExportLine(text: "Finisher: \(finisher)", style: .body))
            }
            for note in summary.notes {
                lines.append(ExportLine(text: "Note (\(note.exercise)): \(note.text)", style: .body))
            }
            lines.append(ExportLine(text: "Session total: \(summary.totalVolumeText) · \(setsDoneText(done: summary.doneSets, total: summary.totalSets))", style: .body))
            lines.append(ExportLine(text: "", style: .body))
        }
        if summaries.count > 1 {
            let totalExercises = summaries.flatMap { $0.exercises }.count
            let totalSets = summaries.reduce(0) { $0 + $1.totalSets }
            let totalVolume = volumeLb(for: sessions.flatMap { $0.exercises })
            lines.append(ExportLine(
                text: "TOTAL — \(pluralised(summaries.count, singular: "workout")) · \(pluralised(totalExercises, singular: "exercise")) · \(pluralised(totalSets, singular: "set")) · \(context.volumeText(totalVolume))",
                style: .heading))
        }
        return lines
    }

    // MARK: - Plain text

    static func textString(sessions: [SessionLog], scope: ExportScope, context: ExportContext) -> String {
        summaryLines(sessions: sessions, scope: scope, context: context)
            .map { line in
                // Indent sub-lines so the text reads as an outline.
                switch line.style {
                case .subheading: return "  \(line.text)"
                case .body where !line.text.isEmpty: return line.text.hasPrefix("Set ") || line.text.hasPrefix("Volume:") || line.text.hasPrefix("Pump finisher:") || line.text.hasPrefix("Finisher:") || line.text.hasPrefix("Note (") ? "    \(line.text)" : "  \(line.text)"
                default: return line.text
                }
            }
            .joined(separator: "\n")
    }

    // MARK: - CSV (one row per set + a totals row)

    static func csvString(sessions: [SessionLog], context: ExportContext) -> String {
        var rows: [String] = [
            "date,time,workout,exercise,set,kind,weight,reps,unit,per_hand,done"
        ]
        var totalSets = 0
        var doneSets = 0
        var totalReps = 0
        for session in sessions {
            for exercise in session.exercises {
                // The unit in effect for this exercise: its saved
                // override, else the global unit — the same unit the
                // screen showed when the set was logged.
                let unit = context.unit(for: exercise)
                let isBodyweight = context.isBodyweight(exercise.exerciseId)
                for (index, set) in exercise.sets.enumerated() {
                    totalSets += 1
                    if set.done { doneSets += 1 }
                    totalReps += set.reps
                    let weight = unit.displayValue(for: set.weightLb).map(numberText) ?? ""
                    let unitText: String
                    if set.weightLb == nil || (set.weightLb ?? 0) <= 0 {
                        unitText = isBodyweight ? "bodyweight" : unit.label
                    } else {
                        unitText = unit.label
                    }
                    let fields = [
                        csvDateFormatter.string(from: session.date),
                        csvTimeFormatter.string(from: session.date),
                        session.dayTitle,
                        exercise.name,
                        "\(index + 1)",
                        set.kind.label,
                        weight,
                        "\(set.reps)",
                        unitText,
                        exercise.isPair ? "yes" : "no",
                        set.done ? "yes" : "no",
                    ]
                    rows.append(fields.map(csvField).joined(separator: ","))
                }
            }
        }
        // Totals row: volume is the shared `volumeLb(for:)` (bodyweight
        // sets contribute 0, per-hand loads doubled), in the user's unit.
        let totalVolume = volumeInUnit(volumeLb(for: sessions.flatMap { $0.exercises }), unit: context.weightUnit)
        let totals = [
            "",
            "",
            "TOTAL",
            "\(sessions.count) workout\(sessions.count == 1 ? "" : "s")",
            "\(totalSets)",
            "",
            numberText(totalVolume),
            "\(totalReps)",
            context.weightUnit.label,
            "",
            "\(doneSets)/\(totalSets)",
        ]
        rows.append(totals.map(csvField).joined(separator: ","))
        return rows.joined(separator: "\n")
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    /// "40" for a whole number, 1 decimal otherwise — no trailing ".0".
    private static func numberText(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return roundedWeightText(value)
    }

    // MARK: - JSON (full structured data)

    private struct ExportDocument: Codable {
        let app: String
        let exportedAt: Date
        let scope: String
        let workouts: [ExportWorkout]
        let totals: ExportTotals
    }

    private struct ExportWorkout: Codable {
        let id: UUID
        let date: Date
        let dayKey: String
        let dayTitle: String
        let finisherDone: Bool
        let finisher: String?
        let notes: [ExportNote]
        let exercises: [ExportExercise]
        let totalVolumeLb: Double
        let totalVolume: String
        let setsDone: Int
        let setsTotal: Int
    }

    private struct ExportNote: Codable {
        let exercise: String
        let text: String
    }

    private struct ExportExercise: Codable {
        let id: String
        let name: String
        let isPair: Bool
        let unit: String
        let sets: [ExportSet]
        let volumeLb: Double
        let bestOneRepMaxLb: Double?
    }

    private struct ExportSet: Codable {
        let set: Int
        let kind: String
        /// Stored lb (the raw number). Nil for a bodyweight set.
        let weightLb: Double?
        /// The exact text History shows for this set ("100 lb × 8").
        let weightDisplay: String
        let reps: Int
        let done: Bool
    }

    private struct ExportTotals: Codable {
        let workouts: Int
        let exercises: Int
        let sets: Int
        let setsDone: Int
        let totalVolumeLb: Double
    }

    static func jsonData(sessions: [SessionLog], scope: ExportScope, context: ExportContext) throws -> Data {
        let summaries = summaries(for: sessions, context: context)
        let workouts = zip(sessions, summaries).map { session, summary -> ExportWorkout in
            let exercises = zip(session.exercises, summary.exercises).map { exercise, exSummary -> ExportExercise in
                let sets = exercise.sets.enumerated().map { index, set -> ExportSet in
                    ExportSet(
                        set: index + 1,
                        kind: set.kind.rawValue,
                        weightLb: set.weightLb,
                        weightDisplay: context.setWeightText(set, exercise: exercise),
                        reps: set.reps,
                        done: set.done
                    )
                }
                // Best valid 1RM for this exercise across ALL history
                // (the shared gate, precomputed once in the context),
                // not just this session, so the JSON answers "best ever".
                return ExportExercise(
                    id: exercise.exerciseId,
                    name: exercise.name,
                    isPair: exercise.isPair,
                    unit: context.unit(for: exercise).label,
                    sets: sets,
                    volumeLb: volumeLb(for: [exercise]),
                    bestOneRepMaxLb: context.bestOneRepMaxLb[exercise.exerciseId]
                )
            }
            let finisher = summary.finisherText
            return ExportWorkout(
                id: session.id,
                date: session.date,
                dayKey: session.dayKey,
                dayTitle: session.dayTitle,
                finisherDone: session.finisherDone,
                finisher: finisher,
                notes: summary.notes.map { ExportNote(exercise: $0.exercise, text: $0.text) },
                exercises: exercises,
                totalVolumeLb: volumeLb(for: session.exercises),
                totalVolume: summary.totalVolumeText,
                setsDone: summary.doneSets,
                setsTotal: summary.totalSets
            )
        }
        let totals = ExportTotals(
            workouts: sessions.count,
            exercises: sessions.flatMap { $0.exercises }.count,
            sets: sessions.flatMap { $0.exercises }.flatMap { $0.sets }.count,
            setsDone: sessions.flatMap { $0.exercises }.flatMap { $0.sets }.filter { $0.done }.count,
            totalVolumeLb: volumeLb(for: sessions.flatMap { $0.exercises })
        )
        let document = ExportDocument(
            app: "Status",
            exportedAt: Date(),
            scope: scope.titleText(),
            workouts: workouts,
            totals: totals
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    // MARK: - PDF (printable summary, same lines as the text export)

    /// Rendered with UIGraphicsPDFRenderer (US Letter, 48pt margins).
    /// The content is the shared `summaryLines` — the PDF and the
    /// text export are two renderers over the same lines, so their
    /// numbers can never drift apart.
    static func pdfData(sessions: [SessionLog], scope: ExportScope, context: ExportContext) -> Data {
        let lines = summaryLines(sessions: sessions, scope: scope, context: context)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 48
        let contentWidth = pageRect.width - margin * 2
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Status — Workout Export"]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { context in
            var page = 1
            var y = margin

            func font(for style: ExportLine.Style) -> UIFont {
                switch style {
                case .title: return .boldSystemFont(ofSize: 20)
                case .heading: return .boldSystemFont(ofSize: 14)
                case .subheading: return .boldSystemFont(ofSize: 12)
                case .body: return .systemFont(ofSize: 11)
                case .muted: return .systemFont(ofSize: 11)
                }
            }

            func drawFooter(_ pageNumber: Int) {
                let footer = "Status — page \(pageNumber)"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9),
                    // Fixed print colors: dynamic label colors resolve to
                    // white in dark mode — white text on a white page.
                    .foregroundColor: UIColor.darkGray,
                ]
                let size = footer.size(withAttributes: attrs)
                footer.draw(at: CGPoint(x: (pageRect.width - size.width) / 2, y: pageRect.height - 32), withAttributes: attrs)
            }

            context.beginPage()
            for line in lines {
                let indent: CGFloat = {
                    switch line.style {
                    case .subheading: return 12
                    case .body: return line.text.hasPrefix("Set ") || line.text.hasPrefix("Volume:")
                        || line.text.hasPrefix("Pump finisher:") || line.text.hasPrefix("Finisher:")
                        || line.text.hasPrefix("Note (") ? 24 : 12
                    default: return 0
                    }
                }()
                let text = line.text
                let lineFont = font(for: line.style)
                let color: UIColor = line.style == .muted ? .darkGray : .black
                let attrs: [NSAttributedString.Key: Any] = [.font: lineFont, .foregroundColor: color]
                let height = text.isEmpty ? 6 : text.boundingRect(
                    with: CGSize(width: contentWidth - indent, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin],
                    attributes: attrs, context: nil
                ).height
                if y + height > pageRect.height - margin - 20 {
                    drawFooter(page)
                    context.beginPage()
                    page += 1
                    y = margin
                }
                if !text.isEmpty {
                    text.draw(in: CGRect(x: margin + indent, y: y, width: contentWidth - indent, height: height), withAttributes: attrs)
                }
                y += height + (line.style == .heading ? 8 : line.style == .title ? 6 : 2)
            }
            drawFooter(page)
        }
    }
}

// MARK: - Export sheet (scope + format picker, share + copy)
//
// Presented from History (session detail + History page) and from the
// strength graph (per-exercise view). The sheet only BUILDS the file;
// the user decides where it goes via the share sheet, or pastes it
// via Copy. Nothing is sent anywhere by this sheet itself.

struct ExportSheet: View {
    @EnvironmentObject var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss

    let request: ExportRequest

    @State private var scope: ExportScope
    @State private var format: ExportFormat = .csv
    @State private var rangeFrom: Date
    @State private var rangeTo: Date
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var copied = false
    @State private var errorMessage: String?
    /// True while a file / copy text is being built off the main thread.
    @State private var isBuilding = false

    init(request: ExportRequest) {
        self.request = request
        _scope = State(initialValue: request.initialScope)
        if case .range(let from, let to) = request.initialScope {
            _rangeFrom = State(initialValue: from)
            _rangeTo = State(initialValue: to)
        } else {
            _rangeFrom = State(initialValue: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date())
            _rangeTo = State(initialValue: Date())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if request.scopeOptions.count > 1 {
                    Section("What to export") {
                        scopePicker
                    }
                }
                if case .range = scope {
                    Section("Date range") {
                        DatePicker("From", selection: $rangeFrom, displayedComponents: .date)
                        DatePicker("To", selection: $rangeTo, displayedComponents: .date)
                    }
                }
                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(format.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Section {
                    summaryRow
                }
                Section {
                    shareButton
                    copyButton
                }
                Section {
                    Text("Exports stay on your device until you choose to share them — nothing is uploaded.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .navigationTitle("Export workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: rangeFrom) { _, _ in applyRange() }
            .onChange(of: rangeTo) { _, _ in applyRange() }
            .onChange(of: format) { _, _ in copied = false }
            .onChange(of: scope) { _, _ in copied = false }
            .sheet(isPresented: $showingShare) {
                if let shareURL {
                    ShareSheet(activityItems: [shareURL])
                }
            }
            .alert("Couldn't export", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Scope chips (not a Picker: a range's tag would change every
    /// time its dates move). The selected chip is the scope whose
    /// CHOICE matches, ignoring the range's current dates.
    private var scopePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(request.scopeOptions.indices, id: \.self) { index in
                    let option = request.scopeOptions[index]
                    let selected = scope.isSameChoice(as: option)
                    Button {
                        scope = option
                        if case .range = option { applyRange() }
                    } label: {
                        Text(option.label)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selected ? Color.accentColor : Theme.cardElevated)
                            .foregroundStyle(selected ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The resolved sessions for the current scope, and their totals —
    /// the same shared volume formula the screens use.
    private var resolvedSessions: [SessionLog] { scope.sessions(from: store) }

    private var summaryRow: some View {
        let sessions = resolvedSessions
        let exercises = sessions.flatMap { $0.exercises }.count
        let sets = sessions.flatMap { $0.exercises }.flatMap { $0.sets }.count
        let volume = volumeLb(for: sessions.flatMap { $0.exercises })
        return Group {
            if sessions.isEmpty {
                Text("No workouts in this scope yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                HStack {
                    Text("\(sessions.count) workout\(sessions.count == 1 ? "" : "s") · \(exercises) exercises · \(sets) sets")
                        .font(.subheadline)
                    Spacer()
                    Text(unitVolumeText(lb: volume, unit: store.settings.weightUnit))
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var shareButton: some View {
        Button {
            share()
        } label: {
            HStack {
                Label(isBuilding ? "Preparing…" : "Share…", systemImage: "square.and.arrow.up")
                if isBuilding {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(resolvedSessions.isEmpty || isBuilding)
    }

    private var copyButton: some View {
        Button {
            copy()
        } label: {
            Label(
                copied ? "Copied" : (format == .pdf ? "Copy as text" : "Copy \(format.label)"),
                systemImage: copied ? "checkmark.circle.fill" : "doc.on.clipboard"
            )
        }
        .disabled(resolvedSessions.isEmpty || isBuilding)
    }

    private func applyRange() {
        guard case .range = scope else { return }
        let from = min(rangeFrom, rangeTo)
        let to = max(rangeFrom, rangeTo)
        scope = .range(from: from, to: to)
    }

    /// Build the file, write it to temp, and open the native share
    /// sheet (AirDrop, Messages, Mail, Save to Files, Print). The data
    /// is snapshotted here on the main thread; the file (PDF layout,
    /// years of CSV rows) is built on a background queue while the
    /// Share button shows a spinner.
    private func share() {
        guard !isBuilding else { return }
        isBuilding = true
        let job = ExportJob(store: store, scope: scope)
        let format = format
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try job.file(format: format).temporaryURL() }
            DispatchQueue.main.async {
                isBuilding = false
                switch result {
                case .success(let url):
                    shareURL = url
                    showingShare = true
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Copy the format's text to the clipboard (PDF copies its
    /// plain-text summary — see `WorkoutExport.copyText`). Built off the
    /// main thread like Share.
    private func copy() {
        guard !isBuilding else { return }
        isBuilding = true
        let job = ExportJob(store: store, scope: scope)
        let format = format
        DispatchQueue.global(qos: .userInitiated).async {
            let text = job.copyText(format: format)
            DispatchQueue.main.async {
                UIPasteboard.general.string = text
                isBuilding = false
                copied = true
            }
        }
    }
}
