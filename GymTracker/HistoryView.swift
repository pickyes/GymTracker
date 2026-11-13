import SwiftUI

/// The Calendar page (History and Calendar merged, Nov 12): the month
/// grid on top, the chosen day's workouts under it (tap one for its
/// details), then the strength links, this week's stats, records, and
/// every session.
struct HistoryView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    /// The day chosen in the grid (shared with the open Duo's other page).
    @Binding var selectedDay: Date
    @State private var selectedSessionID: UUID?
    @State private var exportRequest: ExportRequest?
    /// The tool tiles open these (buttons, so the list adds no "›").
    @State private var showStrengthGraph = false
    @State private var showBody = false
    /// D6 (2026-11-10): the session awaiting delete confirmation —
    /// set by the row swipe action or the detail trash button.
    @State private var sessionToDelete: SessionLog?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Open Duo: the chosen day lives on the other page, so this page
    /// doesn't repeat it.
    @Environment(\.duoWide) private var duoWide
    @Environment(\.duoSwapped) private var duoSwapped
    /// On the open Duo's right page the swap and menu buttons sit in the
    /// bottom-right corner; the summary and tiles stop short of them.
    private var cornerButtonsInset: CGFloat { duoWide && !duoSwapped ? 76 : 0 }

    /// Sidebar visibility, persisted in the shared App Group suite (the
    /// migration in WorkoutStore.init moves this key there with the rest).
    /// The sidebar hides its toolbar, so the system sidebar toggle is
    /// unreachable there — the detail pane carries an explicit toggle
    /// instead (P1-3). Default visible.
    @AppStorage("gymtracker.historySidebarVisible.v1", store: SharedDefaults.shared) private var sidebarVisible = true

    /// The split view's column visibility, driven by the persisted Bool.
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarVisible ? .all : .detailOnly },
            set: { sidebarVisible = ($0 != .detailOnly) }
        )
    }

    /// The page title lines up with the content margin (16pt compact).
    /// On the open display the title's "H" was clipped by the screen's
    /// rounded corner at 16pt, so regular width gets a little more room.
    private var titleLeading: CGFloat { horizontalSizeClass == .regular ? 24 : 16 }

    var body: some View {
        // One list, always — the top links (Strength graph, Body),
        // the sessions, and the stats sections render from
        // real store data even with zero sessions (zeros and an honest
        // "no sessions yet" row), so the page is never just the link
        // rows (DaRon, 21:38; top links + sessions lead, 22:58).
        // Two-pane when open (regular width); collapses to a single
        // navigable column on the outer display automatically.
        sessionsSplitView
            // Fold (Debug Pass 2): the title leading (16↔24pt) and the
            // split view's column collapse/expand flip discretely on the
            // size class, which used to snap with no animation. Animate
            // them on the shared fold spring so History glides with the
            // pose instead of popping.
            .animation(FoldAnimation.morph, value: horizontalSizeClass)
            .disableVerticalBar()
            .sheet(item: $exportRequest) { request in
                ExportSheet(request: request)
            }
    }

    private var sessionsSplitView: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            List(selection: $selectedSessionID) {
                // Title lines up with the list rows below it (same 16pt
                // leading), not flush to the edge.
                PageTitle(text: "Calendar")
                    // In the clock's row, like Today (Nov 12).
                    .padding(.top, 30)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: titleLeading, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                // Calendar, legend, and the month at a glance (Nov 12
                // layout DaRon picked: calendar with the stuff below it).
                CalendarView(externalSelection: $selectedDay, gridOnly: true, showsMonthSummary: true,
                             summaryTrailingInset: cornerButtonsInset)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                // Folded there's no other page: the chosen day and the
                // training heatmap sit here instead.
                if !duoWide {
                    Section {
                        selectedDayRows
                    } header: {
                        Text(selectedDay, format: .dateTime.weekday(.wide).month().day())
                    }
                }
                toolTiles
                    .padding(.trailing, cornerButtonsInset)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                if !duoWide {
                    TrainingHeatmap(selectedDay: $selectedDay)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
                Section("Personal records") {
                    personalRecordsView
                }
                Section("This week") {
                    historyStatsHeader
                }
                Section("All sessions") {
                    if store.sessions.isEmpty {
                        Text("No sessions yet — finish a workout from Today and it will show up here.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(store.sessions) { session in
                        SessionRowView(session: session)
                            .tag(session.id)
                            // D6: swipe to delete — the only way to remove
                            // a saved session (deleteSession existed with
                            // zero callers). Confirms before deleting.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { sessionToDelete = session } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                // Bottom breathing room (shared LayoutClearance rule,
                // Debug Pass 2): the last row must scroll fully into
                // view clear of the floating menu button — and of the
                // rest-timer panel above it while a rest runs. The old
                // 40pt spacer was short of the 96pt menu-button value
                // (the FAB's top is 41–60pt above the list's bottom
                // edge depending on the safe area), so the last row
                // could sit under the button at scroll-bottom.
                Color.clear
                    .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .ignoresSafeArea(edges: .top)
            .infinityTopEdge()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showStrengthGraph) { StrengthGraphView() }
            .navigationDestination(isPresented: $showBody) { BodyView() }
        } detail: {
            Group {
                if let session = store.sessions.first(where: { $0.id == selectedSessionID }) {
                    SessionDetailView(session: session)
                } else {
                    ContentUnavailableView("Select a workout", systemImage: "clock.arrow.circlepath")
                        .navigationTitle("History")
                        // D9: restore the latest session whenever the
                        // empty detail appears in regular width (page
                        // switch after a compact back-nav clear, pose
                        // flip, or any other nil-ing of the selection).
                        .onAppear {
                            if horizontalSizeClass == .regular, selectedSessionID == nil {
                                selectedSessionID = store.sessions.first?.id
                            }
                        }
                }
            }
            .toolbar {
                // Explicit sidebar toggle on the detail pane (P1-3): the
                // sidebar's own toolbar is hidden, so this is the only
                // way to HIDE the session list. When the sidebar is
                // already hidden, NavigationSplitView injects its own
                // system toggle — D8 (2026-11-10): showing this one too
                // put TWO toggles side by side. So it renders only
                // while the sidebar is visible.
                ToolbarItem(placement: .topBarLeading) {
                    if sidebarVisible {
                        Button {
                            sidebarVisible.toggle()
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .accessibilityLabel("Hide session list")
                    }
                }
            }
        }
        .onAppear {
            // Open on the latest session (sessions are newest-first) —
            // only when two-pane. In compact (folded, or kept at the
            // folded width on the open Duo) a selection pushes the
            // detail over the list, so the page must open on the list.
            if horizontalSizeClass == .regular, selectedSessionID == nil {
                selectedSessionID = store.sessions.first?.id
            }
        }
        .onChange(of: horizontalSizeClass) { _, newValue in
            if newValue == .compact { selectedSessionID = nil }
        }
        // D9: pose flip while the empty detail is showing — restore the
        // latest session when the width becomes regular again.
        .onChange(of: horizontalSizeClass) { _, _ in
            if horizontalSizeClass == .regular, selectedSessionID == nil {
                selectedSessionID = store.sessions.first?.id
            }
        }
        // D6: one delete confirmation for the swipe action (the detail
        // trash button uses the detail view's own dialog — same wording).
        .confirmationDialog("Delete this workout?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    store.deleteSession(id: session.id)
                    if selectedSessionID == session.id { selectedSessionID = nil }
                    sessionToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
        } message: {
            Text("This removes the saved session and its sets from History. This can't be undone.")
        }
    }

    // MARK: - Tools (Strength graph, Body, Export)

    /// One row of three tiles instead of three list rows.
    private var toolTiles: some View {
        HStack(spacing: 10) {
            Button { showStrengthGraph = true } label: {
                toolTile("Strength graph", systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.plain)
            Button { showBody = true } label: {
                toolTile("Body", systemImage: "figure.stand")
            }
            .buttonStyle(.plain)
            // Export the whole history, or a date range — the sheet's
            // scope picker offers both.
            Button {
                exportRequest = ExportRequest(
                    initialScope: .all,
                    scopeOptions: [
                        .all,
                        .range(from: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(), to: Date()),
                    ]
                )
            } label: {
                toolTile("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Export history")
        }
    }

    private func toolTile(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .themeCard(cornerRadius: 16)
        .contentShape(Rectangle())
    }

    // MARK: - Chosen day

    /// The chosen day's workouts (tap to open), or what was planned.
    @ViewBuilder
    private var selectedDayRows: some View {
        let cal = Calendar.current
        let daySessions = store.sessions.filter { cal.isDate($0.date, inSameDayAs: selectedDay) }
        if !daySessions.isEmpty {
            ForEach(daySessions) { session in
                SessionRowView(session: session)
                    .tag(session.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { sessionToDelete = session } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        } else if let plan = store.programDay(for: selectedDay) {
            let isPast = selectedDay < cal.startOfDay(for: Date())
            VStack(alignment: .leading, spacing: 6) {
                Text(isPast ? "Missed · \(plan.title)" : "Planned · \(plan.title)")
                    .font(.headline)
                    .foregroundStyle(isPast ? Theme.vividOrange : Color.accentColor)
                ForEach(plan.exercises) { template in
                    HStack {
                        Text(template.name).font(.subheadline)
                        Spacer()
                        Text("\(template.sets) × \(template.repRange)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .padding(.vertical, 4)
        } else {
            Text(selectedDay < cal.startOfDay(for: Date()) ? "Nothing logged that day." : "Rest day.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Stats header (Fitbod weekly set targets + overall strength)

    private var historyStatsHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Leading stat", selection: statBinding) {
                ForEach(HistoryStatChoice.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            leadingStatView
            statRow(label: "Workouts this week", value: "\(workoutsThisWeek)")

            weeklyTargetsView
            strengthScoreView
        }
    }

    /// The user-chosen leading stat (one row). Extracted so the stats
    /// header stays a small, fast-to-type-check expression.
    private var leadingStatView: some View {
        Group {
            switch store.settings.historyStat {
            case .volume:
                statRow(label: "Volume this week",
                        value: formattedVolumeLb(weeklyVolume))
            case .bestWeight:
                statRow(label: "Best lift this week",
                        value: bestLiftThisWeek ?? "—")
            case .oneRepMax:
                statRow(label: "Best max lift",
                        value: bestOneRepMax ?? "—")
            case .streak:
                statRow(label: "Weekly streak",
                        value: "\(store.weeklyStreak) week\(store.weeklyStreak == 1 ? "" : "s")")
            }
        }
    }

    private var statBinding: Binding<HistoryStatChoice> {
        Binding(
            get: { store.settings.historyStat },
            set: { var s = store.settings; s.historyStat = $0; store.updateSettings(s) }
        )
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(.headline)
        }
    }

    private var weeklyVolume: Double {
        store.volume(from: weekStartDate(for: Date()), to: Date())
    }

    /// Best lift this week, compared by valid 1RM — not by raw load.
    /// Raw weight mixes incomparable lifts (a 200 lb leg press always
    /// "beats" a 100 lb bench; a 45 lb dumbbell is per-hand). Only
    /// compound lifts with a ≤10-rep set qualify (shared 1RM gate);
    /// the displayed set is the one behind that best 1RM.
    private var bestLiftThisWeek: String? {
        let weekStart = weekStartDate(for: Date())
        var best: (exercise: ExerciseLog, set: SetLog, oneRM: Double)?
        for session in store.sessions where session.date >= weekStart {
            for exercise in session.exercises {
                guard ExerciseLibrary.byId(exercise.exerciseId, plus: store.customExercises)?.isCompound == true else { continue }
                for set in exercise.sets where set.done && set.kind != .warmup {
                    guard let weight = set.weightLb,
                          let oneRM = validOneRepMax(weightLb: weight, reps: set.reps, isCompound: true) else { continue }
                    if best == nil || oneRM > best!.oneRM {
                        best = (exercise: exercise, set: set, oneRM: oneRM)
                    }
                }
            }
        }
        guard let best else { return nil }
        let template = ExerciseTemplate(id: best.exercise.exerciseId, name: best.exercise.name, sets: 1,
                                        repRange: "", topReps: 1, defaultWeightLb: nil,
                                        isPair: best.exercise.isPair, weightNote: nil, cues: nil)
        return "\(best.exercise.name): \(store.displayWeightLabel(best.set.weightLb, isPair: best.exercise.isPair, for: template)) × \(best.set.reps)"
    }

    private var bestOneRepMax: String? {
        // One lookup pass instead of re-flattening the sessions per id.
        var byId: [String: ExerciseLog] = [:]
        for session in store.sessions {
            for exercise in session.exercises where byId[exercise.exerciseId] == nil {
                byId[exercise.exerciseId] = exercise
            }
        }
        var best: (name: String, oneRM: Double, isPair: Bool)?
        for id in byId.keys {
            guard let oneRM = store.oneRepMax(for: id) else { continue }
            let exercise = byId[id]
            let name = exercise?.name ?? id
            let isPair = exercise?.isPair ?? false
            if best == nil || oneRM > best!.oneRM {
                best = (name, oneRM, isPair)
            }
        }
        guard let best else { return nil }
        let template = ExerciseTemplate(id: "", name: best.name, sets: 1, repRange: "", topReps: 1,
                                        defaultWeightLb: nil, isPair: best.isPair, weightNote: nil, cues: nil)
        return "\(best.name): \(store.displayWeightLabel(best.oneRM, isPair: best.isPair, for: template))"
    }

    private var workoutsThisWeek: Int {
        store.sessions.filter { $0.date >= weekStartDate(for: Date()) }.count
    }

    /// Best lift per muscle group, from logged sessions (real data only).
    /// Same benchmarks as the Overall Strength score — compound lifts
    /// only, so the arm rows are gone: curls and pushdowns are
    /// isolation lifts with no valid 1RM (Gap 7), and a "record" for
    /// them would be a made-up number.
    private var personalRecords: [(muscle: MuscleGroup, name: String, weight: String)] {
        var byId: [String: ExerciseLog] = [:]
        for session in store.sessions {
            for exercise in session.exercises where byId[exercise.exerciseId] == nil {
                byId[exercise.exerciseId] = exercise
            }
        }
        let benchmarks: [(MuscleGroup, [String])] = [
            (.quads, ["squat", "leg-press", "hack-squat"]),
            (.chest, ["barbell-bench", "dumbbell-bench", "flat-bench"]),
            (.back, ["deadlift", "lat-pulldown", "barbell-row", "cable-row", "dumbbell-row"]),
            (.shoulders, ["overhead-press", "barbell-ohp"]),
        ]
        var rows: [(muscle: MuscleGroup, name: String, weight: String)] = []
        for (muscle, ids) in benchmarks {
            var best: (name: String, oneRM: Double, isPair: Bool)?
            for id in ids {
                guard let oneRM = store.oneRepMax(for: id) else { continue }
                let exercise = byId[id]
                let name = exercise?.name ?? id
                let isPair = exercise?.isPair ?? false
                if best == nil || oneRM > best!.oneRM {
                    best = (name, oneRM, isPair)
                }
            }
            guard let best else { continue }
            let template = ExerciseTemplate(id: "", name: best.name, sets: 1, repRange: "", topReps: 1,
                                            defaultWeightLb: nil, isPair: best.isPair, weightNote: nil, cues: nil)
            rows.append((muscle: muscle, name: best.name,
                         weight: store.displayWeightLabel(best.oneRM, isPair: best.isPair, for: template)))
        }
        return rows
    }

    private var personalRecordsView: some View {
        Group {
            if personalRecords.isEmpty {
                Text("No records yet — finish a workout and your best lifts will show up here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(personalRecords, id: \.name) { record in
                    HStack {
                        Text(record.muscle.label)
                            .font(.subheadline)
                        Spacer()
                        Text("\(record.name): \(record.weight)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }

    /// Weekly set targets (Fitbod pattern): a progress ring + per-group
    /// rows. Targets are derived live from the active program
    /// (store.plannedWeeklyTargets) — never a fixed constant — so the
    /// total is the sum of its parts by construction.
    private var weeklyTargetsView: some View {
        let counts = store.setsByTargetGroupThisWeek()
        let targets = store.plannedWeeklyTargets()
        let total = counts.push + counts.pull + counts.legs + counts.core
        let target = targets.total
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                WeeklyRing(progress: target > 0 ? min(1, Double(total) / Double(target)) : 0)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekly set target")
                        .font(.headline)
                    Text("\(total)/\(target) working sets")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            ForEach(weeklyTargetRows(counts: counts, targets: targets), id: \.muscle) { row in
                HStack {
                    Text(row.muscle.label)
                        .font(.caption)
                    Spacer()
                    Text("\(row.count)/\(row.target)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    ProgressView(value: min(1, Double(row.count) / Double(max(row.target, 1))))
                        .frame(width: 80)
                }
            }
        }
    }

    private func weeklyTargetRows(counts: (push: Int, pull: Int, legs: Int, core: Int), targets: WeeklyTargets) -> [(muscle: MuscleGroup, count: Int, target: Int)] {
        // Push / Pull / Legs / Core, in that order. A group with no
        // planned sets (e.g. no core in the program, or the no-program
        // fallback) has no target row — a 0 target would read as failure.
        [
            (muscle: .chest, count: counts.push, target: targets.push),
            (muscle: .back, count: counts.pull, target: targets.pull),
            (muscle: .quads, count: counts.legs, target: targets.legs),
            (muscle: .core, count: counts.core, target: targets.core),
        ].filter { $0.target > 0 }
    }

    /// Overall Strength score (Fitbod pattern): 0–100 from best lifts
    /// relative to bodyweight, with per-muscle bars. Nil when bodyweight
    /// is unknown or nothing is logged — no invented fallback.
    private var strengthScoreView: some View {
        let score = overallStrengthScore
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Overall Strength")
                    .font(.headline)
                Spacer()
                Text(score.map { "\($0)" } ?? "—")
                    .font(.headline)
            }
            ProgressView(value: score.map { Double($0) / 100 } ?? 0)
            if store.bodyWeightLb == nil {
                Text("Enter your bodyweight in Profile to see your score.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Based on \(strengthByMuscle.count) of 4 lifts")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(strengthByMuscle, id: \.muscle) { row in
                HStack {
                    Text(row.muscle.label)
                        .font(.caption)
                    Spacer()
                    Text("\(row.score)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    ProgressView(value: Double(row.score) / 100)
                        .frame(width: 80)
                }
            }
        }
    }

    /// Mean of the per-muscle scores that exist. The mean's denominator
    /// is the number of muscles with a logged lift — adding a fourth
    /// muscle lowers the score when it scores below the old mean, which
    /// is correct execution, not a bug — so the view always shows the
    /// coverage ("based on 3 of 4 lifts") next to the number.
    private var overallStrengthScore: Int? {
        let scores = strengthByMuscle.map { $0.score }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / scores.count
    }

    private var strengthByMuscle: [(muscle: MuscleGroup, score: Int)] {
        // No bodyweight, no score: scoring against an invented 180 lb
        // would present a made-up number as a measurement.
        guard let bodyweight = store.bodyWeightLb, bodyweight > 0 else { return [] }
        // Per-LIFT benchmarks (P2-1 / Gap 9): each lift is scored against
        // its own bodyweight multiple — leg press is not a squat (2.5×),
        // a pulldown is not a deadlift (1.0×), a row is not a deadlift
        // (0.75×), and an overhead press uses the intermediate 0.65×
        // standard (0.6× is intermediate, not advanced). Per-hand dumbbell weights are doubled before
        // comparing, so the multiples below are whole-body multiples
        // (a pair of 45s on DB bench counts as 90 lb, not 45).
        // Biceps/triceps are NOT scored: every lift in those groups is
        // an isolation lift (curls, pushdowns) with no valid 1RM
        // (Gap 7), so scoring them would invent a strength number.
        // The score WILL jump vs the old metric — expected, not a
        // regression: the old metric under-scored pulldowns and rows and
        // over-scored leg press, and compared per-hand DB loads to
        // whole-body multiples without doubling.
        let benchmarks: [(MuscleGroup, [(id: String, multiple: Double)])] = [
            (.quads, [("squat", 1.5), ("leg-press", 2.5), ("hack-squat", 2.0)]),
            (.chest, [("barbell-bench", 1.0), ("dumbbell-bench", 1.0), ("flat-bench", 1.0)]),
            (.back, [("deadlift", 1.75), ("lat-pulldown", 1.0), ("barbell-row", 0.75), ("cable-row", 0.75), ("dumbbell-row", 0.75)]),
            (.shoulders, [("overhead-press", 0.65), ("barbell-ohp", 0.65)]),
        ]
        var rows: [(MuscleGroup, Int)] = []
        for (muscle, lifts) in benchmarks {
            var bestRatio: Double = 0
            for lift in lifts {
                guard let oneRM = store.oneRepMax(for: lift.id) else { continue }
                // Per-hand dumbbell loads are doubled before comparing to
                // the whole-body multiple; barbell/cable/machine loads
                // already are whole-body loads.
                let isPair = ExerciseLibrary.byId(lift.id)?.isPair ?? false
                let total = isPair ? oneRM * 2 : oneRM
                bestRatio = max(bestRatio, total / (bodyweight * lift.multiple))
            }
            guard bestRatio > 0 else { continue }
            rows.append((muscle, min(100, Int(bestRatio * 100))))
        }
        return rows
    }
}

/// One session row in the History list. Extracted so the list body stays
/// a small, fast-to-type-check expression.
struct SessionRowView: View {
    let session: SessionLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(session.dayKey) · \(session.dayTitle)")
                .font(.headline)
                .lineLimit(1)
            Text(session.date, format: .dateTime.weekday(.wide).month().day().year())
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Text("\(pluralised(session.exercises.count, singular: "exercise")) · \(setsDoneText(done: doneSets)) · \(formattedVolumeLb(sessionVolume))")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var doneSets: Int {
        session.exercises.flatMap { $0.sets }.filter { $0.done }.count
    }

    /// Session volume — the ONE volume formula (`volumeLb(for:)`), so a
    /// session row and the weekly total can never disagree.
    private var sessionVolume: Double {
        volumeLb(for: session.exercises)
    }
}

/// A progress ring (Fitbod weekly-target pattern).
struct WeeklyRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.02, progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .bold()
        }
    }
}

struct SessionDetailView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    let session: SessionLog
    @State private var exportRequest: ExportRequest?
    /// D6: delete confirmation for this detail view's trash button.
    /// (HistoryView holds its own sessionToDelete for the swipe path —
    /// the two dialogs share wording and the same store.deleteSession
    /// call; the detail view cannot reach the list's state directly.)
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            Section {
                Text(session.date, format: .dateTime.weekday(.wide).month().day().year().hour().minute())
                if session.finisherDone {
                    Label("Pump finisher done", systemImage: "flame.fill")
                }
            }
            ForEach(session.exercises, id: \.exerciseId) { exercise in
                Section(exercise.name) {
                    ForEach(exercise.sets.indices, id: \.self) { index in
                        let set = exercise.sets[index]
                        HStack {
                            Text("Set \(index + 1)")
                            if set.kind != .working {
                                Text(set.kind.label)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Text(setWeightText(set, exercise: exercise))
                            Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(set.done ? CompletedTint.completedGlyph : Theme.tertiaryText)
                        }
                    }
                }
            }
            // Bottom breathing room, same shared rule as the History
            // list — the detail pane is the RIGHT pane in the open pose,
            // so the floating menu button (and the rest-timer panel
            // while a rest runs) sits over it. The old 32pt spacer left
            // the last set row's trailing weight + checkmark under the
            // button at scroll-bottom.
            Color.clear
                .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .oledList()
        .navigationTitle("\(session.dayKey) · \(session.dayTitle)")
        .toolbar {
            // Export this one workout (CSV / PDF / text / JSON) — the
            // share sheet and copy live in ExportSheet.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportRequest = ExportRequest(initialScope: .session(session))
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Export this workout")
            }
            // D6: delete this session. The detail dismisses itself: once
            // the session is gone HistoryView's detail branch finds no
            // match and shows the empty detail instead.
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityLabel("Delete this workout")
            }
        }
        // D6: delete confirmation (same wording as the list swipe path).
        .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                store.deleteSession(id: session.id)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the saved session and its sets from History. This can't be undone.")
        }
        .sheet(item: $exportRequest) { request in
            ExportSheet(request: request)
        }
    }

    /// Weight text for one logged set — the store's shared formatter
    /// (same rule as Calendar's day detail, unit-override aware).
    private func setWeightText(_ set: SetLog, exercise: ExerciseLog) -> String {
        store.setWeightText(set, exercise: exercise)
    }
}


// MARK: - Training heatmap (Calendar page, Nov 12)

/// The last 14 weeks, one square per day: full accent color for a full
/// workout, faded for a short one, empty for none. Columns are weeks
/// (oldest left), rows are weekdays. Today is ringed; tap a day to pick
/// it on the calendar. The header counts the weekly streak.
struct TrainingHeatmap: View {
    @EnvironmentObject var store: WorkoutStore
    @Binding var selectedDay: Date

    private let weeks = 14
    private let cell: CGFloat = 20
    private let gap: CGFloat = 4

    private var calendar: Calendar { Calendar.current }

    /// The first day shown: the start of the week, 13 weeks before this one.
    private var firstDay: Date {
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: weekStart) ?? weekStart
    }

    /// Sets logged per day over the window.
    private var setsByDay: [Date: Int] {
        var result: [Date: Int] = [:]
        for session in store.sessions where session.date >= firstDay {
            let day = calendar.startOfDay(for: session.date)
            let sets = session.exercises.reduce(0) { $0 + $1.sets.count }
            result[day, default: 0] += max(sets, 1)
        }
        return result
    }

    var body: some View {
        let sets = setsByDay
        let today = calendar.startOfDay(for: Date())
        let streak = store.weeklyStreak
        VStack(alignment: .leading, spacing: 8) {
            Text("Last \(weeks) weeks · \(streak)-week streak")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let day = calendar.date(byAdding: .day, value: week * 7 + weekday, to: firstDay) ?? firstDay
                            square(day: day, sets: sets[day] ?? 0, today: today)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training over the last \(weeks) weeks: \(sets.count) workout days, \(streak)-week streak")
    }

    @ViewBuilder
    private func square(day: Date, sets: Int, today: Date) -> some View {
        if day > today {
            Color.clear.frame(width: cell, height: cell)
        } else {
            // Accent color (DaRon): full for a full workout, faded for a
            // short one.
            let fill: Color = sets == 0 ? Theme.cardElevated
                : (sets >= 12 ? Color.accentColor : Color.accentColor.opacity(0.4))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(fill)
                .frame(width: cell, height: cell)
                .overlay {
                    if day == today {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 1.5)
                    }
                }
                .onTapGesture {
                    withAnimation(AppAnimation.snappy) { selectedDay = day }
                }
        }
    }
}
