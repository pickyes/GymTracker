import SwiftUI
import Charts

/// Progress (Calendar → Progress, beside Strength): how training is
/// trending, from the saved sessions only (on-device, nothing guessed).
/// This month against last, weekly volume and workouts for the last 12
/// weeks, and the lifts that have gone up most.
struct TrainingProgressView: View {
    @EnvironmentObject var store: WorkoutStore
    @Environment(\.fabBottomOffset) private var fabBottomOffset

    private var calendar: Calendar { Calendar.current }
    private var unit: WeightUnit { store.settings.weightUnit }

    // MARK: Data

    private struct Totals { var workouts = 0; var sets = 0; var volumeLb = 0.0 }

    private func doneWorkingSets(_ session: SessionLog) -> Int {
        session.exercises.reduce(0) { $0 + $1.sets.filter { $0.done && $0.kind != .warmup }.count }
    }

    private func totals(from start: Date, to end: Date) -> Totals {
        var t = Totals()
        for s in store.sessions where s.date >= start && s.date < end {
            t.workouts += 1
            t.sets += doneWorkingSets(s)
            t.volumeLb += volumeLb(for: s.exercises)
        }
        return t
    }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    }

    private struct Week: Identifiable {
        let start: Date
        var workouts = 0
        var volumeLb = 0.0
        var id: Date { start }
    }

    /// The last 12 weeks, oldest first (this week last).
    private var weeks: [Week] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        var result: [Week] = (0..<12).reversed().compactMap { back in
            calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek).map { Week(start: $0) }
        }
        for s in store.sessions {
            guard let i = result.lastIndex(where: { s.date >= $0.start }),
                  s.date < (calendar.date(byAdding: .weekOfYear, value: 1, to: result[i].start) ?? .distantFuture)
            else { continue }
            result[i].workouts += 1
            result[i].volumeLb += volumeLb(for: s.exercises)
        }
        return result
    }

    private struct Gain: Identifiable {
        let name: String
        let firstLb: Double
        let latestLb: Double
        var id: String { name }
        var changeLb: Double { latestLb - firstLb }
    }

    /// Best estimated max per exercise in its first session of the last 90
    /// days against its latest one; the five that went up most.
    private var gains: [Gain] {
        let since = calendar.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast
        var first: [String: (Date, Double, String)] = [:]
        var latest: [String: (Date, Double, String)] = [:]
        for s in store.sessions where s.date >= since {
            for ex in s.exercises {
                let best = ex.sets
                    .filter { $0.done && $0.kind != .warmup }
                    .compactMap { set in set.weightLb.map { estimatedOneRepMax(weightLb: $0, reps: set.reps) } }
                    .max()
                guard let best, best > 0 else { continue }
                if first[ex.exerciseId].map({ s.date < $0.0 }) ?? true { first[ex.exerciseId] = (s.date, best, ex.name) }
                if latest[ex.exerciseId].map({ s.date > $0.0 }) ?? true { latest[ex.exerciseId] = (s.date, best, ex.name) }
            }
        }
        return first.compactMap { id, f in
            guard let l = latest[id], l.0 > f.0 else { return nil }
            return Gain(name: l.2, firstLb: f.1, latestLb: l.1)
        }
        .filter { $0.changeLb > 0 }
        .sorted { $0.changeLb > $1.changeLb }
        .prefix(5)
        .map { $0 }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if store.sessions.isEmpty {
                    ContentUnavailableView("No progress yet",
                                           systemImage: "chart.bar.xaxis",
                                           description: Text("Finish a workout from Today and your progress will show up here."))
                        .padding(.top, 40)
                } else {
                    monthCard
                    chartCard(title: "Weekly volume", subtitle: "Last 12 weeks · \(unit.label)") {
                        Chart(weeks) { week in
                            BarMark(x: .value("Week", week.start, unit: .weekOfYear),
                                    y: .value("Volume", displayWeight(week.volumeLb)))
                                .foregroundStyle(Color.accentColor.gradient)
                                .cornerRadius(3)
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        } }
                    }
                    chartCard(title: "Workouts per week", subtitle: "Last 12 weeks") {
                        Chart(weeks) { week in
                            BarMark(x: .value("Week", week.start, unit: .weekOfYear),
                                    y: .value("Workouts", week.workouts))
                                .foregroundStyle(Theme.vividGreen.gradient)
                                .cornerRadius(3)
                        }
                        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                        .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        } }
                    }
                    gainsCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
        }
        .background(Theme.background)
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func displayWeight(_ lb: Double) -> Double {
        unit == .kg ? lb / 2.20462 : lb
    }

    // MARK: Cards

    private var monthCard: some View {
        let now = totals(from: monthStart, to: .distantFuture)
        let lastStart = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        // Last month up to the same day, so a half-done month compares fairly.
        let sameDayLast = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let then = totals(from: lastStart, to: sameDayLast)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This month")
                    .font(.headline)
                Text("Against last month, up to the same day")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) { monthStats(now, then) }
                VStack(alignment: .leading, spacing: 12) { monthStats(now, then) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    @ViewBuilder
    private func monthStats(_ now: Totals, _ then: Totals) -> some View {
        stat("Workouts", "\(now.workouts)", change: Double(now.workouts - then.workouts), format: { "\(Int($0))" })
        stat("Sets", "\(now.sets)", change: Double(now.sets - then.sets), format: { "\(Int($0))" })
        stat("Volume", unitVolumeText(lb: now.volumeLb, unit: unit),
             change: now.volumeLb - then.volumeLb,
             format: { unitVolumeText(lb: $0, unit: unit) })
    }

    private func stat(_ label: String, _ value: String, change: Double, format: (Double) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(change == 0 ? "Same" : (change > 0 ? "▲ " : "▼ ") + format(abs(change)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(change > 0 ? Theme.vividGreen : (change < 0 ? Theme.vividOrange : Theme.secondaryText))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func chartCard<C: View>(title: String, subtitle: String, @ViewBuilder chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            chart().frame(height: 160)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    private var gainsCard: some View {
        let list = gains
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Most improved").font(.headline)
                Text("Estimated max, last 90 days").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if list.isEmpty {
                Text("Log the same lift on two different days and its gain shows up here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(list) { gain in
                    HStack {
                        Text(gain.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(formatWeight(gain.firstLb)) → \(formatWeight(gain.latestLb))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .monospacedDigit()
                        Text("+\(formatWeight(gain.changeLb))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.vividGreen)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard()
    }

    private func formatWeight(_ lb: Double) -> String {
        "\(Int(displayWeight(lb).rounded()))"
    }
}
