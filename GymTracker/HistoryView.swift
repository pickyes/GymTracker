import SwiftUI

/// The Calendar page (History and Calendar merged, Nov 12): the month
/// grid on top, the chosen day's workouts under it (tap one for its
/// details), then the strength links, this week's stats, records, and
/// every session.
struct HistoryView: View {
    @Environment(\.pageTitleTop) private var pageTitleTop
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    /// The day chosen in the grid (shared with the open Duo's other page).
    @Binding var selectedDay: Date
    @State private var selectedSessionID: UUID?
    @State private var exportRequest: ExportRequest?
    /// The tool tiles open these (buttons, so the list adds no "›").
    /// The tool tile that's open (one at a time — two flags let both
    /// destinations be presented at once on a wide screen).
    @State private var openTool: HistoryTool?
    /// D6 (2026-11-10): the session awaiting delete confirmation —
    /// set by the row swipe action or the detail trash button.
    @State private var sessionToDelete: SessionLog?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Open Duo: the chosen day lives on the other page, so this page
    /// doesn't repeat it.
    @Environment(\.duoWide) private var duoWide
    @Environment(\.duoSwapped) private var duoSwapped
    @Environment(\.duoStacked) private var duoStacked
    @Environment(\.cornerButtonsInRail) private var inRail
    @Environment(\.duoCornerInset) private var duoCornerInset
    /// On the open Duo's right page the swap and menu buttons sit in the
    /// bottom-right corner; the summary and tiles stop short of them.
    /// Clear of the swap and menu buttons. DS: only on the bottom half,
    /// following the swap (the List ignores the pair's safe-area padding,
    /// so the month's Saturday column sat under the buttons).
    private var cornerButtonsInset: CGFloat {
        if inRail { return 0 }
        return duoStacked ? duoCornerInset : (duoWide && !duoSwapped ? 76 : 0)
    }

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
                    .padding(.top, pageTitleTop)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: titleLeading, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                // Calendar, legend, and the month at a glance (Nov 12
                // layout DaRon picked: calendar with the stuff below it).
                CalendarView(externalSelection: $selectedDay, gridOnly: true, showsMonthSummary: true,
                             summaryTrailingInset: duoStacked ? 0 : cornerButtonsInset)
                    // DS bottom half: the whole month steps clear.
                    .padding(.trailing, duoStacked ? cornerButtonsInset : 0)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                // Folded there's no other page: the chosen day and the
                // training heatmap sit here instead.
                if !duoWide {
                    // Plain heading rows, not section headers: a header
                    // pins to the top and the rows slid under it
                    // ("Rest day" over "Saturday, Nov 21").
                    listHeading(Text(selectedDay, format: .dateTime.weekday(.wide).month().day()))
                    selectedDayRows
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
                listHeading(Text("Personal records"))
                personalRecordsView
                // A plain heading row: a section header stays pinned to
                // the top and slid over the cards while scrolling.
                Text("This week")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))
                    .listRowBackground(Color.clear)
                historyStatsHeader
                    .padding(.trailing, cornerButtonsInset)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                listHeading(Text("All sessions"))
                Group {
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
                                .tint(.red)
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
            .navigationDestination(item: $openTool) { tool in
                Group {
                    switch tool {
                    case .strength: StrengthGraphView()
                    case .body: BodyView()
                    }
                }
                .navigationBarBackButtonHidden(inRail)
            }
            .onChange(of: openTool == nil, initial: true) { _, top in store.setCanGoBack("history", !top) }
            .onChange(of: store.backRequest.n) { _, _ in
                if store.backRequest.page == "history" { openTool = nil }
            }
            // Picking a session or jumping here from a note closes a tool.
            .onChange(of: selectedSessionID) { _, id in if id != nil { openTool = nil } }
            .onChange(of: selectedDay) { _, _ in openTool = nil }
        } detail: {
            Group {
                if let session = store.sessions.first(where: { $0.id == selectedSessionID }) {
                    // Deleting from the detail clears the selection, so a
                    // compact push never sits on a dead id.
                    SessionDetailView(session: session, onDelete: { selectedSessionID = nil })
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
        // A selection whose session no longer exists (deleted here, from
        // the other page, or by a sample-data swap) is no selection.
        .onChange(of: store.sessions.count) { _, _ in
            if let id = selectedSessionID, !store.sessions.contains(where: { $0.id == id }) {
                selectedSessionID = nil
            }
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
            Button { openTool = .strength } label: {
                toolTile("Strength graph", systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.plain)
            Button { openTool = .body } label: {
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

    /// A section title as an ordinary row, so it scrolls away with its
    /// rows instead of pinning over them.
    private func listHeading(_ text: Text) -> some View {
        text
            .font(.headline)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityAddTraits(.isHeader)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 18, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
    }

    private func toolTile(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                // One icon height, so the three tiles match (the symbols
                // differ in height and made the tiles uneven).
                .frame(height: 26)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        // Room at the sides so a long label ("Strength graph") shrinks
        // instead of touching the tile's edge.
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .themeCard(cornerRadius: 16)
        .contentShape(Rectangle())
    }

    // MARK: - Chosen day

    /// The chosen day's workouts (tap to open), or what was planned.
    @ViewBuilder
    private var selectedDayRows: some View {
        // The calendar's own day rules (CalendarDayIndex): a day before
        // tracking started is never "Missed" here either.
        let index = CalendarDayIndex(store: store)
        let daySessions = index.sessions(on: selectedDay)
        let status = index.status(for: selectedDay)
        if !daySessions.isEmpty {
            ForEach(daySessions) { session in
                SessionRowView(session: session)
                    .tag(session.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { sessionToDelete = session } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
            }
        } else if status == .planned || status == .missed, let plan = index.plan(for: selectedDay) {
            let isPast = status == .missed
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
            Text(status == .beforeStart ? "Before you started tracking."
                 : (selectedDay < index.today ? "Nothing logged that day." : "Rest day."))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Stats header (Fitbod weekly set targets + overall strength)

    /// This week (DaRon picked the activity-rings design, with every
    /// muscle instead of four groups): three rings for workouts, sets and
    /// pounds moved; a bar per muscle trained or planned; then the best
    /// max lift and the streak.
    private var historyStatsHeader: some View {
        let done = store.setsByMuscleThisWeek()
        let planned = store.plannedSetsByMuscle()
        let totalSets = done.values.reduce(0, +)
        let targetSets = planned.values.reduce(0, +)
        // Days trained, not sessions: two sessions on one day are one
        // workout day against the planned days (red team #5).
        let start = weekStartDate(for: Date())
        let workouts = Set(store.sessions.filter { $0.date >= start }
            .map { Calendar.current.startOfDay(for: $0.date) }).count
        let plannedWorkouts = max(store.plannedWorkoutsThisWeek(), workouts)
        let volume = weeklyVolume
        let lastWeek = lastWeekVolume
        // Volume ring: this week against last week (full once you match it).
        let volumeProgress = lastWeek > 0 ? volume / lastWeek : (volume > 0 ? 1 : 0)
        let unit = store.settings.weightUnit
        let streak = store.dayStreak
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 18) {
                ActivityRings(rings: [
                    (ratio(workouts, plannedWorkouts), Color.accentColor),
                    (ratio(totalSets, targetSets), Theme.vividGreen),
                    (min(1, volumeProgress), Theme.vividOrange),
                ])
                .frame(width: 128, height: 128)
                VStack(alignment: .leading, spacing: 8) {
                    ringLegend("\(workouts)/\(plannedWorkouts)", "workouts", Color.accentColor)
                    ringLegend(targetSets > 0 ? "\(totalSets)/\(targetSets)" : "\(totalSets)", "sets", Theme.vividGreen)
                    ringLegend(Self.shortVolume(volume, unit: unit), "\(unit.label) moved", Theme.vividOrange)
                    if lastWeek > 0 {
                        Text("Last week \(Self.shortVolume(lastWeek, unit: unit)) \(unit.label)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .themeCard(cornerRadius: 16)

            muscleBars(done: done, planned: planned)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max lift").font(.caption).foregroundStyle(Theme.secondaryText)
                    Text(bestOneRepMax ?? "—").font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Streak").font(.caption).foregroundStyle(Theme.secondaryText)
                    Text(store.dayText(streak))
                        .font(.headline)
                        .foregroundStyle(Theme.vividOrange)
                }
            }
            .padding(14)
            .themeCard(cornerRadius: 16)
        }
    }

    private func ratio(_ a: Int, _ b: Int) -> Double {
        b > 0 ? min(1, Double(a) / Double(b)) : 0
    }

    private func ringLegend(_ value: String, _ label: String, _ color: Color) -> some View {
        (Text(value).foregroundStyle(color).fontWeight(.bold) + Text(" \(label)"))
            .font(.subheadline)
            .monospacedDigit()
    }

    /// Volume in the user's unit, without the unit label.
    private static func shortVolume(_ lb: Double, unit: WeightUnit) -> String {
        let v = volumeInUnit(lb, unit: unit)
        return v >= 10_000 ? String(format: "%.1fk", v / 1000) : "\(Int(v.rounded()))"
    }

    private var lastWeekVolume: Double {
        let start = weekStartDate(for: Date())
        let prev = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: start) ?? start
        return store.volume(from: prev, to: start.addingTimeInterval(-1))
    }

    /// One bar per muscle: every muscle the program plans this week, plus
    /// any trained outside it. Filled to sets done / sets planned.
    private func muscleBars(done: [MuscleGroup: Int], planned: [MuscleGroup: Int]) -> some View {
        let muscles = MuscleGroup.allCases.filter { (planned[$0] ?? 0) > 0 || (done[$0] ?? 0) > 0 }
        let palette: [Color] = [Color.accentColor, .cyan, Theme.vividGreen, Theme.vividOrange, .purple, .pink, .yellow, .mint, .indigo, .teal]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Muscles").font(.headline)
            if muscles.isEmpty {
                Text("Log a workout and each muscle you train shows up here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                // Horizontal bars, one row per muscle (DaRon).
                VStack(spacing: 10) {
                    ForEach(Array(muscles.enumerated()), id: \.element) { index, muscle in
                        let d = done[muscle] ?? 0
                        let t = planned[muscle] ?? 0
                        let color = palette[index % palette.count]
                        let fill = t > 0 ? min(1, Double(d) / Double(t)) : (d > 0 ? 1 : 0)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(muscle.label).font(.subheadline)
                                Spacer()
                                Text(t > 0 ? "\(d)/\(t)" : "\(d)")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.cardElevated)
                                    Capsule()
                                        .fill(color)
                                        .frame(width: max(d > 0 ? 8 : 0, geo.size.width * fill))
                                }
                            }
                            .frame(height: 8)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(t > 0 ? "\(muscle.label): \(d) of \(t) sets" : "\(muscle.label): \(d) sets")
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(cornerRadius: 16)
    }

    /// The user-chosen leading stat (one row). Extracted so the stats
    /// header stays a small, fast-to-type-check expression.
    private var leadingStatView: some View {
        Group {
            switch store.settings.historyStat {
            case .volume:
                statRow(label: "Volume this week",
                        value: unitVolumeText(lb: weeklyVolume, unit: store.settings.weightUnit))
            case .bestWeight:
                statRow(label: "Best lift this week",
                        value: bestLiftThisWeek ?? "—")
            case .oneRepMax:
                statRow(label: "Best max lift",
                        value: bestOneRepMax ?? "—")
            case .streak:
                statRow(label: "Streak",
                        value: store.dayText(store.dayStreak))
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
        var best: (exercise: ExerciseLog, set: SetLog, load: Double)?
        for session in store.sessions where session.date >= weekStart {
            for exercise in session.exercises {
                let lib = ExerciseLibrary.byId(exercise.exerciseId, plus: store.customExercises)
                guard lib?.isCompound == true, !Self.isMachineStyle(lib) else { continue }
                for set in exercise.sets where set.done && set.kind != .warmup {
                    guard let weight = set.weightLb,
                          let oneRM = validOneRepMax(weightLb: weight, reps: set.reps, isCompound: true) else { continue }
                    // Per-hand dumbbell loads doubled to compare.
                    let load = exercise.isPair ? oneRM * 2 : oneRM
                    if best == nil || load > best!.load {
                        best = (exercise: exercise, set: set, load: load)
                    }
                }
            }
        }
        guard let best, let weight = best.set.weightLb else { return nil }
        let unit = best.exercise.unitOverride ?? store.settings.weightUnit
        return "\(best.exercise.name): \(liftWeightText(weight, isPair: best.exercise.isPair, unit: unit)) × \(best.set.reps)"
    }

    /// Machine and cable lifts (leg press, hack squat, pulldowns, cable
    /// rows): sled / stack numbers aren't comparable to free weights, so
    /// a 400 lb leg press must not "beat" a 225 lb squat.
    private static func isMachineStyle(_ lib: LibraryExercise?) -> Bool {
        guard let lib else { return false }
        return !lib.equipment.isDisjoint(with: [.machine, .cable])
    }

    /// Best valid 1RM per exercise in one pass (it re-scanned every
    /// session per exercise), plus the LATEST log of it — its unit
    /// override is the one the labels show.
    private struct LiftBest {
        let latest: ExerciseLog
        let oneRM: Double          // as logged (per hand for pairs)
        let isMachineStyle: Bool
        /// One scale across lifts: per-hand dumbbell loads doubled.
        var comparable: Double { latest.isPair ? oneRM * 2 : oneRM }
    }

    private var liftBests: [String: LiftBest] {
        var latest: [String: ExerciseLog] = [:]
        var best: [String: Double] = [:]
        var machine: [String: Bool] = [:]
        // store.sessions is newest-first: the first log seen is the latest.
        for session in store.sessions {
            for exercise in session.exercises {
                let id = exercise.exerciseId
                if latest[id] == nil {
                    latest[id] = exercise
                    let lib = ExerciseLibrary.byId(id, plus: store.customExercises)
                    machine[id] = lib?.isCompound == true ? Self.isMachineStyle(lib) : nil
                }
                guard machine[id] != nil,
                      let oneRM = bestValidOneRepMax(in: exercise.sets, isCompound: true) else { continue }
                best[id] = max(best[id] ?? 0, oneRM)
            }
        }
        var out: [String: LiftBest] = [:]
        for (id, oneRM) in best {
            guard let log = latest[id] else { continue }
            out[id] = LiftBest(latest: log, oneRM: oneRM, isMachineStyle: machine[id] ?? false)
        }
        return out
    }

    private func liftText(_ lift: LiftBest) -> String {
        let unit = lift.latest.unitOverride ?? store.settings.weightUnit
        // An estimated max is a calculation, not a plate count: whole
        // pounds (half kilos), never "193.33 lb".
        let step = unit == .kg ? 0.5 / 0.45359237 : 1.0
        let tidy = (lift.oneRM / step).rounded() * step
        return liftWeightText(tidy, isPair: lift.latest.isPair, unit: unit)
    }

    /// The best max lift across free-weight compounds, compared on one
    /// scale (per-hand dumbbells doubled; machine/cable lifts left out).
    private var bestOneRepMax: String? {
        let best = liftBests.values
            .filter { !$0.isMachineStyle }
            .max { $0.comparable < $1.comparable }
        guard let best else { return nil }
        return "\(best.latest.name): \(liftText(best))"
    }

    /// Best lift per muscle group, from logged sessions (real data only).
    /// Same benchmarks as the Overall Strength score — compound lifts
    /// only, so the arm rows are gone: curls and pushdowns are
    /// isolation lifts with no valid 1RM (Gap 7), and a "record" for
    /// them would be a made-up number. Within a group a free-weight lift
    /// wins over a machine one (leg press vs squat aren't comparable);
    /// per-hand dumbbell loads are doubled to compare.
    private var personalRecords: [(muscle: MuscleGroup, name: String, weight: String)] {
        let bests = liftBests
        let benchmarks: [(MuscleGroup, [String])] = [
            (.quads, ["squat", "leg-press", "hack-squat"]),
            (.chest, ["barbell-bench", "dumbbell-bench", "flat-bench"]),
            (.back, ["deadlift", "lat-pulldown", "barbell-row", "cable-row", "dumbbell-row"]),
            (.shoulders, ["overhead-press", "barbell-ohp"]),
        ]
        var rows: [(muscle: MuscleGroup, name: String, weight: String)] = []
        for (muscle, ids) in benchmarks {
            let candidates = ids.compactMap { bests[$0] }
            let pool = candidates.contains { !$0.isMachineStyle } ? candidates.filter { !$0.isMachineStyle } : candidates
            guard let best = pool.max(by: { $0.comparable < $1.comparable }) else { continue }
            rows.append((muscle: muscle, name: best.latest.name, weight: liftText(best)))
        }
        return rows
    }

    private var personalRecordsView: some View {
        let personalRecords = personalRecords
        return Group {
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
    @EnvironmentObject var store: WorkoutStore
    let session: SessionLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(session.dayKey) · \(session.dayTitle)")
                .font(.headline)
                .lineLimit(1)
            Text(session.date, format: .dateTime.weekday(.wide).month().day().year())
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Text("\(pluralised(session.exercises.count, singular: "exercise")) · \(setsDoneText(done: doneSets)) · \(unitVolumeText(lb: sessionVolume, unit: store.settings.weightUnit))")
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
/// Concentric rings, outermost first, each filled 0…1.
struct ActivityRings: View {
    var rings: [(Double, Color)]
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let line = size * 0.1
            ZStack {
                ForEach(rings.indices, id: \.self) { i in
                    let inset = CGFloat(i) * (line + 3) + line / 2
                    Circle()
                        .stroke(rings[i].1.opacity(0.18), lineWidth: line)
                        .padding(inset)
                    Circle()
                        .trim(from: 0, to: max(0.001, rings[i].0))
                        .stroke(rings[i].1, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(inset)
                }
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

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
    /// Called after this session is deleted, so the presenter can drop
    /// its selection (a stale id left the compact push on a dead page).
    var onDelete: (() -> Void)? = nil
    @State private var exportRequest: ExportRequest?
    /// D6: delete confirmation for this detail view's trash button.
    /// (HistoryView holds its own sessionToDelete for the swipe path —
    /// the two dialogs share wording and the same store.deleteSession
    /// call; the detail view cannot reach the list's state directly.)
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            Group {
            Section {
                Text(session.date, format: .dateTime.weekday(.wide).month().day().year().hour().minute())
                if session.finisherDone {
                    Label("Pump finisher done", systemImage: "flame.fill")
                }
            }
            // Share and delete sit under the title and date (DaRon), not
            // floating in the bar over the title.
            HStack(spacing: 10) {
                // Export this one workout (CSV / PDF / text / JSON).
                Button {
                    exportRequest = ExportRequest(initialScope: .session(session))
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Export this workout")
                // D6: delete this session (asks first).
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .tint(.red)
                .accessibilityLabel("Delete this workout")
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            // Each button is its own target (not the whole row).
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
            // Rows take the app's card color (set on the List itself it does nothing).
            .listRowBackground(Theme.card)
        }
        .oledList()
        .navigationTitle("\(session.dayKey) · \(session.dayTitle)")
        // D6: delete confirmation (same wording as the list swipe path).
        .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                store.deleteSession(id: session.id)
                onDelete?()
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
    /// Fill the space it's given (the DS half): squares grow or shrink
    /// to fit. Otherwise it takes the largest fixed grid that fits across.
    var fill = false

    private let gap: CGFloat = 4
    /// Header, weekday row, key and the spacing between them.
    private let chrome: CGFloat = 34 + 14 + 16 + 3 * 8

    private var calendar: Calendar { Calendar.current }


    /// Done working sets per day from `start` on. Every day with a saved
    /// session has an entry (0 when no set was ticked): a saved session
    /// counts as trained, the same rule as the calendar's green dot.
    private func setsByDay(from start: Date) -> [Date: Int] {
        var result: [Date: Int] = [:]
        for session in store.sessions where session.date >= start {
            let day = calendar.startOfDay(for: session.date)
            // Done working sets only, the same count as This week's bars.
            let sets = session.exercises.reduce(0) { total, exercise in
                total + exercise.sets.filter { $0.done && $0.kind != .warmup }.count
            }
            result[day, default: 0] += sets
        }
        return result
    }

    /// The month shown: the one the chosen day is in (DaRon: daily, like
    /// the calendar — "This month, by day").
    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDay)) ?? selectedDay
    }

    /// The month's days laid out by week: leading blanks, then each day.
    private var monthCells: [Date?] {
        let start = monthStart
        let lead = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for d in 0..<days { cells.append(calendar.date(byAdding: .day, value: d, to: start)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    var body: some View {
        if fill {
            GeometryReader { geo in
                heatmap(cell: fittedCell(to: geo.size))
            }
        } else {
            // Squares as wide as the space allows, seven across (DaRon:
            // use the full space), never smaller than before.
            heatmap(cell: widthCell)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
    }

    @State private var width: CGFloat = 0
    private var widthCell: CGFloat {
        guard width > 0 else { return 26 }
        return max(26, min((width - 6 * gap) / 7, 56))
    }

    /// Squares as big as fit: seven across the width, every week down the height.
    private func fittedCell(to size: CGSize) -> CGFloat {
        let rows = CGFloat(monthCells.count / 7)
        let byWidth = (size.width - 6 * gap) / 7
        let byHeight = (size.height - chrome - (rows - 1) * gap) / rows
        return max(12, min(byWidth, byHeight, 44))
    }

    private func heatmap(cell: CGFloat) -> some View {
        let cells = monthCells
        let sets = setsByDay(from: monthStart)
        let today = calendar.startOfDay(for: Date())
        let streak = store.dayStreak
        let corner = max(3, cell * 0.25)
        // Same tracking start as the calendar: min(setup, oldest session).
        let trackingStart = CalendarDayIndex.trackingStart(setupDate: store.setupDate,
                                                           oldestSession: store.sessions.last?.date) ?? today
        // Trained = any saved session that day (the calendar's rule).
        let trained = cells.compactMap { $0 }.filter { sets[$0] != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            // Non-breaking hyphen, so "0-day" never splits across lines.
            Text("\(monthStart.formatted(.dateTime.month(.wide))) · \(trained) day\(trained == 1 ? "" : "s") trained · \(streak)\u{2011}day streak")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            // Weekday initials over the columns.
            HStack(spacing: gap) {
                ForEach(0..<7, id: \.self) { column in
                    Text(weekdayInitial(column))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: cell)
                }
            }
            .frame(height: 14)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: gap) {
                ForEach(0..<(cells.count / 7), id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { column in
                            if let day = cells[row * 7 + column] {
                                square(day: day, sets: sets[day], today: today, trackingStart: trackingStart,
                                       cell: cell, corner: corner)
                                    .overlay {
                                        if calendar.isDate(day, inSameDayAs: selectedDay) && day <= today {
                                            RoundedRectangle(cornerRadius: corner, style: .continuous)
                                                .stroke(Theme.text, lineWidth: 2.5)
                                        }
                                    }
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
            // Key: none, a short workout, a full one.
            HStack(spacing: 4) {
                Text("Less")
                keySquare(Self.level(0))
                keySquare(Self.level(1))
                keySquare(Color.accentColor)
                Text("More")
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText)
            .frame(height: 16)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(monthStart.formatted(.dateTime.month(.wide))): \(trained) days trained, \(store.dayText(streak)) streak")
    }

    private func keySquare(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(width: 14, height: 14)
    }

    private func weekdayInitial(_ column: Int) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        return symbols[(calendar.firstWeekday - 1 + column) % 7]
    }

    /// Heat levels (DaRon: more visible): an empty day still reads as a
    /// square, a short workout is a clear mid accent, a full one solid.
    private static let emptyFill = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.17, alpha: 1) : UIColor(white: 0.88, alpha: 1)
    })
    private static let emptyEdge = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.26, alpha: 1) : UIColor(white: 0.78, alpha: 1)
    })
    private static func level(_ sets: Int) -> Color {
        sets == 0 ? emptyFill : (sets >= 12 ? Color.accentColor : Color.accentColor.opacity(0.55))
    }

    /// `sets` is nil on a day with no saved session, else its done
    /// working sets (0 still counts as trained: a saved session).
    @ViewBuilder
    private func square(day: Date, sets: Int?, today: Date, trackingStart: Date, cell: CGFloat, corner: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let dayText = day.formatted(.dateTime.weekday(.wide).month().day())
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        if day > today {
            // Days still to come: an outline, so the month reads whole.
            // Tapping one shows its plan on the calendar.
            shape.stroke(Self.emptyEdge, lineWidth: 1.5)
                .frame(width: cell, height: cell)
                .contentShape(shape)
                .onTapGesture {
                    withAnimation(AppAnimation.snappy) { selectedDay = day }
                }
                .accessibilityElement()
                .accessibilityLabel("\(dayText), upcoming")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        } else if sets == nil, day < trackingStart {
            // Before you started tracking: a faint, inert square — not
            // tappable, and VoiceOver says why it's blank.
            shape.fill(Self.emptyFill.opacity(0.4))
                .frame(width: cell, height: cell)
                .accessibilityElement()
                .accessibilityLabel("\(dayText), before you started")
        } else {
            // Accent color (DaRon): full for a full workout, faded for a
            // short one (or a saved session with no sets ticked).
            let count = sets ?? 0
            shape.fill(sets == nil ? Self.level(0) : Self.level(max(1, count)))
                .frame(width: cell, height: cell)
                .overlay {
                    if day == today {
                        shape.stroke(Color.accentColor, lineWidth: 2.5)
                    } else if sets == nil {
                        shape.stroke(Self.emptyEdge, lineWidth: 1)
                    }
                }
                .contentShape(shape)
                .onTapGesture {
                    withAnimation(AppAnimation.snappy) { selectedDay = day }
                }
                .accessibilityElement()
                .accessibilityLabel((day == today ? "Today, " : "") + dayText
                    + (sets == nil ? ", no workout" : (count > 0 ? ", \(count) sets" : ", workout logged")))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
    }
}

// MARK: - Volume / lift text in the user's unit

/// Stored-lb volume converted to a unit (exact, no 0.5 kg rounding —
/// it's a total, not a loadable plate weight).
func volumeInUnit(_ lb: Double, unit: WeightUnit) -> Double {
    unit == .kg ? lb * 0.45359237 : lb
}

/// "12.5k kg" / "850 lb" — `formattedVolumeLb`'s shape, in the user's
/// unit (it was hard-coded lb on every screen).
func unitVolumeText(lb: Double, unit: WeightUnit) -> String {
    let v = volumeInUnit(lb, unit: unit)
    if v >= 1000 { return String(format: "%.1fk %@", v / 1000, unit.label) }
    return "\(Int(v.rounded())) \(unit.label)"
}

/// A lift's weight in a unit; per-hand dumbbell loads say "each".
func liftWeightText(_ lb: Double, isPair: Bool, unit: WeightUnit) -> String {
    guard let display = unit.displayValue(for: lb) else { return "—" }
    return "\(roundedWeightText(display)) \(unit.label)" + (isPair ? " each" : "")
}

/// The Calendar page's tool tiles that open a page.
enum HistoryTool: Hashable { case strength, body }
