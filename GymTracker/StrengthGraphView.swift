import SwiftUI
import Charts

/// Strength graph — Robinhood P&L style.
///
/// Past = actual estimated 1RMs from logged sessions (Epley), current =
/// the latest value, future = a dashed projected line. The projection is a
/// linear fit to the recent trend, tapered so it flattens toward an
/// asymptote — it is labelled as a projection ("where you could be if you
/// stay consistent"), never a guarantee. All computed on-device from local
/// history; nothing leaves the device. iOS 17.0 deployment target
/// (Swift Charts is iOS 16+).
///
/// A point on the graph. `isProjection` marks the dashed future line.
struct GraphPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let value: Double
    let isProjection: Bool
}

struct StrengthGraphView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var range: TimeRange = .threeMonths
    @State private var selection: LiftSelection = .overall
    @State private var scrubDate: Date?
    @State private var exportRequest: ExportRequest?

    enum TimeRange: String, CaseIterable {
        case oneWeek = "1W"
        case oneMonth = "1M"
        case threeMonths = "3M"
        case sixMonths = "6M"
        case oneYear = "1Y"
        case all = "All"

        /// Days of history shown (nil = everything).
        var days: Int? {
            switch self {
            case .oneWeek: return 7
            case .oneMonth: return 30
            case .threeMonths: return 90
            case .sixMonths: return 180
            case .oneYear: return 365
            case .all: return nil
            }
        }

        /// How far forward the projection runs (matches the range so the
        /// chart shows roughly equal past and future).
        var horizonDays: Int {
            days ?? 365
        }
    }

    /// Overall (sum of the main lifts) or one lift.
    enum LiftSelection: Hashable {
        case overall
        case exercise(id: String, name: String)

        var label: String {
            switch self {
            case .overall: return "Overall"
            case .exercise(_, let name): return name
            }
        }
    }

    /// Main lifts (big compounds) — the per-exercise picker only shows
    /// the ones with logged data. Variants of a lift share a picker row
    /// only by exact exercise id; the library name is the label.
    private static let mainLiftIDs: [String] = [
        "squat", "leg-press", "deadlift", "hip-thrust",
        "barbell-bench", "dumbbell-bench", "flat-bench",
        "cable-row", "barbell-row", "dumbbell-row",
        "lat-pulldown", "pull-up",
        "overhead-press", "barbell-ohp",
    ]

    /// Muscle groups for the Overall number (same grouping as History's
    /// Overall Strength score): best 1RM per group, carried forward, summed.
    /// Compound lifts only — biceps/triceps are isolation lifts with no
    /// valid 1RM (Gap 7), so they are not part of the Overall number.
    private static let overallGroups: [(MuscleGroup, [String])] = [
        (.quads, ["squat", "leg-press", "hack-squat"]),
        (.chest, ["barbell-bench", "dumbbell-bench", "flat-bench"]),
        (.back, ["deadlift", "lat-pulldown", "barbell-row", "cable-row", "dumbbell-row"]),
        (.shoulders, ["overhead-press", "barbell-ohp"]),
    ]

    var body: some View {
        // D16 (2026-11-10): the empty state used to pin to the top with
        // ~45% dead black below it. The GeometryReader measures the
        // viewport so the empty state can fill the space under the
        // header/pickers and centre itself in it — copy unchanged, no
        // invented data.
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerView
                    liftPicker
                    rangePicker
                    if actualPoints.isEmpty {
                        emptyStateView
                            .frame(maxWidth: 640, alignment: .leading)
                            .frame(maxWidth: .infinity, minHeight: max(200, geo.size.height - 220), alignment: .center)
                    } else {
                        chartView
                        projectionNoteView
                    }
                }
                // Same 16pt sides/top as before; the bottom is the shared
                // LayoutClearance rule (Debug Pass 2) so the projection note
                // scrolls clear of the floating menu button — and of the
                // rest-timer panel while a rest runs. The old uniform 16pt
                // padding left the last lines under the button.
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, LayoutClearance.bottom(restActive: store.isRestActive))
            }
        }
        .navigationTitle("Strength")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Export what this screen is showing: the selected lift's
            // history, or the selected range when Overall is picked.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportRequest = ExportRequest(initialScope: graphExportScope)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Export \(selection.label) history")
            }
        }
        .sheet(item: $exportRequest) { request in
            ExportSheet(request: request)
        }
    }

    /// The export scope for the current selection: a single lift's
    /// history, or the graph's selected range for Overall ("All" range
    /// exports everything).
    private var graphExportScope: ExportScope {
        switch selection {
        case .exercise(let id, let name):
            return .exercise(id: id, name: name)
        case .overall:
            if let cutoff = rangeCutoff {
                return .range(from: cutoff, to: Date())
            }
            return .all
        }
    }

    // MARK: - Header (Robinhood-style: current value + change)

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selection.label)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            if let current = actualPoints.last?.value {
                Text(formatted(current))
                    .font(.system(size: 36, weight: .bold))
                if let change = rangeChange {
                    HStack(spacing: 6) {
                        Text(changeText(change))
                        Text("(\(changePercentText(change)))")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(trendColor)
                }
            } else {
                Text("—")
                    .font(.system(size: 36, weight: .bold))
            }
            Text("Estimated max lift · \(store.settings.weightUnit.label)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// Change (latest − first) over the selected range, in display units.
    private var rangeChange: Double? {
        guard let first = actualPoints.first?.value,
              let last = actualPoints.last?.value,
              actualPoints.count > 1 else { return nil }
        return last - first
    }

    private func changeText(_ change: Double) -> String {
        let sign = change >= 0 ? "+" : ""
        return "\(sign)\(formatted(change))"
    }

    private func changePercentText(_ change: Double) -> String {
        guard let first = actualPoints.first?.value, first > 0 else { return "—" }
        let pct = change / first * 100
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", pct))%"
    }

    /// Green when trending up over the range, red when down (Robinhood).
    private var trendColor: Color {
        guard let change = rangeChange else { return Theme.vividGreen }
        return change >= 0 ? Theme.vividGreen : Theme.vividRed
    }

    private func formatted(_ value: Double) -> String {
        let unit = store.settings.weightUnit
        let display = unit.displayValue(for: value) ?? value
        return "\(roundedWeightText(display)) \(unit.label)"
    }

    // MARK: - Pickers

    private var liftPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                liftChip(.overall)
                ForEach(availableLifts, id: \.id) { lift in
                    liftChip(.exercise(id: lift.id, name: lift.name))
                }
            }
            .padding(.trailing, 16)
        }
        // D38 (2026-11-10): trailing fade so the last chip reads as
        // scrollable, not clipped off at the edge.
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [Theme.background.opacity(0), Theme.background],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 24)
            .allowsHitTesting(false)
        }
    }

    /// The chip label: the full "Seated DB Overhead Press" ran off the
    /// right edge with no scroll cue — the chip alone shortens to
    /// "Seated DB OHP" (D38). The chart header / detail keep the full
    /// name; only the chip shortens.
    private func chipLabel(for lift: LiftSelection) -> String {
        lift.label == "Seated DB Overhead Press" ? "Seated DB OHP" : lift.label
    }

    private func liftChip(_ lift: LiftSelection) -> some View {
        Button {
            selection = lift
            scrubDate = nil
        } label: {
            Text(chipLabel(for: lift))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selection == lift ? Color.accentColor : Theme.cardElevated)
                .foregroundStyle(selection == lift ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(TimeRange.allCases, id: \.self) { r in
                Text(r.rawValue).tag(r)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: range) { _, _ in scrubDate = nil }
    }

    // MARK: - Chart

    private var chartView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                // Actual (past + current) — solid line + area fill.
                ForEach(actualPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Strength", point.value)
                    )
                    .foregroundStyle(trendColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                ForEach(actualPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Strength", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [trendColor.opacity(0.25), trendColor.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
                // Projection — dashed, faded.
                ForEach(projectionPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Strength", point.value)
                    )
                    .foregroundStyle(trendColor.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                // Current point.
                if let last = actualPoints.last {
                    PointMark(
                        x: .value("Date", last.date),
                        y: .value("Strength", last.value)
                    )
                    .foregroundStyle(trendColor)
                    .symbolSize(60)
                }
                // Scrub rule + dot.
                if let scrub = scrubDate, let val = scrubbedValue(for: scrub) {
                    RuleMark(x: .value("Date", scrub))
                        .foregroundStyle(Theme.secondaryText)
                    PointMark(
                        x: .value("Date", scrub),
                        y: .value("Strength", val)
                    )
                    .foregroundStyle(trendColor)
                    .symbolSize(50)
                }
            }
            .chartXSelection(value: $scrubDate)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 1)) { value in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Theme.border)
                    AxisValueLabel()
                }
            }
            .frame(height: 220)
            // Scrub readout.
            if let scrub = scrubDate, let val = scrubbedValue(for: scrub) {
                HStack {
                    Text(scrub, format: .dateTime.month(.abbreviated).day().year())
                    Spacer()
                    Text(formatted(val))
                        .fontWeight(.semibold)
                    if isProjectionDate(scrub) {
                        Text("Projected")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .font(.subheadline)
            } else {
                HStack {
                    Text("Past")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text("Drag across the line to scrub")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        // The chart is the visual anchor of this screen — it gets the
        // same card treatment as every other content block.
        .padding()
        .themeCard()
    }

    /// Y domain with padding; never degenerate (flat line gets headroom).
    private var yDomain: ClosedRange<Double> {
        var all: [Double] = []
        for p in actualPoints { all.append(p.value) }
        for p in projectionPoints { all.append(p.value) }
        guard let minV = all.min(), let maxV = all.max() else { return 0...100 }
        var lo = minV * 0.92
        var hi = maxV * 1.06
        if hi - lo < 10 {
            let mid = (lo + hi) / 2
            lo = mid - 5
            hi = mid + 5
        }
        if lo < 0 { lo = 0 }
        return lo...hi
    }

    /// Nearest point value (actual or projection) to a scrubbed date.
    private func scrubbedValue(for date: Date) -> Double? {
        var best: GraphPoint?
        var bestGap = Double.greatestFiniteMagnitude
        for p in actualPoints {
            let gap = abs(p.date.timeIntervalSince(date))
            if gap < bestGap { bestGap = gap; best = p }
        }
        for p in projectionPoints {
            let gap = abs(p.date.timeIntervalSince(date))
            if gap < bestGap { bestGap = gap; best = p }
        }
        return best?.value
    }

    private func isProjectionDate(_ date: Date) -> Bool {
        guard let lastActual = actualPoints.last?.date else { return false }
        return date > lastActual
    }

    private var projectionNoteView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Projected — where you could be if you stay consistent")
                .font(.caption.weight(.semibold))
            Text("The dashed line extends your recent rate of progress forward and tapers off over time, so it flattens instead of running away. It is a projection, not a guarantee — strength gains slow as you get stronger.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No strength data yet")
                .font(.headline)
            Text("Finish a workout from Today and your estimated max lift will show up here — past, current, and where you could be if you stay consistent.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Data (on-device, from local sessions)

    /// Main lifts that have at least one logged set, by library name.
    private var availableLifts: [(id: String, name: String)] {
        var seen: [String: String] = [:]
        for session in store.sessions {
            for exercise in session.exercises {
                guard Self.mainLiftIDs.contains(exercise.exerciseId) else { continue }
                let hasWeight = exercise.sets.contains { $0.done && ($0.weightLb ?? 0) > 0 }
                guard hasWeight else { continue }
                if seen[exercise.exerciseId] == nil {
                    let name = ExerciseLibrary.byId(exercise.exerciseId)?.name ?? exercise.name
                    seen[exercise.exerciseId] = name
                }
            }
        }
        var lifts: [(id: String, name: String)] = []
        for id in Self.mainLiftIDs where seen[id] != nil {
            lifts.append((id: id, name: seen[id]!))
        }
        return lifts
    }

    /// Earliest date shown for the selected range (nil = everything).
    private var rangeCutoff: Date? {
        guard let days = range.days else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }

    /// Convert a stored lb value to the user's display unit.
    private func displayValue(_ lb: Double) -> Double {
        store.settings.weightUnit.displayValue(for: lb) ?? lb
    }

    /// Best valid Epley 1RM for one exercise in one session — delegated
    /// to the store's shared gate (compound lifts, ≤10-rep sets only),
    /// so the graph, History, and the per-exercise sheet can never
    /// disagree about a session's max.
    private func sessionOneRM(session: SessionLog, exerciseId: String) -> Double? {
        store.sessionOneRepMax(session: session, exerciseId: exerciseId)
    }

    /// Actual (past + current) points for the selection, within the range.
    /// One point per day (best that day). Explicit loops — the chained
    /// flatMap/filter/map forms time out the Swift 6 type checker.
    private var actualPoints: [GraphPoint] {
        let cutoff = rangeCutoff
        let sessions = store.sessions.sorted { $0.date < $1.date }
        switch selection {
        case .overall:
            return overallPoints(sessions: sessions, cutoff: cutoff)
        case .exercise(let id, _):
            return exercisePoints(sessions: sessions, cutoff: cutoff, exerciseId: id)
        }
    }

    private func exercisePoints(sessions: [SessionLog], cutoff: Date?, exerciseId: String) -> [GraphPoint] {
        var byDay: [Date: Double] = [:]
        let calendar = Calendar.current
        for session in sessions {
            if let cutoff, session.date < cutoff { continue }
            guard let value = sessionOneRM(session: session, exerciseId: exerciseId) else { continue }
            let day = calendar.startOfDay(for: session.date)
            if let existing = byDay[day] {
                byDay[day] = max(existing, value)
            } else {
                byDay[day] = value
            }
        }
        var points: [GraphPoint] = []
        for day in byDay.keys.sorted() {
            points.append(GraphPoint(date: day, value: displayValue(byDay[day]!), isProjection: false))
        }
        return points
    }

    private func overallPoints(sessions: [SessionLog], cutoff: Date?) -> [GraphPoint] {
        var carry: [MuscleGroup: Double] = [:]
        var byDay: [Date: Double] = [:]
        let calendar = Calendar.current
        for session in sessions {
            if let cutoff, session.date < cutoff { continue }
            for (muscle, ids) in Self.overallGroups {
                var best: Double = 0
                for id in ids {
                    if let v = sessionOneRM(session: session, exerciseId: id), v > best {
                        best = v
                    }
                }
                if best > 0 { carry[muscle] = best }
            }
            var total: Double = 0
            for (_, v) in carry { total += v }
            guard total > 0 else { continue }
            let day = calendar.startOfDay(for: session.date)
            if let existing = byDay[day] {
                byDay[day] = max(existing, total)
            } else {
                byDay[day] = total
            }
        }
        var points: [GraphPoint] = []
        for day in byDay.keys.sorted() {
            points.append(GraphPoint(date: day, value: displayValue(byDay[day]!), isProjection: false))
        }
        return points
    }

    /// Projected (future) points: a least-squares fit to the recent trend,
    /// tapered so it flattens toward an asymptote and never runs away.
    /// With fewer than 2 actual points the projection is flat at the last
    /// value (so the dashed line still renders).
    private var projectionPoints: [GraphPoint] {
        guard let last = actualPoints.last else { return [] }
        let points = actualPoints
        var slopePerDay: Double = 0
        // Fit only the last 12 weeks (shared `projectionFitWindowDays`):
        // the least-squares slope over the whole selected range carries
        // stale novice gains forward and overstates where a trained
        // lifter is heading. Fewer than 2 points in the window = flat.
        let fitCutoff = Calendar.current.date(byAdding: .day, value: -projectionFitWindowDays, to: last.date) ?? last.date
        let fitPoints = points.filter { $0.date >= fitCutoff }
        if fitPoints.count >= 2 {
            let firstDate = fitPoints[0].date
            var sumX: Double = 0, sumY: Double = 0, sumXY: Double = 0, sumXX: Double = 0
            for p in fitPoints {
                let x = p.date.timeIntervalSince(firstDate) / 86400.0
                sumX += x
                sumY += p.value
                sumXY += x * p.value
                sumXX += x * x
            }
            let n = Double(fitPoints.count)
            let denom = n * sumXX - sumX * sumX
            if denom != 0 {
                slopePerDay = (n * sumXY - sumX * sumY) / denom
            }
            // A negative slope (getting weaker) projects flat, not a
            // decline — the projection is "if you stay consistent".
            if slopePerDay < 0 { slopePerDay = 0 }
        }
        // Taper: gain(t) = slope * 180 * (1 - exp(-t/180)). Starts at the
        // recent rate, decays exponentially, asymptotes at slope*180
        // (six months of progress) — it flattens, never runs away.
        // Capped at a realistic ceiling: no more than the
        // experience-scaled monthly rate (novice 4%/mo, intermediate
        // 2%/mo, advanced 1%/mo — shared `projectionMonthlyCapRate`),
        // goal-dependent (Build muscle runs at 0.75x — hypertrophy
        // sits at the lower end of the strength-gain band), and never
        // more than 30% total, so a steep short-term trend (or a
        // beginner's first weeks) can't inflate the line.
        // The projection stays honest about the rate of gain.
        let horizon = range.horizonDays
        let monthlyRate = projectionMonthlyCapRate(for: store.profile?.experience, goal: store.profile?.goal)
        let maxGain = last.value * min(projectionMaxTotalGain, monthlyRate * Double(horizon) / 30.0)
        let steps = max(1, horizon / 7)
        var projected: [GraphPoint] = []
        for i in 1...steps {
            let t = Double(i * 7)
            if t > Double(horizon) { break }
            let gain = min(slopePerDay * 180.0 * (1.0 - exp(-t / 180.0)), maxGain)
            let date = last.date.addingTimeInterval(t * 86400.0)
            projected.append(GraphPoint(date: date, value: last.value + gain, isProjection: true))
        }
        return projected
    }
}
