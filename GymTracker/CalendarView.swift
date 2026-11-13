import SwiftUI

/// Workout calendar (DaRon, 2026-11-09: "i want you to be able to hold
/// it down and it open a calendar that show future and past data").
///
/// Long-press the date (or the "Today" title) on the Today page and this
/// opens. Everything comes from the real on-device store — no fake data:
/// - Past: days with a saved session, marked Done (green dot).
/// - Future: days the active program has a workout planned, marked
///   Planned (blue dot). Rest days get no dot.
/// - Today is ringed. Tap any day to see that day's detail below the
///   grid: the logged workout (exercises, sets, weights) or the planned
///   workout (exercises, sets × reps, finisher).
struct CalendarView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss

    /// When the calendar is shown as a dropdown from the menu instead
    /// of a sheet (DaRon 22:28), Done calls this to close the dropdown
    /// — dismiss() is a no-op outside a sheet. Nil (the default) keeps
    /// the sheet behavior for the long-press / title-tap presentation.
    var onDone: (() -> Void)? = nil

    /// The month on screen (any day inside it; normalized to the 1st).
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    /// The day whose detail shows below the grid. Today on open.
    @State private var localSelectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// Calendar page (History + Calendar merged, Nov 12): the page owns
    /// the selected day so it can list that day's workouts under the
    /// grid and show it on the open Duo's other page.
    var externalSelection: Binding<Date>? = nil
    /// Just the month grid (header, weekdays, days, legend) — no
    /// scroll view, no day detail. Used inside the Calendar page's list.
    var gridOnly: Bool = false
    /// Calendar page (Nov 12 layout): the month's done / missed /
    /// planned counts and the weekly streak, in a card under the legend.
    var showsMonthSummary: Bool = false
    /// Room kept clear at the summary's trailing edge (the open Duo's
    /// corner buttons sit there when this page is on their side).
    var summaryTrailingInset: CGFloat = 0
    /// Wide dropdown on the open Duo (Nov 12, "I want a full
    /// calendar"): the whole month on the left, the chosen day's detail
    /// beside it, so nothing has to scroll.
    var sideBySide: Bool = false
    /// The full-page Today calendar closes with the menu button's ✓, so
    /// its header drops the Done button.
    var showsDone: Bool = true

    private var selectedDate: Date {
        get { externalSelection?.wrappedValue ?? localSelectedDate }
        nonmutating set {
            if let externalSelection { externalSelection.wrappedValue = newValue } else { localSelectedDate = newValue }
        }
    }

    private var calendar: Calendar { Calendar.current }

    /// The earliest month the calendar may show: the month the user
    /// first set up the app (the "account creation" date). No setup
    /// date recorded yet (setup not finished) means the current month
    /// is the floor — never earlier.
    private var earliestMonth: Date {
        let creation = store.setupDate ?? Date()
        return calendar.date(
            from: calendar.dateComponents([.year, .month], from: creation)
        ) ?? creation
    }

    /// True when the month on screen is the account-creation month.
    private var isAtEarliestMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: earliestMonth, toGranularity: .month)
    }

    /// When the calendar is a NavigationLink destination inside
    /// History's split view (DaRon, 22:58), it must not bring its own
    /// NavigationStack or a Done button: the split view supplies the
    /// navigation, and Done's dismiss() would be a dead button there.
    /// Default false keeps the sheet / dropdown behavior unchanged.
    var embeddedInNavigation: Bool = false

    var body: some View {
        if gridOnly {
            VStack(alignment: .leading, spacing: 14) {
                monthHeader
                weekdayHeader
                monthGrid
                legend
                if showsMonthSummary { monthSummary.padding(.trailing, summaryTrailingInset) }
            }
            .onAppear {
                // Show the month of the chosen day.
                displayedMonth = selectedDate
            }
            // A day picked elsewhere (the heatmap, a note's linked
            // workout) brings its month onto the grid. The page stays
            // mounted, so onAppear alone never saw these (red team #1).
            .onChange(of: selectedDate) { _, day in
                guard !calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month) else { return }
                withAnimation(AppAnimation.snappy) {
                    displayedMonth = max(day, earliestMonth)
                }
            }
        } else if embeddedInNavigation {
            calendarContent
                .background(Theme.background)
                .navigationTitle("Calendar")
                .navigationBarTitleDisplayMode(.inline)
        } else if onDone != nil {
            // Dropdown (menu pill + Today long-press): NO inner
            // NavigationStack, so the native toolbar can never duplicate
            // it on the menu path (CAL-0, 2026-11-10). The Done/Calendar
            // header is NOT a sibling above the ScrollView any more —
            // D10-partial (fix batch 2): as a plain VStack sibling the
            // scroll-to-detail landed the day-detail title flush
            // against (and half under) the header. It now rides as the
            // ScrollView's .safeAreaInset (see calendarContent), pinned
            // above the scroll content, so scrollTo("dayDetail",
            // anchor: .top) always lands the title BELOW the header.
            calendarContent
                .background(Theme.background)
        } else {
            // Sheet fallback (no live call sites): the native toolbar
            // supplies Done + title, and the explicit header stays off.
            NavigationStack {
                VStack(spacing: 0) {
                    calendarContent
                }
                .background(Theme.background)
                .navigationTitle("Calendar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { close() }
                    }
                }
            }
        }
    }

    /// The Done + "Calendar" header row (DaRon 2026-11-10 07:49 spec).
    ///
    /// The dropdown presentations (TodayView's overlay, ContentView's
    /// menu) render NO inner NavigationStack (CAL-0): this explicit
    /// header is their only Done/title, so it can never duplicate the
    /// native toolbar the menu path already renders. The sheet path
    /// (onDone nil) keeps the native toolbar and never reaches this
    /// header; the embedded presentation never reaches this branch.
    @ViewBuilder
    private var dropdownHeader: some View {
        if onDone != nil {
            ZStack {
                Text("Calendar")
                    .font(.headline)
                HStack {
                    if showsDone { Button("Done") { close() } }
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            // Opaque: as a pinned safe-area inset this sits over the
            // scroll content, so it needs its own background — content
            // must never show through it (D10).
            .background(Theme.background)
        }
    }

    /// The one close path: the dropdown's onDone (same as the scrim
    /// tap) or the sheet's dismiss(). The toolbar Done and the header
    /// Done both call this, so they can never drift apart.
    private func close() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    /// The month grid + day detail, shared by both presentations.
    private var calendarContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    if sideBySide {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 16) {
                                monthHeader
                                weekdayHeader
                                monthGrid
                                legend
                            }
                            .frame(maxWidth: .infinity)
                            dayDetail(for: selectedDate)
                                .id("dayDetail")
                                .frame(width: 320)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            monthHeader
                            weekdayHeader
                            monthGrid
                            legend
                            dayDetail(for: selectedDate)
                                .id("dayDetail")
                        }
                    }
                }
                // Same 16pt sides/top as before. The bottom is the shared
                // LayoutClearance rule (Debug Pass 2) — but ONLY for the
                // embedded presentation (a NavigationLink destination inside
                // the History split view, where the floating menu button
                // sits over the page). The dropdown presentation anchors
                // the whole card 92pt above the button and scrolls inside
                // the card, so it keeps its plain 16pt bottom and the card
                // doesn't grow 96pt taller.
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, embeddedInNavigation ? LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset) : 16)
                // D35 (2026-11-10): after a day is tapped, bring its
                // detail into view — the grid is 42 cells tall and the
                // detail sits below it, out of reach otherwise.
                .onChange(of: selectedDate) { _, _ in
                    guard !sideBySide else { return }
                    withAnimation(AppAnimation.snappy) {
                        proxy.scrollTo("dayDetail", anchor: .top)
                    }
                }
            }
            // D10-partial (fix batch 2): in the dropdown presentations
            // the Done/Calendar header is pinned here as a top safe-area
            // inset instead of a VStack sibling above the ScrollView.
            // The inset reserves the header's height in the scrollable
            // area, so scrollTo("dayDetail", anchor: .top) lands the
            // day-detail title ("Tuesday, Nov 10") BELOW the header
            // instead of half-clipped under it. Sheet (native toolbar)
            // and embedded (nav title) presentations get no inset.
            .safeAreaInset(edge: .top, spacing: 0) {
                if onDone != nil {
                    dropdownHeader
                }
            }
        }
    }

    // MARK: - Month navigation

    private var monthHeader: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isAtEarliestMonth)
            .opacity(isAtEarliestMonth ? 0.4 : 1)
            .accessibilityLabel("Previous month")

            Spacer()

            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.title3)
                .fontWeight(.bold)

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next month")

            if !calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month) {
                Button("Today") {
                    withAnimation(AppAnimation.snappy) {
                        displayedMonth = calendar.startOfDay(for: Date())
                        selectedDate = calendar.startOfDay(for: Date())
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.leading, 4)
            }
        }
    }

    /// One month forward or back. Never goes before the
    /// account-creation month — the chevron and the swipe both stop
    /// there. A step that would pass the bound lands on it instead.
    private func changeMonth(by value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        let clamped = calendar.compare(next, to: earliestMonth, toGranularity: .month) == .orderedAscending
            ? earliestMonth : next
        withAnimation(AppAnimation.snappy) {
            displayedMonth = clamped
        }
    }

    // MARK: - Month grid

    private var weekdayHeader: some View {
        let symbols = weekdaySymbols
        return HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Short weekday symbols (S M T W T F S) starting on the calendar's
    /// first weekday, so the columns line up with the grid below.
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        guard shift > 0 else { return symbols }
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// The cells of the displayed month: leading blanks, then the days.
    /// Always 6 rows (42 cells) so the grid never jumps height between
    /// months.
    private var monthCells: [Date?] {
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: displayedMonth)
        ) ?? displayedMonth
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in 1...days {
            cells.append(calendar.date(byAdding: .day, value: day - 1, to: startOfMonth))
        }
        // The page's grid ends with the month (the legend sits right under
        // it); the sheet and dropdown keep 6 rows so they never jump.
        let target = gridOnly ? ((cells.count + 6) / 7) * 7 : 42
        while cells.count < target { cells.append(nil) }
        return cells
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(monthCells.indices, id: \.self) { index in
                if let date = monthCells[index] {
                    dayCell(for: date)
                } else {
                    Color.clear.frame(height: 52)
                }
            }
        }
        // NOTE (2026-11-10): this MUST be .simultaneousGesture, not
        // .gesture — a plain .gesture(DragGesture) on the grid claims
        // the touch and swallows the day-cell Buttons' taps (verified
        // on screen: date cells dead 3x while the header chevron, which
        // sits outside the grid, worked; the swipe itself still fired).
        // simultaneousGesture lets both fire: taps select a day, and a
        // 40pt+ predominantly-horizontal drag still changes the month.
        // D35 (2026-11-10): the swipe also entangled vertical scrolling —
        // drags that should scroll the card were claimed by the grid, so
        // the last rows / legend / day detail were unreachable until a
        // day was tapped. The swipe now fires ONLY on a predominantly
        // horizontal drag (and never on a vertical one); the month
        // chevrons in monthHeader navigate months regardless, so if
        // this still blocks scrolling on screen, DELETE the gesture.
        .simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < -50 {
                        changeMonth(by: 1)
                    } else if value.translation.width > 50 {
                        changeMonth(by: -1)
                    }
                }
        )
    }

    private func dayCell(for date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let session = session(for: date)
        let hasPlan = store.programDay(for: date) != nil
        let isPast = date < calendar.startOfDay(for: Date())
        // Future planned day; a past planned day with no session is a
        // miss, not a plan — it gets its own dot so past and future
        // never read the same.
        let planned = session == nil && hasPlan && !isPast
        let missed = session == nil && hasPlan && isPast
        return Button {
            withAnimation(AppAnimation.snappy) {
                selectedDate = calendar.startOfDay(for: date)
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.body.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.accentColor : Theme.text)
                    .frame(width: 34, height: 34)
                    .background(
                        isSelected
                            ? Theme.cardElevated
                            : (isToday ? Color.accentColor.opacity(0.15) : Color.clear),
                        in: Circle()
                    )
                    .overlay(
                        Circle()
                            .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                // One dot tells the whole story: green = a workout was
                // logged that day, accent = one is planned, orange = one
                // was planned and missed. Rest days get no dot.
                Circle()
                    .fill(session != nil ? Theme.vividGreen
                          : (missed ? Theme.vividOrange
                          : (planned ? Color.accentColor : Color.clear)))
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(for: date, session: session, planned: planned, missed: missed))
    }

    private func dayAccessibilityLabel(for date: Date, session: SessionLog?, planned: Bool, missed: Bool) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month().day())
        if session != nil { return "\(day), workout done" }
        if missed { return "\(day), workout missed" }
        if planned { return "\(day), workout planned" }
        return "\(day), rest day"
    }

    /// The displayed month at a glance: workouts done, planned days
    /// missed, planned days still ahead (from today), and the streak of
    /// weeks with at least one workout.
    private var monthSummary: some View {
        let days = monthCells.compactMap { $0 }
        let today = calendar.startOfDay(for: Date())
        // Days before you set the app up can't be missed (red team #3).
        let start = calendar.startOfDay(for: store.setupDate ?? .distantPast)
        let sessionDays = Set(store.sessions.map { calendar.startOfDay(for: $0.date) })
        var done = 0, missed = 0, planned = 0
        for day in days {
            if sessionDays.contains(calendar.startOfDay(for: day)) { done += 1; continue }
            guard store.programDay(for: day) != nil else { continue }
            if day >= today { planned += 1 } else if day >= start { missed += 1 }
        }
        let streak = store.dayStreak
        return VStack(alignment: .leading, spacing: 8) {
            Text(displayedMonth, format: .dateTime.month(.wide))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 0) {
                summaryStat("\(done)", "Done", Theme.vividGreen)
                summaryStat("\(missed)", "Missed", Theme.vividOrange)
                summaryStat("\(planned)", "Planned", Color.accentColor)
                summaryStat(store.dayText(streak), "Streak", Theme.text)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .themeCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private func summaryStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: Theme.vividGreen, label: "Done")
            legendItem(color: Color.accentColor, label: "Planned")
            legendItem(color: Theme.vividOrange, label: "Missed")
            HStack(spacing: 6) {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: - Day detail

    @ViewBuilder
    private func dayDetail(for date: Date) -> some View {
        // D14 (2026-11-10): ALL sessions that day, newest first — the
        // old single-session lookup hid Nov 9's second session entirely.
        let sessions = sessions(for: date)
        let plan = sessions.isEmpty ? store.programDay(for: date) : nil
        let isPast = date < calendar.startOfDay(for: Date())
        // Notes for this day: addUserNote stamps createdAt from the typed
        // date, so a same-day match is exactly this day's notes.
        let dayNotes = store.userNotes.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: date) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(date, format: .dateTime.weekday(.wide).month().day())
                    .font(.headline)
                Spacer()
                if !sessions.isEmpty {
                    statusChip("Done", color: Theme.vividGreen)
                } else if plan != nil && !isPast {
                    statusChip("Planned", color: Color.accentColor)
                } else if plan != nil {
                    statusChip("Missed", color: Theme.vividOrange)
                } else {
                    statusChip("Rest day", color: Theme.tertiaryText)
                }
            }

            if !sessions.isEmpty {
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(session.dayTitle)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            statusChip("Done", color: Theme.vividGreen)
                        }
                        ForEach(session.exercises, id: \.exerciseId) { exercise in
                            loggedExerciseRow(exercise)
                        }
                        if session.finisherDone {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.vividGreen)
                                Text("Pump finisher done")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            } else if let plan {
                Text(plan.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                ForEach(plan.exercises) { template in
                    plannedExerciseRow(template)
                }
                if !plan.finisher.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pump finisher")
                            .font(.subheadline.weight(.semibold))
                        ForEach(plan.finisher, id: \.self) { item in
                            Text("• \(item)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                Text(calendar.isDate(date, inSameDayAs: Date())
                     ? "No workout planned today."
                     : (date < calendar.startOfDay(for: Date())
                        ? "Nothing logged that day."
                        : "No workout planned that day."))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }

            if !dayNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.subheadline.weight(.semibold))
                    ForEach(dayNotes) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            if !note.title.isEmpty {
                                Text(note.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            if !note.body.isEmpty {
                                Text(note.body)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .themeCard()
    }

    private func statusChip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func loggedExerciseRow(_ exercise: ExerciseLog) -> some View {
        let done = exercise.sets.filter { $0.done }.count
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(exercise.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(done)/\(exercise.sets.count) sets")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(exercise.sets.map {
                setWeightText($0, exercise: exercise)
            }.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 2)
    }

    /// Weight text for one logged set — the store's shared formatter
    /// (same rule as History's session detail, unit-override aware).
    private func setWeightText(_ set: SetLog, exercise: ExerciseLog) -> String {
        store.setWeightText(set, exercise: exercise)
    }

    private func plannedExerciseRow(_ template: ExerciseTemplate) -> some View {
        return HStack {
            Text(template.name)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(template.sets) × \(template.repRange)")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            // The weight Today will pre-fill (last logged, with the
            // 2-for-2 bump when earned) — not the plan's stale default,
            // so the planned row and the workout agree.
            if let weight = store.nextWeightAndReps(for: template).weightLb {
                Text(store.displayWeightLabel(weight, isPair: template.isPair, for: template))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Store lookups

    private func session(for date: Date) -> SessionLog? {
        store.sessions.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// Every session logged on a day, newest first (store.sessions is
    /// kept newest-first). D14 (2026-11-10): dayDetail renders all of
    /// these; session(for:) stays ONLY for the day-cell dot check, so
    /// the two lookups can never drift apart.
    private func sessions(for date: Date) -> [SessionLog] {
        store.sessions.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
}
