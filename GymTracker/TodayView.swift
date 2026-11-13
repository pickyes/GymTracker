import SwiftUI
import AudioToolbox
import UIKit

struct TodayView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @Environment(\.pageContainerSize) private var pageContainerSize
    @Environment(\.duoSwapped) private var duoSwapped
    @Environment(\.duoSwapProgress) private var duoSwapProgress
    @Environment(\.appDrawsKeyboardDone) private var appDrawsKeyboardDone
    @Environment(\.todayPlusInColumn) private var inRail
    @AppStorage("duoSideShift") private var sideShift: Double = 0
    @Environment(\.duoWide) private var duoWide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var store: WorkoutStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var saved = false
    @State private var selectedExerciseID: String?
    /// Tap / long-press the date (or the "Today" title) opens the
    /// workout calendar as a compact dropdown card over the Today page
    /// (DaRon 21:22; dropdown presentation DaRon 22:28) — never a
    /// full-screen sheet. The same card ContentView's menu opens.
    @State private var showCalendarDropdown = false
    /// Keyboard avoidance (DaRon 2026-11-10 07:40: the keyboard covered
    /// the primary button and the focused field, with no scroll or
    /// shift): the keyboard's height, tracked from show/hide
    /// notifications. Layouts add it as bottom inset so the focused
    /// field and the primary button can always scroll above the
    /// keyboard; 0 when the keyboard is down.
    @State private var keyboardHeight: CGFloat = 0
    /// The field the keyboard is open for ("field-note-<id>",
    /// "field-weight-<id>-<set>", "field-reps-<id>-<set>",
    /// "field-routine-<id>"). Layouts scroll it into view (anchor
    /// .center) when it changes and again when the keyboard appears,
    /// so the focused field is never hidden behind the keyboard.
    @State private var focusedFieldID: String? = nil
    /// "Train anyway" on a rest day: the workout started from the
    /// rest-day screen (the next scheduled plan). While set, Today
    /// shows that plan's workout instead of the rest-day screen; it
    /// clears on save (back to the rest-day screen) or from the
    /// "Back to rest day" banner. The schedule is untouched — the
    /// program still says rest today, and the day stays neutral
    /// (never "missed").
    @State private var trainingAnywayPlan: DayPlan? = nil
    /// The next workout the rest-day preview sheet is showing, if any.
    @State private var previewPlan: DayPlan? = nil
    @State private var previewDate: Date = Date()
    @State private var showNextPreview = false
    /// The stretch whose detail sheet is open from the rest-day
    /// stretches section, if any.
    @State private var stretchDetail: LibraryExercise? = nil
    /// Rest-day recovery figure: which side of the body it shows, and
    /// which muscle is tapped. (Same state the Body screen keeps.)
    @State private var recoverySide: BodyDiagramSide = .front
    @State private var tappedRecoveryMuscle: MuscleID? = nil
    /// Cold-start greeting: the title says "Hi DaRon" for 5 seconds
    /// after a cold start, then morphs into the normal title.
    @State private var showingGreeting = false
    /// Shared namespace for the fold/unfold morph: the live body and the
    /// current exercise's card glide between layouts in this space.
    /// (DaRon 21:53.)
    @Namespace private var foldNamespace
    /// StandBy-style tent pose: which card the right tile shows.
    @State private var standbyCard: StandbyCard? = .rest
    /// Progress card: headline shows exercises instead of sets (tap).
    @State private var progressShowsExercises = false
    /// Live-body side/flip, hoisted out of LiveBodyView (Debug Pass 2):
    /// LiveBodyView is rebuilt per layout (a new identity each swap),
    /// so its own @State would snap the figure back to the auto side on
    /// every fold. Today owns the values; the three layouts pass them in.
    @State private var liveBodySide: BodyDiagramSide = .front
    @State private var liveBodyUserFlipped = false

    /// The name for the cold-start greeting: the profile's name, or
    /// "DaRon" when the active program is his preset (his saved profile
    /// predates the name field). Nil for a quiz user with no name.
    private var greetingName: String? {
        let set = ProfileIdentity.shared.name.trimmingCharacters(in: .whitespaces)
        if !set.isEmpty { return set }
        if let name = store.profile?.name, !name.isEmpty { return name }
        if store.activeProgram?.id == Program.daronPreset.id { return "DaRon" }
        return nil
    }

    /// The page title: the greeting while it shows, the normal title
    /// otherwise.
    private func greetingTitle(normal: String) -> String {
        guard showingGreeting else { return normal }
        if let name = greetingName { return "Hi \(name)" }
        return "Hi there"
    }

    /// Start the cold-start greeting (once per cold start): show it for
    /// 5 seconds, then morph back to the normal title. The store flag is
    /// cleared immediately so the greeting can't re-fire if Today is left
    /// and re-entered mid-greeting.
    private func startGreetingIfNeeded() {
        guard store.showColdStartGreeting, !showingGreeting else { return }
        showingGreeting = true
        store.showColdStartGreeting = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation(AppAnimation.snappy) { showingGreeting = false }
        }
    }

    private var plan: DayPlan? {
        store.programDay(for: Date())
    }

    /// Today's exercises in the user's order (reordered / added / swapped
    /// mid-workout). Falls back to the plan order before the draft exists.
    private var exercises: [ExerciseTemplate] {
        store.draftExercises.isEmpty ? (plan?.exercises ?? []) : store.draftExercises
    }

    var body: some View {
        // ONE NavigationStack for the whole page (Debug Pass 2, fold
        // glitch): the four layouts used to each build their own stack,
        // so every fold destroyed the nav stack and rebuilt it — a
        // guaranteed pop. The layouts are plain Groups now; this stack
        // survives every pose change. (The sheets below still work —
        // they present from this stack's hierarchy.)
        NavigationStack {
            GeometryReader { proxy in
                let rawKind = layoutKind(for: proxy.size)
                // Fold/unfold (Nov 12 redesign): NO morph and no delay.
                // Folded and open-upright are the SAME workout column view
                // (see compactLayout), so opening the phone keeps it
                // exactly where it was — same scroll, same width — and the
                // body pane is simply revealed beside it, already waiting.
                todayContent(kind: rawKind)
                    // Pin to the real page height (see PageContainerSizeKey):
                    // on the outer screen held sideways the stack measures
                    // taller than the display, which pushed the bottom of
                    // the page (Mark Set Done) off the screen.
                    // Fixed (non-scrolling) layouts only — pinning the
                    // scrolling column stopped it short of the home
                    // indicator and left a black band.
                    // The open Duo's two-page layout too: on the phone it
                    // measured taller than the screen and pushed the body
                    // pane's progress card off the bottom edge. Only ever
                    // shrinks to the real page height, never grows.
                    .frame(height: (rawKind == .tent || rawKind == .propped) ? visibleHeight(proxy.size.height) : nil, alignment: .top)
                    .frame(maxHeight: .infinity, alignment: .top)
                    // The keyboard doesn't squeeze the page: the workout
                    // column already scrolls clear of it on its own
                    // (contentBottomPadding), so the body pane and the
                    // fixed layouts stay put.
                    .ignoresSafeArea(.keyboard)
                    // No animation when the fold or the size changes (no
                    // morph). Only then: blocking every change here also
                    // snapped the keyboard padding, scrolls and the body
                    // pane's front/back turn (red team, animations).
                    .transaction(value: rawKind) { $0.animation = nil }
                    .transaction(value: proxy.size) { $0.animation = nil }
                    // Calendar open: the page behind blurs and goes black
                    // and white, like behind the open menu (DaRon, Nov 12).
                    .blur(radius: showCalendarDropdown ? 3 : 0)  // light: the page stays readable behind it
                    .saturation(showCalendarDropdown ? 0 : 1)
                    .animation(AppAnimation.snappy, value: showCalendarDropdown)
                    // Calendar dropdown: hangs from the Today arrow and
                    // unfolds downward out of it. Never a sheet.
                    .overlay {
                        if showCalendarDropdown {
                            calendarDropdownOverlay(size: proxy.size, kind: rawKind)
                        }
                    }
                    .animation(AppAnimation.snappy, value: showCalendarDropdown)
                    .onChange(of: showCalendarDropdown) { _, open in store.calendarDropdownOpen = open }
                    // The menu button's ✓ closes it.
                    .onChange(of: store.calendarDropdownOpen) { _, open in
                        if !open && showCalendarDropdown {
                            withAnimation(AppAnimation.snappy) { showCalendarDropdown = false }
                        }
                    }
            }
        }
        .disableVerticalBar()
        // Tap-outside-to-dismiss + drag-to-dismiss (Debug Pass 2): the
        // four layouts already carry the keyboard Done toolbar — this
        // is the second way out of the keyboard. Taps on a button,
        // field, or other control are unaffected (the child's own
        // gesture wins the arena), so only taps on empty space dismiss.
        .dismissKeyboardOnTapOutside()
        .scrollDismissesKeyboard(.interactively)
        // Keyboard avoidance, tracked once for the whole page (all four
        // layouts read the same height): the keyboard's end frame on
        // show, 0 on hide. Without this the keyboard covered the
        // primary button and the focused field with no scroll or shift
        // (DaRon 2026-11-10 07:40).
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = frame.height }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
        }
        .onAppear {
            if let plan {
                store.ensureDraft(for: plan)
            }
            applyKeepAwake()
            startGreetingIfNeeded()
        }
        .onChange(of: store.showColdStartGreeting) { _, _ in
            // The greeting flag flips when the loading screen dismisses
            // (after Today has already appeared) — start it then.
            startGreetingIfNeeded()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: plan?.key) { _, _ in
            if let plan {
                store.ensureDraft(for: plan)
            }
        }
        .onChange(of: plan?.exercises.map(\.id).joined(separator: ",")) { _, _ in
            // Same weekday key, different exercises (plan swapped
            // mid-day): the key-only watch above never fires, so watch
            // the exercise list too — ensureDraft now resets the draft
            // when the plan's exercise set changes.
            if let plan {
                store.ensureDraft(for: plan)
            }
        }
        .onChange(of: store.settings.keepScreenAwake) { applyKeepAwake() }
        .onChange(of: store.liveActivitySelectedExerciseID) { _, nextID in
            // The user tapped Next on the lock screen Live Activity:
            // advance the current exercise (the body highlight follows
            // the selection, and the set dots follow the exercise). The
            // store field stays set so the activity keeps showing this
            // exercise until a new rest starts or the rest ends.
            if let nextID {
                selectedExerciseID = nextID
            }
        }
        .alert("Session saved", isPresented: $saved) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Nice work. Come back tomorrow — same time, same place.")
        }
        .sheet(isPresented: $store.todayAddExercise) {
            AddExerciseSheet { template in
                store.addDraftExercise(template)
            }
        }
        .sheet(isPresented: $store.todaySessionMod) {
            SessionModSheet { mod in
                applySessionMod(mod)
            }
        }
        .sheet(isPresented: $showNextPreview) {
            if let plan = previewPlan {
                NextWorkoutPreviewSheet(plan: plan, date: previewDate) { plan in
                    startTrainAnyway(plan: plan)
                }
            }
        }
        .sheet(item: $stretchDetail) { lib in
            LibraryExerciseDetailSheet(exercise: lib)
        }
    }

    /// Tap / long-press on the date / title opens the workout calendar
    /// as a compact dropdown card over Today — never a full-screen
    /// sheet (Item B). One medium haptic on trigger so the hold has a
    /// feel to it. Any open keyboard is dismissed first so it never
    /// sits on top of the dropdown.
    private func openCalendar() {
        if store.settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        hideKeyboard()
        withAnimation(AppAnimation.snappy) { showCalendarDropdown = true }
    }

    /// The calendar dropdown card (Item B): the SAME presentation
    /// ContentView's menu uses (calendarDropdown there) — the same
    /// CalendarView with onDone, the same 20pt rounded card with
    /// border + shadow, the same 0.35 scrim with tap-outside to close,
    /// the same top-move + fade transition, capped at 68% of the
    /// window height and anchored above the floating menu button
    /// (92pt = 24 above the bottom + 56 button + 12 gap), so the
    /// Today page stays visible, dimmed, behind the card and Done
    /// dismisses back to Today. One presentation for both entry
    /// points — never a second, different calendar.
    private func calendarDropdownOverlay(size: CGSize, kind: TodayLayoutKind) -> some View {
        // Which part of the screen the Today title is on: the workout
        // column (the right page on the open Duo unless swapped).
        // (The line between the pages can be dragged: follow it.)
        let paneShare = min(DuoSplitHandle.clamp(
            DuoPagePair<EmptyView, EmptyView>.sideDefault(total: size.width, mainWidth: Self.outerDisplayWidth) + sideShift),
            DuoPagePair<EmptyView, EmptyView>.maxPaneShare(total: size.width, mainMinWidth: 380))
        let columnX: CGFloat = kind == .split && !duoSwapped ? size.width * paneShare : 0
        // Open Duo: a full calendar across both pages (DaRon). Folded:
        // the screen's width.
        let wide = kind == .split && size.width > size.height
        // Ends left of the corner button column (the ✓ that closes it), so
        // the two never overlap (DaRon, Nov 12).
        let cardWidth = size.width - 12 - 84
        // The pointer sits under the arrow wherever the title is.
        let pointerX = columnX + 135 - 12 - 9
        // Just under the title row (the title sits 30pt down, ~41pt tall).
        let top: CGFloat = 82
        let close = { withAnimation(AppAnimation.snappy) { showCalendarDropdown = false } }
        return ZStack(alignment: .topLeading) {
            // Tap anywhere outside to fold it back up.
            Color.black.opacity(0.06)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(spacing: 0) {
                // Small pointer up at the arrow, so the card reads as
                // dropping out of it.
                Triangle()
                    .fill(Theme.background)
                    .overlay(Triangle().stroke(Theme.border, lineWidth: 1))
                    .frame(width: 18, height: 9)
                    // Under the arrow: "Today" (~105pt) + 4pt gap + half
                    // the chevron, from the column's 16pt margin, minus
                    // the card's 12pt inset and half the pointer.
                    .padding(.leading, pointerX)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: 1)
                    .zIndex(1)
                CalendarView(onDone: close, sideBySide: wide, showsDone: false)
                    .frame(maxWidth: .infinity, maxHeight: max(320, size.height - top - (wide ? 8 : 110)))
                    .background(Theme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
            }
            .frame(width: cardWidth)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            .padding(.leading, 12)
            .padding(.top, top)
            // Unfolds downward out of the arrow.
            .transition(reduceMotion
                ? .opacity
                : .scale(scale: 0.08, anchor: UnitPoint(x: (pointerX + 9) / max(cardWidth, 1), y: 0)).combined(with: .opacity))
        }
        .ignoresSafeArea(edges: .top)
    }

    /// The workout Today shows: the "Train anyway" plan while one is
    /// running on a rest day, else today's scheduled plan (nil on a
    /// rest day, which shows the rest-day screen).
    private var effectivePlan: DayPlan? {
        trainingAnywayPlan ?? plan
    }

    /// Bottom clearance for scrollable workout content — the shared
    /// LayoutClearance rule (Debug Pass 2): 96pt clears the floating
    /// menu button (56pt button, 24pt above the bottom edge, 16pt
    /// gap); 238pt clears the whole floating stack while a rest runs,
    /// when the rest-timer panel sits 16pt above the button and would
    /// otherwise cover the Finish & Save button at scroll-bottom (the
    /// panel's top is 222pt above the screen's bottom edge). The
    /// keyboard's height when it is up, so the same content can scroll
    /// clear of the keyboard — always the largest of the three when up.
    /// One definition: compact, regular, propped, rest-day, and the
    /// tent right pane all read this, so they can never drift apart.
    private var fabClearance: CGFloat { LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset) }
    private var contentBottomPadding: CGFloat {
        max(keyboardHeight, fabClearance)
    }

    /// Start a workout on a rest day ("Train anyway"): build the draft
    /// for the given plan (the next scheduled workout) and show its
    /// workout flow today. The schedule is untouched — programDay(for:
    /// today) still says rest, the draft's source plan is the workout
    /// being done, and saving logs a session dated today like any
    /// other session. The rest day stays neutral (never "missed"):
    /// missed requires a scheduled workout, and today has none.
    private func startTrainAnyway(plan: DayPlan) {
        store.ensureDraft(for: plan)
        showNextPreview = false
        withAnimation(AppAnimation.snappy) { trainingAnywayPlan = plan }
    }

    /// The way back from a "Train anyway" workout: clears the override
    /// so Today shows the rest-day screen again. The in-progress draft
    /// stays in the store untouched — tomorrow the same plan is the
    /// day's plan, so the work reappears there. Shown at the top of
    /// every workout layout while a train-anyway session is running.
    private var trainAnywayBanner: some View {
        HStack {
            Text("Training on a rest day")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Back to rest day") {
                withAnimation(AppAnimation.snappy) { trainingAnywayPlan = nil }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }

    /// The page title with a tappable calendar chevron right after the
    /// last letter — a small accent chevron that opens the workout
    /// calendar, so the calendar has a VISIBLE way in, not just the
    /// hidden long-press. (DaRon 22:20: "add an arrow by the y on
    /// today to open calendar.") Tap the title or the chevron — or
    /// keep holding the title / date — all open the same calendar.
    /// The PageTitle is pinned to its ideal width so the chevron sits
    /// snug against the text instead of at the far edge.
    private func calendarTitle(_ text: String) -> some View {
        HStack(spacing: 4) {
            PageTitle(text: text)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.down")
                .scaledFont(size: 20, weight: .bold)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Open calendar")
        }
        .id(text)
        .transition(.opacity)
        .animation(AppAnimation.snappy, value: showingGreeting)
        .contentShape(Rectangle())
        .onTapGesture(perform: openCalendar)
        .onLongPressGesture(minimumDuration: 0.5, perform: openCalendar)
    }

    private func applyKeepAwake() {
        UIApplication.shared.isIdleTimerDisabled = store.settings.keepScreenAwake
    }

    /// Dismiss the keyboard from whichever set field is focused.
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// The keyboard toolbar: exactly ONE Done button for the whole
    /// page. (DaRon 21:06: three Done buttons showed because every
    /// NumberField declared its own keyboard toolbar — one per set
    /// row. The per-field toolbar is gone; each layout below declares
    /// this once, and only one layout is ever on screen.)
    private var keyboardDoneToolbar: some ToolbarContent {
        // The app floats its own Done above the keyboard (ContentView);
        // the system's sat right on the keys (DaRon).
        ToolbarItemGroup(placement: .keyboard) {
            if !appDrawsKeyboardDone {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
    }

    /// Apply a one-off Session Mod (Fitbod pattern): rebuild today's draft
    /// with the mod's equipment / shorter sets, without touching the program.
    private func applySessionMod(_ mod: SessionMod) {
        guard let plan, let profile = store.profile else { return }
        store.draftSessionMod = mod
        let equipment = mod.equipment ?? store.effectiveEquipment
        let program = ProgramGenerator.generate(
            profile: profile,
            customExercises: store.customExercises,
            preferences: store.exercisePreferences,
            equipment: equipment
        )
        guard let modPlan = program.day(forKey: plan.key) else { return }
        var templates = modPlan.exercises
        if mod.shorterSession {
            templates = templates.map { template in
                var copy = template
                copy.sets = min(2, template.sets)
                return copy
            }
        }
        if mod.deload {
            // Recovery week: half the volume (rounded up, at least 1 set),
            // same exercises, same weight. The load stays — the volume drops.
            templates = templates.map { template in
                var copy = template
                copy.sets = max(1, (template.sets + 1) / 2)
                return copy
            }
        }
        if let focus = mod.focusMuscle {
            templates.sort { a, b in
                let aMatch = ExerciseLibrary.byId(a.id, plus: store.customExercises)?.muscle == focus
                let bMatch = ExerciseLibrary.byId(b.id, plus: store.customExercises)?.muscle == focus
                return aMatch && !bMatch
            }
        }
        store.draftExercises = templates
        for template in templates where store.draftLogs[template.id] == nil {
            let weight = store.lastWeight(for: template) ?? template.defaultWeightLb
            store.draftLogs[template.id] = (0..<template.sets).map { _ in
                SetLog(weightLb: weight, reps: template.topReps, done: false)
            }
        }
    }

    // MARK: - Layout branch (inside one view; logs live in the store, so
    // folding/unfolding never loses the in-progress workout)

    /// Which of the four Today layouts is on screen, from the window
    /// size + size class. One value drives the fold/unfold animation
    /// (DaRon 21:53): the branch below keys off it, and the animation
    /// in `body` fires exactly when it flips — Closed ↔ Partially
    /// Open ↔ Open, and into/out of the Tent/Seated glanceable layout.
    /// State survives the flip unchanged: logs live in the store, the
    /// current exercise is derived from the draft, and each layout
    /// scrolls back to the current card on appear (scrollToCurrent).
    private enum TodayLayoutKind: Equatable {
        case compact, split, regular, propped, tent
    }

    /// The real page height (keyboard ignored), capped by what was measured
    /// only when there's no container size to go on.
    /// The window's height down to the home indicator (from the screen's
    /// top edge). The open Duo's body pane is capped to it so the progress
    /// card always ends right above the home indicator — on the phone the
    /// pane measured taller than the screen and the card ran off the edge.
    static var windowUsableHeight: CGFloat? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return nil }
        let h = window.bounds.height - window.safeAreaInsets.bottom
        // Before the window is laid out its height is 0, and a negative
        // cap is an invalid frame that collapsed the whole Today page.
        return h > 200 ? h : nil
    }

    /// The status bar's height (the window's top safe area).
    static var windowSafeTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.safeAreaInsets.top ?? 0
    }

    private func visibleHeight(_ measured: CGFloat) -> CGFloat {
        pageContainerSize.height > 200 ? min(measured, pageContainerSize.height) : measured
    }

    private func layoutKind(for measured: CGSize) -> TodayLayoutKind {
        // Trust the page container when ContentView provides it (see
        // PageContainerSizeKey): never larger than what's really on screen.
        // The real page size, measured without the keyboard: a keyboard
        // coming up shortened the measured height, so the folded screen
        // looked "sideways" and flipped to the tent view mid-typing (seen
        // on the phone, Nov 12). The keyboard never changes the pose.
        let size = (pageContainerSize.width > 200 && pageContainerSize.height > 200) ? pageContainerSize : measured
        if size.width > size.height * 1.2 {
            // Propped (Seated / Tent): landscape and much wider than tall.
            if size.height < 520 {
                // Short window = one half of the device (Seated top
                // half, ~475pt tall, or Tent cover in landscape,
                // ~466pt tall): glanceable hands-free view — big
                // exercise, big timer, readable from a distance.
                // A full landscape window (open inner 669pt,
                // iPad 768pt+) takes the normal propped layout.
                return .tent
            }
            // Opening the Duo like a book turns the outer (portrait)
            // screen into the inner screen held landscape: the outer
            // screen's column becomes the right page and the body is
            // revealed on the left page (Nov 12, verified in Device Hub).
            if size.width >= Self.outerDisplayWidth + 150 { return .split }
            return .propped
        }
        // Open inner display: two-pane list + detail — but only when the
        // window is actually wide. A stale .regular size class after a
        // warm relaunch (D26, 2026-11-10) must never squeeze the two-pane
        // layout into the folded window: folded ≈ 412pt, open inner
        // ≈ 850pt. The bar is 760pt, not 600: the open inner display held
        // in portrait is 669pt wide, which left each pane ~326pt — too
        // narrow for a set row, so the workout pane ran off the right
        // edge and covered the Front/Back toggle. That pose now gets the
        // single column, which has room to spare at 669pt.
        if horizontalSizeClass == .regular && size.width >= 760 { return .regular }
        // Open inner display held upright (~669pt): the outer display's
        // column at its own width on the right, the body revealed on the
        // left (Nov 12: "the other side is just waiting to be seen").
        if size.width >= Self.outerDisplayWidth + 150 { return .split }
        // Outer display: single column, one-handed.
        return .compact
    }

    @ViewBuilder
    private func todayContent(kind: TodayLayoutKind) -> some View {
        // The "Train anyway" plan wins while one is running on a rest
        // day; otherwise today's scheduled plan (nil on a rest day).
        if let plan = effectivePlan {
            // Empty workout (every exercise removed in Edit mode, or a
            // Session Mod that left zero exercises): show the empty
            // state instead of a layout — propped/tent index
            // exercises[0] and would crash on an empty list.
            if exercises.isEmpty {
                emptyWorkoutView(for: plan)
            } else {
                // NO transition on the branches (Debug Pass 2, fold
                // glitch): the old .opacity crossfade kept the outgoing
                // layout mounted while the incoming one mounted, so BOTH
                // carried matchedGeometryEffect(id: "liveBody") and
                // "currentCard" at once — two sources for one id, and
                // the morph jumped/flickered instead of gliding. With no
                // transition the swap is a single commit, the shared
                // namespace has exactly one source, the hero views glide
                // on FoldAnimation.morph, and everything else re-places
                // once, mid-fold, while the window is still resizing.
                switch kind {
                case .tent:
                    tentLayout(for: plan)
                case .propped:
                    proppedLayout(for: plan)
                case .regular:
                    regularLayout(for: plan)
                case .compact, .split:
                    compactLayout(for: plan, split: kind == .split)
                }
            }
        } else {
            restDayView()
        }
    }

    /// Empty workout state: no exercises left to show (all removed in
    /// Edit mode, or a Session Mod that left zero). Offers Add exercise
    /// instead of crashing — propped/tent never see an empty list
    /// because todayContent routes here first.
    private func emptyWorkoutView(for plan: DayPlan) -> some View {
        // Plain Group: the page's single NavigationStack lives in body —
        // this used to build its own stack, which the fold destroyed and
        // rebuilt on every pose change.
        Group {
            VStack(spacing: 12) {
                Text("No exercises in this workout")
                    .font(.headline)
                Text("Add an exercise to get started, or pick a different day.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                Button("Add exercise") { store.todayAddExercise = true }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 44)
            }
            .padding()
            // The page's single stack (in body) hosts this too — keep its
            // bar hidden like every other Today layout.
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Rest-day screen (interactive, never "missed")

    /// The rest-day Today screen (DaRon 2026-11-10 07:59–08:00): a day
    /// with no scheduled workout is NEUTRAL — never "missed" — and the
    /// screen is interactive, not a static label. Four parts, all from
    /// real store / library data, in the same Today chrome (title with
    /// calendar chevron, date, 16pt margins) as a workout day:
    /// 1. What's recovering — the Body screen's freshness coloring.
    /// 2. The next scheduled workout, tappable to view it in full.
    /// 3. "Train anyway" — start the next workout today without
    ///    marking the rest day missed or breaking the schedule.
    /// 4. Stretches for the muscle groups the last workout used.
    private func restDayView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                calendarTitle(greetingTitle(normal: "Today"))
                    .padding(.leading, 16)
                Text(Date(), format: .dateTime.weekday(.wide).month().day())
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .padding(.leading, 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Rest day")
                        .font(.title2)
                        .bold()
                    Text("No workout scheduled today. Recovery is part of the plan — nothing missed, nothing owed.")
                        .font(.body)
                        .foregroundStyle(Theme.text)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    recoverySection
                    nextWorkoutSection
                    trainAnywaySection
                    stretchesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, fabClearance)
            }
        }
        // The page's single stack (in body) hosts the rest-day screen
        // too — it used to sit outside any stack, so without this the
        // hoisted stack would show an empty bar above it.
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Recovery colour per muscle, from the store's logged history —
    /// the same map the Body screen builds (BodyView.recovery).
    private var recoveryMap: [MuscleID: MuscleRecovery] {
        let dates = store.lastTrainedDates()
        var map: [MuscleID: MuscleRecovery] = [:]
        for id in MuscleID.allCases {
            guard let group = id.muscleGroup else { continue }
            map[id] = store.recoveryState(for: group, dates: dates)
        }
        return map
    }

    /// Muscle groups still recovering (within their recovery window),
    /// most recently trained first — the muscles the rest-day screen's
    /// recovery view and stretches section are about.
    private var recoveringMuscleGroups: [MuscleGroup] {
        let dates = store.lastTrainedDates()
        return dates.keys
            .filter { store.recoveryState(for: $0, dates: dates) == .recovering }
            .sorted { (dates[$0] ?? .distantPast) > (dates[$1] ?? .distantPast) }
    }

    /// Muscle groups the most recent logged workout used (the latest
    /// trained date, all muscles trained that day) — the stretches
    /// section targets exactly these.
    private var recentlyUsedMuscles: [MuscleGroup] {
        let dates = store.lastTrainedDates()
        guard let latest = dates.values.max() else { return [] }
        return dates
            .filter { Calendar.current.isDate($0.value, inSameDayAs: latest) }
            .keys.sorted { $0.label < $1.label }
    }

    /// Stretching exercises in the library for the given muscles. The
    /// library has no stretch category — the match is by name
    /// ("Stretch" in the exercise name) — so this is empty until
    /// stretch entries are added to the library (see the pass report:
    /// no stretch exercises exist in the 1,583-exercise library today).
    /// A marked injury hides the stretches that load the injured area:
    /// the filter drops any stretch whose muscle is in the injured
    /// area's stretch muscles (`Limit.stretchMuscles`) — a shoulder
    /// injury never suggests an overhead shoulder stretch, a knee
    /// injury never suggests a quad stretch.
    private func stretches(for muscles: [MuscleGroup]) -> [LibraryExercise] {
        let blocked = InjuryAdaptation.stretchMuscles(for: store.profile?.limits ?? [])
        return ExerciseLibrary.all(plus: store.customExercises)
            .filter { lib in
                muscles.contains(lib.muscle)
                && lib.name.localizedCaseInsensitiveContains("stretch")
                && !blocked.contains(lib.muscle)
            }
    }

    /// True when at least one muscle the last workout used has its
    /// stretches hidden by a marked injury — the empty state then
    /// says why, instead of claiming the library has no stretches.
    private var stretchBlockedByInjury: Bool {
        guard let limits = store.profile?.limits, !limits.isEmpty else { return false }
        let blocked = InjuryAdaptation.stretchMuscles(for: limits)
        return !blocked.intersection(recentlyUsedMuscles).isEmpty
    }

    /// The stretches for the muscles the last workout used.
    private var stretchesForRecentMuscles: [LibraryExercise] {
        stretches(for: recentlyUsedMuscles)
    }

    /// 1. What's recovering: the SAME figure and the SAME freshness
    /// coloring as the Body screen (BodyFigureView with the store's
    /// recovery map — fresh = bright pink + dashed ring, recovering =
    /// purple, resting = the image's own red), plus the one-line
    /// caption per recovering muscle and the front/back flip. Tap a
    /// muscle to see which one it is. No second diagram, no fake data.
    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's recovering")
                .font(.headline)
            BodyFigureView(side: recoverySide, recovery: recoveryMap) { muscle in
                withAnimation(AppAnimation.snappy) {
                    tappedRecoveryMuscle = (tappedRecoveryMuscle == muscle) ? nil : muscle
                }
            }
            .frame(height: 360)
            if let muscle = tappedRecoveryMuscle {
                Text(muscle.accessibilityLabel)
                    .font(.headline)
                if let group = muscle.muscleGroup {
                    Text(store.recoveryCaption(for: group))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else if let recovering = recoveringMuscleGroups.first {
                Text(store.recoveryCaption(for: recovering))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Button {
                withAnimation(AppAnimation.snappy) {
                    recoverySide = recoverySide == .front ? .back : .front
                }
            } label: {
                Label("Rotate — \(recoverySide == .front ? "Back" : "Front")", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    /// 2. The next scheduled workout, tappable to view it in full (the
    /// preview sheet). Real data from the active program via
    /// store.nextWorkout(after:) — the same lookup the old rest-day
    /// screen used.
    private var nextWorkoutSection: some View {
        Group {
            if let next = store.nextWorkout(after: Date()) {
                Button {
                    previewPlan = next.plan
                    previewDate = next.date
                    showNextPreview = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Next workout")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Text("\(next.plan.title) · \(next.date, format: .dateTime.weekday(.wide).month().day())")
                            .font(.subheadline)
                        ForEach(next.plan.exercises) { exercise in
                            Text("• \(exercise.name) — \(exercise.sets) × \(exercise.repRange)")
                                .font(.subheadline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding()
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            }
        }
    }

    /// 3. "Train anyway": start the next workout today. The rest day
    /// stays neutral (never "missed") and the schedule is unchanged —
    /// see startTrainAnyway. Hidden when there is no next workout (no
    /// active program), so the button never promises a workout that
    /// does not exist.
    private var trainAnywaySection: some View {
        Group {
            if let next = store.nextWorkout(after: Date()) {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        startTrainAnyway(plan: next.plan)
                    } label: {
                        Text("Train anyway — start \(next.plan.title)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    Text("Starts today's session with the next scheduled workout. Your rest day stays a rest day on the schedule — nothing is marked missed.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 4. Stretches for the muscle groups the last workout used (DaRon
    /// 2026-11-10 08:00): each row is tappable to view how to do it.
    /// Follows the ACTUAL logged history (recentlyUsedMuscles), not a
    /// fixed list — after a Pull day the stretches are for back /
    /// biceps / rear delts, after a Legs day they are for legs. The
    /// library currently holds no stretch exercises, so until stretch
    /// entries are added this section says so plainly instead of
    /// showing invented content.
    private var stretchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stretches to try")
                .font(.headline)
            if recentlyUsedMuscles.isEmpty {
                Text("Log a workout and stretches for the muscles you worked will show up here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("For \(recentlyUsedMuscles.map { $0.label }.joined(separator: ", ")) — worked in your last session.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                if stretchesForRecentMuscles.isEmpty {
                    if stretchBlockedByInjury {
                        Text("Stretches for these muscles are hidden while an injury is marked there — check with your doctor or physical therapist about what stretching is OK for you.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("No stretches in the library for these muscles yet.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    ForEach(stretchesForRecentMuscles) { lib in
                        Button { stretchDetail = lib } label: {
                            HStack {
                                Text(lib.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Text(lib.muscle.label)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Theme.cardElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    // MARK: - Compact (outer display, one-handed, glanceable)

    /// Width of the outer (folded) display, in points. In the open
    /// upright pose the workout column keeps exactly this width so
    /// unfolding never re-lays it out.
    static let outerDisplayWidth: CGFloat = 466

    /// Folded: the single column. `split` (open, upright): the SAME
    /// column at the outer display's width on the right, with the live
    /// body in a pane on the left. The column is always the HStack's
    /// second child, so SwiftUI keeps its identity (and scroll position)
    /// across fold/unfold; only the left pane appears or disappears.
    private func compactLayout(for plan: DayPlan, split: Bool) -> some View {
        // Swapped (open Duo, swap button): the workout column moves to
        // the left page and the body waits on the right.
        let swapped = split && duoSwapped
        // One pair of pages that trade sides like two apps (DuoPagePair).
        return DuoPagePair(wide: split, swapped: swapped, paneClearsCorner: false,
                           mainMinWidth: 380) {
            splitBodyPane(for: plan, anchor: swapped ? .leading : .trailing)
        } main: {
            compactColumn(for: plan, showBody: !split)
                // The column keeps the folded screen's sizing on the open
                // Duo (compact fields), or the set rows got crushed to
                // "S…  P…" at its 466pt width.
                .environment(\.horizontalSizeClass, split ? .compact : horizontalSizeClass)
        }
    }

    /// Today's session at a glance (open Duo, above the body): a ring
    /// for sets done, then sets, exercises, and weight moved.
    private var sessionProgressCard: some View {
        let allLogs = exercises.map { store.draftLogs[$0.id] ?? [] }
        let totalSets = allLogs.reduce(0) { $0 + $1.count }
        let doneSets = allLogs.reduce(0) { $0 + $1.filter(\.done).count }
        let doneExercises = allLogs.filter { !$0.isEmpty && $0.allSatisfy(\.done) }.count
        let volumeLb = allLogs.flatMap { $0 }.filter(\.done)
            .reduce(0.0) { $0 + ($1.weightLb ?? 0) * Double($1.reps) }
        let unit = store.settings.weightUnit
        let volume = unit.displayValue(for: volumeLb) ?? volumeLb
        // Tap to switch the headline between sets and exercises (DaRon):
        // the other one moves to the small line, and the ring follows.
        let byExercise = progressShowsExercises
        let progress = byExercise
            ? (exercises.isEmpty ? 0 : Double(doneExercises) / Double(exercises.count))
            : (totalSets == 0 ? 0 : Double(doneSets) / Double(totalSets))
        let ring = ZStack {
            Circle().stroke(Theme.track, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((progress * 100).rounded()))%")
                .font(.subheadline.weight(.bold).monospacedDigit())
        }
        .frame(width: 64, height: 64)
        .animation(AppAnimation.snappy, value: progress)
        let setsText = "\(doneSets) of \(totalSets) sets"
        let exercisesText = "\(doneExercises) of \(exercises.count) exercises"
        let setsLine = Text(byExercise ? exercisesText : setsText)
            .font(.title3.weight(.bold))
            .contentTransition(.numericText())
        let detail = Text("\(byExercise ? setsText : exercisesText) · \(volume.formatted(.number.precision(.fractionLength(0)))) \(unit.label) lifted")
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
        // Wide pane: ring beside the text. Narrow pane (open Duo held
        // upright, ~200pt): ring over the text, centered.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                ring
                VStack(alignment: .leading, spacing: 4) {
                    setsLine.fixedSize()
                    detail.fixedSize()
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 8) {
                ring
                setsLine
                detail
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .themeCard(cornerRadius: 20)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture {
            withAnimation(AppAnimation.snappy) { progressShowsExercises.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(byExercise ? "Shows sets instead" : "Shows exercises instead")
    }

    /// The body pane revealed beside the workout column on the open Duo.
    @ViewBuilder
    private func splitBodyPane(for plan: DayPlan, anchor: UnitPoint) -> some View {
        if let currentID = displayedExerciseID(for: plan),
           let current = exercises.first(where: { $0.id == currentID }) {
            // Starts at the top of the pane (it sat 60pt down, leaving an
            // empty strip — Nov 12). Held sideways the pane is wide enough
            // for the session progress card above the body; upright (a
            // ~200pt strip) it's just the body (DaRon: "undo only in
            // portrait").
            // The card sits at the bottom of the screen, under the body
            // (DaRon).
            VStack(spacing: 18) {
                LiveBodyView(
                    exerciseID: current.id,
                    nextExerciseID: nextExercise(after: current.id, in: exercises)?.id,
                    figureHeight: nil,
                    sideBinding: $liveBodySide,
                    userFlippedBinding: $liveBodyUserFlipped
                )
                // The figure takes all the room down to the progress card
                // (DaRon: "enlarge") — no spacer competing for it.
                .frame(maxHeight: .infinity)
                if pageContainerSize.width > pageContainerSize.height {
                    sessionProgressCard
                        .padding(.bottom, 16)
                        // Full width on either page (DaRon: it looked cut
                        // short) — its ring and text sit at the left, so
                        // the corner buttons only cover empty card.
                }
            }
            .padding(.horizontal, 16)
            // DS: the body's labels end clear of the fold's fade and the
            // divider grabber, so "Next up" reads in full (DaRon).
            .modifier(FoldClearance())
            // "Working now" sits in the clock's row, level with the
            // Today title (same top strip, DaRon Nov 12).
            // On the right page (sides swapped) the clock is above it, so
            // it starts below the status bar there instead.
            // Same top on both sides (DaRon: the body must not change size or
            // move when the sides swap) — always just below the status bar.
            .padding(.top, 46)  // status bar (34) + 12, same on both sides
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Only the body pane is capped to the real page height (so its
            // progress card is never cut off at the bottom edge); the
            // workout column still runs to the bottom of the screen.
            // (no window-height cap: reading the window during layout
            // blanked the whole Today page on a launch while open)
            .ignoresSafeArea(edges: .top)
            // Follows the real hinge: the waiting pane comes up to full
            // brightness exactly as the phone opens flat.
            .hingeReveal(anchor: anchor)
        }
    }

    private func compactColumn(for plan: DayPlan, showBody: Bool) -> some View {
        // Plain Group: the page's single NavigationStack lives in body.
        Group {
            ScrollViewReader { proxy in
                ScrollView {
                    // The title lines up with the content below it: the same
                    // 16pt leading the workout content uses, so "Today" and
                    // "Legs" start at the exact same x. (DaRon approved the
                    // layout 17:32 with this one fix; it supersedes the
                    // earlier "flush to the left edge" instruction.)
                    VStack(alignment: .leading, spacing: 0) {
                        calendarTitle(greetingTitle(normal: "Today"))
                            .padding(.leading, 16)
                            // In the clock's row (DaRon, Nov 12): the Duo's
                            // status icons sit only at the top-right, so the
                            // title uses the empty strip beside them instead
                            // of starting below it.
                            .padding(.top, 30)
                        // Date directly under "Today". (DaRon 21:20:
                        // Today on top, Monday, Nov 9 under it.)
                        // Hold it down to open the workout calendar.
                        // Full-bright primary text, larger — the dim
                        // secondary gray was unreadable on black.
                        // (DaRon 21:25: "i cant read the words under".)
                        Text(Date(), format: .dateTime.weekday(.wide).month().day())
                            .font(.body)
                            .foregroundStyle(Theme.text)
                            .padding(.leading, 16)
                            .padding(.top, 2)
                            .onLongPressGesture(minimumDuration: 0.5, perform: openCalendar)
                        VStack(alignment: .leading, spacing: 16) {
                            if trainingAnywayPlan != nil {
                                trainAnywayBanner
                            }
                            header(for: plan)
                            ForEach(exercises) { template in
                                foldCard(
                                    ExerciseCard(
                                        template: template,
                                        sets: binding(for: template),
                                        hint: store.progressionHint(for: template),
                                        previousLog: store.lastLog(for: template.id),
                                        isCurrent: template.id == displayedExerciseID(for: plan),
                                        isEditing: store.todayEditing,
                                        onMoveUp: { moveExercise(id: template.id, up: true) },
                                        onMoveDown: { moveExercise(id: template.id, up: false) },
                                        onRemove: { store.removeDraftExercise(id: template.id) },
                                        onSwap: { replacement in store.swapDraftExercise(id: template.id, with: replacement) },
                                        swapNote: store.swapNote(for: template),
                                        onFieldFocus: { focusedFieldID = $0 }
                                    )
                                    .id("exercise-\(template.id)"),
                                    isCurrent: template.id == displayedExerciseID(for: plan)
                                )
                            }
                            finisherCard(for: store.draftSourcePlan ?? plan)
                            saveButton(for: plan)
                            // Live body, compact: under the current exercise
                            // (in the open pose it lives in the left pane).
                            if showBody, let currentID = displayedExerciseID(for: plan),
                               let current = exercises.first(where: { $0.id == currentID }) {
                                LiveBodyView(
                                    exerciseID: current.id,
                                    nextExerciseID: nextExercise(after: current.id, in: exercises)?.id,
                                    sideBinding: $liveBodySide,
                                    userFlippedBinding: $liveBodyUserFlipped
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        // Bottom clearance: the keyboard's height when it
                        // is up (so the save button and the note field
                        // can scroll above it), else 96pt so the primary
                        // button never sits under the floating menu
                        // button. Without this the content physically
                        // could not scroll above the keyboard at all.
                        .padding(.bottom, contentBottomPadding)
                    }
                }
                // Content starts at the very top (title beside the clock).
                .ignoresSafeArea(edges: .top)
                .infinityTopEdge()
                .onAppear { scrollToCurrent(proxy: proxy, plan: plan, animated: false) }
                .onChange(of: displayedExerciseID(for: plan)) { _, _ in
                    scrollToCurrent(proxy: proxy, plan: plan, animated: true)
                }
                // Focused-field scrolling: when a weight / reps / note
                // field takes focus, and again when the keyboard
                // appears, scroll that field to the middle of the
                // visible list — above the keyboard, never behind it.
                .onChange(of: focusedFieldID) { _, _ in
                    scrollToFocusedField(proxy: proxy)
                }
                .onChange(of: keyboardHeight) { _, height in
                    if height > 0 { scrollToFocusedField(proxy: proxy) }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar { keyboardDoneToolbar }
        }
    }

    // MARK: - Regular (open inner display, two-pane)

    /// Open display, portrait: the SAME 50/50 split as the propped
    /// layout — the live body fills the LEFT pane, the workout (selected
    /// card + exercise list + finisher + save) fills the RIGHT pane.
    /// (DaRon 21:32: swap the body to the left so opening the phone
    /// looks just like the outer display — the body stays put on the
    /// left and the workout opens up beside it.) The old
    /// NavigationSplitView put the exercise list on the left and the
    /// card + body stacked on the right; the list now lives under the
    /// card in the right pane, tappable to switch exercises. The rest
    /// timer no longer lives here at all — it slides up from the
    /// floating menu button (DaRon 21:28).
    private func regularLayout(for plan: DayPlan) -> some View {
        let resolved = displayedExerciseID(for: plan)
        let template = resolved.flatMap { id in exercises.first(where: { $0.id == id }) }
        // Plain Group: the page's single NavigationStack lives in body.
        return Group {
            VStack(alignment: .leading, spacing: 12) {
                // Title lines up with the two panes below (same 16pt
                // leading as the panes' inset), not flush to the edge.
                // The greeting ("Hi [name]" on cold start) shows here
                // like everywhere else; the far-right "+" menu holds
                // Edit / Add exercise / Modify today. The row's 16pt
                // trailing + the menu's own 16pt puts the "+" center
                // exactly 60pt from the right edge — the same axis as
                // the card "+" and the floating menu button below, in
                // every layout (DaRon 2026-11-10: the "+" position
                // shifted between poses).
                HStack(spacing: 12) {
                    calendarTitle(greetingTitle(normal: plan.title))
                    Spacer()
                    workoutActionsMenu
                }
                .padding(.horizontal, 16)
                // D37 (2026-11-10): the wide layouts showed only the
                // title — the date line the compact layout has ("Tuesday,
                // Nov 10", hold to open the calendar) was missing here.
                Text(Date(), format: .dateTime.weekday(.wide).month().day())
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .padding(.leading, 16)
                    .padding(.top, 2)
                    .onLongPressGesture(minimumDuration: 0.5, perform: openCalendar)
                Text(plan.subtitle)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .padding(.leading, 16)
                // Exact 50/50 split (same fix as proppedLayout): fixed
                // half-widths measured from the actual HStack width, so
                // the split is dead center and the hinge line falls in
                // the gap between the panes.
                GeometryReader { geo in
                    // Clamp at 0: during the first layout pass the
                    // GeometryReader can report a zero width, which
                    // would make paneWidth negative (invalid frame).
                    let paneWidth = max((geo.size.width - 16) / 2, 0)
                    HStack(alignment: .top, spacing: 16) {
                        // LEFT: live body, BIG — the current exercise's
                        // muscles, lit up in real time. Nothing else
                        // shares this pane, so nothing ever resizes it.
                        VStack(alignment: .leading, spacing: 16) {
                            if let template {
                                LiveBodyView(
                                    exerciseID: template.id,
                                    nextExerciseID: nextExercise(after: template.id, in: exercises)?.id,
                                    figureHeight: nil,
                                    sideBinding: $liveBodySide,
                                    userFlippedBinding: $liveBodyUserFlipped
                                )
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                // Fold/unfold morph: the body glides
                                // between panes instead of popping.
                                // (DaRon 21:53.)
                                .matchedGeometryEffect(id: "liveBody", in: foldNamespace)
                            }
                        }
                        .frame(width: paneWidth)
                        .frame(maxHeight: .infinity)
                        // RIGHT: the workout — selected card on top,
                        // then the exercise list (tap to switch),
                        // finisher, save.
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    if trainingAnywayPlan != nil {
                                        trainAnywayBanner
                                    }
                                    if let template {
                                        foldCard(
                                            ExerciseCard(
                                                template: template,
                                                sets: binding(for: template),
                                                hint: store.progressionHint(for: template),
                                                previousLog: store.lastLog(for: template.id),
                                                isCurrent: template.id == displayedExerciseID(for: plan),
                                                isEditing: store.todayEditing,
                                                onMoveUp: { moveExercise(id: template.id, up: true) },
                                                onMoveDown: { moveExercise(id: template.id, up: false) },
                                                onRemove: { store.removeDraftExercise(id: template.id) },
                                                onSwap: { replacement in store.swapDraftExercise(id: template.id, with: replacement) },
                                                swapNote: store.swapNote(for: template),
                                                onFieldFocus: { focusedFieldID = $0 }
                                            )
                                            .id("exercise-\(template.id)"),
                                            // Only the current exercise
                                            // morphs: if the user picked a
                                            // different exercise in the
                                            // list, that card just fades.
                                            isCurrent: template.id == displayedExerciseID(for: plan)
                                        )
                                    }
                                    exerciseListSection(for: plan, selectedID: resolved)
                                    finisherCard(for: store.draftSourcePlan ?? plan)
                                    saveButton(for: plan)
                                }
                                // Bottom clearance: keyboard height when
                                // up, else 96pt so the save button never
                                // sits under the floating menu button.
                                .padding(.bottom, contentBottomPadding)
                            }
                            // The open layout had no appear-restore at
                            // all (Debug Pass 2): the return to the open
                            // display rebuilt its list at offset 0. The
                            // card sits first so that usually reads as
                            // "top", but the restore is what keeps the
                            // place when the list was scrolled — same
                            // instant, pre-first-frame restore as the
                            // other layouts.
                            .onAppear { scrollToCurrent(proxy: proxy, plan: plan, animated: false) }
                            .onChange(of: resolved) { _, _ in
                                scrollToCurrent(proxy: proxy, plan: plan, animated: true)
                            }
                            .onChange(of: focusedFieldID) { _, _ in
                                scrollToFocusedField(proxy: proxy)
                            }
                            .onChange(of: keyboardHeight) { _, height in
                                if height > 0 { scrollToFocusedField(proxy: proxy) }
                            }
                        }
                        .frame(width: paneWidth)
                        .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar { keyboardDoneToolbar }
        }
    }

    /// The exercise list for the open layouts: every exercise with its
    /// sets and done count; tap a row to make it the selected card. The
    /// selected row gets the accent border so the current exercise is
    /// obvious at a glance.
    private func exerciseListSection(for plan: DayPlan, selectedID: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercises")
                .font(.headline)
            ForEach(exercises, id: \.id) { template in
                Button {
                    selectedExerciseID = template.id
                    // A manual pick supersedes any lock-screen "Next"
                    // override — the activity falls back to the rest's
                    // exercise on the next sync.
                    store.liveActivitySelectedExerciseID = nil
                } label: {
                    HStack {
                        Text(template.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(template.sets) × \(template.repRange) · \(doneCount(for: template))/\(totalSets(for: template)) done")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(template.id == selectedID ? Color.accentColor : Theme.border, lineWidth: template.id == selectedID ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Propped (Seated / Tent: big live body left, current exercise right)

    /// The open display fills the whole page: the two panes stretch to
    /// the full height. The real-time body fills the LEFT pane BIG (it
    /// scales to the pane, so it uses the full height instead of staying
    /// phone-sized) and the exercise card takes the wide RIGHT pane.
    /// (DaRon 21:32: swap the body to the left so opening the phone
    /// looks just like the outer display — the body stays put on the
    /// left and the workout opens up beside it.) The rest timer no
    /// longer lives in either pane — it slides up from the floating
    /// menu button (DaRon 21:28) — so nothing in either pane ever
    /// resizes the body. An "Up next" list fills the right pane under
    /// the card, then the finisher card and the Finish & Save button
    /// (same components as the regular layout).
    private func proppedLayout(for plan: DayPlan) -> some View {
        // todayContent only calls this layout when exercises is
        // non-empty, so first is never nil here (the empty state is
        // shown instead). The old exercises[0] crashed when the list
        // was emptied in Edit mode or by a Session Mod.
        let currentID = displayedExerciseID(for: plan)
        let current = exercises.first(where: { $0.id == currentID }) ?? exercises.first!
        let next = nextExercise(after: current.id, in: exercises)
        // Plain Group: the page's single NavigationStack lives in body.
        return Group {
            // Title lines up with the two panes below (same 16pt leading
            // as the panes' inset), not flush to the edge.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    calendarTitle(greetingTitle(normal: plan.title))
                    Spacer()
                    workoutActionsMenu
                }
                .padding(.horizontal, 16)
                // D37 (2026-11-10): date line, mirroring the compact
                // layout — the propped layout showed only the title.
                Text(Date(), format: .dateTime.weekday(.wide).month().day())
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .padding(.leading, 16)
                    .padding(.top, 2)
                    .onLongPressGesture(minimumDuration: 0.5, perform: openCalendar)
                // Exact 50/50 split (DaRon 21:10: "still not 50/50"):
                // two flexible panes drift — the ScrollView's content
                // pulls the left pane wider than the body pane. Fixed
                // half-widths, measured from the actual HStack width,
                // so the split is dead center and the hinge line falls
                // in the gap between the panes.
                GeometryReader { geo in
                    // Clamp at 0: during the first layout pass the
                    // GeometryReader can report a zero width, which
                    // would make paneWidth negative (invalid frame).
                    let paneWidth = max((geo.size.width - 16) / 2, 0)
                    HStack(alignment: .top, spacing: 16) {
                    // LEFT: live body, BIG — the current exercise's
                    // muscles, lit up in real time. It fills the
                    // pane's full height.
                    VStack(alignment: .leading, spacing: 16) {
                        LiveBodyView(
                            exerciseID: current.id,
                            nextExerciseID: next?.id,
                            figureHeight: nil,
                            sideBinding: $liveBodySide,
                            userFlippedBinding: $liveBodyUserFlipped
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Fold/unfold morph: the body glides between
                        // panes instead of popping. (DaRon 21:53.)
                        .matchedGeometryEffect(id: "liveBody", in: foldNamespace)
                    }
                    .frame(width: paneWidth)
                    .frame(maxHeight: .infinity)
                    // RIGHT: the current exercise card + "Up next",
                    // then the finisher card + Finish & Save (same as
                    // the regular layout — this pose had neither).
                    // This pane scrolls, so a long card never pushes
                    // the body around.
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                if trainingAnywayPlan != nil {
                                    trainAnywayBanner
                                }
                                ExerciseCard(
                                    template: current,
                                    sets: binding(for: current),
                                    hint: store.progressionHint(for: current),
                                    previousLog: store.lastLog(for: current.id),
                                    isCurrent: true,
                                    isEditing: store.todayEditing,
                                    onMoveUp: { moveExercise(id: current.id, up: true) },
                                    onMoveDown: { moveExercise(id: current.id, up: false) },
                                    onRemove: { store.removeDraftExercise(id: current.id) },
                                    onSwap: { replacement in store.swapDraftExercise(id: current.id, with: replacement) },
                                    swapNote: store.swapNote(for: current),
                                    onFieldFocus: { focusedFieldID = $0 }
                                )
                                .id("exercise-\(current.id)")
                                // Fold/unfold morph: this card is always
                                // the current exercise, so it glides
                                // between layouts. (DaRon 21:53.)
                                .matchedGeometryEffect(id: "currentCard", in: foldNamespace)
                                upNextList(for: plan, current: current)
                                // Finisher + save (same components as the
                                // regular layout, same order): without
                                // these the propped pose had no way to
                                // finish the finisher or save the session
                                // from Today at all.
                                finisherCard(for: store.draftSourcePlan ?? plan)
                                saveButton(for: plan)
                            }
                            // Bottom clearance: keyboard height when up,
                            // else 96pt so the last row never sits under
                            // the floating menu button.
                            .padding(.bottom, contentBottomPadding)
                        }
                        .onAppear { scrollToCurrent(proxy: proxy, plan: plan, animated: false) }
                        .onChange(of: displayedExerciseID(for: plan)) { _, _ in
                            scrollToCurrent(proxy: proxy, plan: plan, animated: true)
                        }
                        .onChange(of: focusedFieldID) { _, _ in
                            scrollToFocusedField(proxy: proxy)
                        }
                        .onChange(of: keyboardHeight) { _, height in
                            if height > 0 { scrollToFocusedField(proxy: proxy) }
                        }
                    }
                    .frame(width: paneWidth)
                    .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar { keyboardDoneToolbar }
        }
    }

    // MARK: - Tent / Seated glanceable layout

    /// Hands-free glanceable view for the short window of the Seated top
    /// half (~475pt tall) and the Tent cover in landscape (~466pt tall).
    /// Big current exercise, a giant Mark Set Done button, a huge rest
    /// timer — readable from a distance while the phone stands on a
    /// surface. Same store, same set logic as SetRow: tapping Done logs
    /// the next set and starts the rest timer.
    @ViewBuilder
    private func tentLayout(for plan: DayPlan) -> some View {
        // Tent pose, StandBy-style (Nov 12, DaRon: "more like the today
        // page but a simplified view that behaves identical to the
        // standby mode"). Two big rounded tiles side by side, readable
        // from across the room:
        // - Left: the current exercise as a simplified Today card — tap a
        //   set to check it off (same as Today: haptic + rest timer).
        //   Swipe up/down to change exercise, like a StandBy widget stack.
        // - Right: a stack you swipe through — rest / next up, the body,
        //   session progress. It jumps to the rest timer on its own when
        //   a rest starts (StandBy's Smart Rotate).
        let currentID = displayedExerciseID(for: plan)
        let current = exercises.first(where: { $0.id == currentID }) ?? exercises.first!
        return HStack(spacing: 14) {
            standbyExerciseTile(current, plan: plan)
            standbyInfoStack(current: current, plan: plan)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // No keyboard lift: this view has no text fields, and a keyboard
        // left over from the list (or a hardware keyboard bar) left a dark
        // band under the tiles.
        .toolbar(.hidden, for: .navigationBar)
        .background(Color.black)
        .onAppear { hideKeyboard() }
    }

    /// StandBy left tile: the current exercise and its sets.
    private func standbyExerciseTile(_ current: ExerciseTemplate, plan: DayPlan) -> some View {
        let logs = store.draftLogs[current.id] ?? []
        let nextIndex = logs.firstIndex(where: { !$0.done })
        let index = exercises.firstIndex(where: { $0.id == current.id }) ?? 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(current.name)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if nextIndex != nil {
                        Text("Current")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { i, set in
                            standbySetRow(set, number: i + 1, isNext: i == nextIndex, template: current)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            // Exercise "stack" dots, like StandBy's widget-stack indicator.
            VStack(spacing: 5) {
                ForEach(exercises.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Color.white : Color.white.opacity(0.25))
                        .frame(width: 5, height: i == index ? 14 : 5)
                }
            }
            .animation(AppAnimation.snappy, value: index)
            .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let v = value.translation.height
                    guard abs(v) > 50, abs(v) > abs(value.translation.width) else { return }
                    tentSwipe(from: current.id, forward: v < 0)
                }
        )
        .accessibilityAction(named: "Next exercise") { tentSwipe(from: current.id, forward: true) }
        .accessibilityAction(named: "Previous exercise") { tentSwipe(from: current.id, forward: false) }
    }

    /// One set, StandBy-sized: tap anywhere on it to check it off.
    private func standbySetRow(_ set: SetLog, number: Int, isNext: Bool, template: ExerciseTemplate) -> some View {
        Button { toggleSet(number - 1, of: template) } label: {
            HStack(spacing: 12) {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.done ? CompletedTint.completedGlyph : isNext ? Color.accentColor : Theme.tertiaryText)
                Text("\(store.displayWeightLabel(set.weightLb, isPair: template.isPair, for: template)) × \(set.reps)")
                    .scaledFont(size: isNext ? 30 : 22, weight: .bold, design: .rounded, maxScale: 1.4)
                    .monospacedDigit()
                    .foregroundStyle(set.done ? Theme.secondaryText : Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if set.kind != .working {
                    Text(set.kind.shortLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, isNext ? 8 : 4)
            .padding(.horizontal, 10)
            .background(isNext ? Color.accentColor.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set \(number), \(set.done ? "done" : "not done")")
        .accessibilityHint("Double-tap to \(set.done ? "uncheck" : "check off") this set")
    }

    /// Same as Today's set checkbox: toggle, haptic, and start the rest
    /// timer on a working set.
    private func toggleSet(_ index: Int, of template: ExerciseTemplate) {
        var logs = store.draftLogs[template.id] ?? []
        guard logs.indices.contains(index) else { return }
        logs[index].done.toggle()
        let done = logs[index].done
        let kind = logs[index].kind
        store.draftLogs[template.id] = logs
        if done {
            if store.settings.hapticsEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            if kind != .warmup { store.startRest(for: template) }
        }
    }

    private enum StandbyCard: Int, CaseIterable, Hashable { case rest, body, progress }

    /// StandBy right tile: swipe up/down through rest / body / progress.
    private func standbyInfoStack(current: ExerciseTemplate, plan: DayPlan) -> some View {
        GeometryReader { geo in
            HStack(spacing: 10) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(StandbyCard.allCases, id: \.self) { card in
                            standbyCard(card, current: current, plan: plan)
                                .frame(width: geo.size.width - 31, height: geo.size.height)
                                .id(card)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $standbyCard)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                VStack(spacing: 5) {
                    ForEach(StandbyCard.allCases, id: \.self) { card in
                        Capsule()
                            .fill(card == (standbyCard ?? .rest) ? Color.white : Color.white.opacity(0.25))
                            .frame(width: 5, height: card == (standbyCard ?? .rest) ? 14 : 5)
                    }
                }
                .frame(width: 21)
                .accessibilityHidden(true)
            }
        }
        // Smart Rotate: a rest starting brings the timer to the front.
        .onChange(of: store.restEndsAt) { _, endsAt in
            if endsAt != nil { withAnimation(AppAnimation.snappy) { standbyCard = .rest } }
        }
    }

    @ViewBuilder
    private func standbyCard(_ card: StandbyCard, current: ExerciseTemplate, plan: DayPlan) -> some View {
        Group {
            switch card {
            case .rest: standbyRestCard(current: current, plan: plan)
            case .body:
                LiveBodyView(
                    exerciseID: current.id,
                    nextExerciseID: nextExercise(after: current.id, in: exercises)?.id,
                    figureHeight: nil,
                    sideBinding: $liveBodySide,
                    userFlippedBinding: $liveBodyUserFlipped
                )
                .padding(14)
            case .progress:
                sessionProgressCard
                    .padding(14)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card)
    }

    /// Rest countdown ring while resting (tap to skip); otherwise what's
    /// next, or Finish & Save once everything is done.
    @ViewBuilder
    private func standbyRestCard(current: ExerciseTemplate, plan: DayPlan) -> some View {
        if let endsAt = store.restEndsAt {
            let total = max(store.restSeconds(for: current), 1)
            Button { store.cancelRest() } label: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, endsAt.timeIntervalSince(context.date))
                    let secs = Int(remaining.rounded(.up))
                    ZStack {
                        Circle().stroke(Theme.track, lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: remaining / total)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 1), value: secs)
                        VStack(spacing: 2) {
                            Text("\(secs / 60):\(String(format: "%02d", secs % 60))")
                                .scaledFont(size: 54, weight: .bold, design: .rounded, maxScale: 1.3)
                                .monospacedDigit()
                            Text("Rest · tap to skip")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(22)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rest timer. Double-tap to skip.")
        } else if store.restPausedRemaining != nil {
            Label("Rest paused", systemImage: "pause.circle")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.secondaryText)
        } else if let next = nextExercise(after: current.id, in: exercises) {
            let allDone = (store.draftLogs[current.id] ?? []).allSatisfy(\.done)
            VStack(alignment: .leading, spacing: 6) {
                Text("Next up")
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)
                Text(next.name)
                    .scaledFont(size: 34, weight: .bold, design: .rounded, maxScale: 1.4)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 0)
                if allDone {
                    Button { tentSwipe(from: current.id, forward: true) } label: {
                        Label("Go to \(next.name)", systemImage: "arrow.right.circle.fill")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 14) {
                Text("Last exercise")
                    .font(.title2.weight(.bold))
                saveButton(for: plan)
            }
            .padding(20)
        }
    }

    /// Page-turn in the Tent/Seated layout: swipe to the next exercise
    /// (or back to the previous one). Same state a tap advances — the
    /// set dots, "Next up", and the body highlight all follow the
    /// selected exercise. Stops at the first/last exercise.
    private func tentSwipe(from currentID: String, forward: Bool) {
        guard let index = exercises.firstIndex(where: { $0.id == currentID }) else { return }
        let target = forward ? index + 1 : index - 1
        guard exercises.indices.contains(target) else { return }
        if store.settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        // A manual swipe supersedes any lock-screen "Next" override.
        store.liveActivitySelectedExerciseID = nil
        withAnimation(AppAnimation.snappy) {
            selectedExerciseID = exercises[target].id
        }
    }

    /// Same set-completion logic as SetRow: log the next undone set, give
    /// haptic feedback, and start the rest timer (unless it's a warm-up).
    private func markNextSetDone(for template: ExerciseTemplate) {
        var logs = store.draftLogs[template.id] ?? []
        guard let idx = logs.firstIndex(where: { !$0.done }) else { return }
        logs[idx].done = true
        store.draftLogs[template.id] = logs
        // If that was the last set, clear the swipe selection so the
        // next undone exercise becomes current on its own.
        if logs.allSatisfy({ $0.done }) {
            selectedExerciseID = nil
        }
        if store.settings.hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if logs[idx].kind != .warmup {
            store.startRest(for: template)
        }
    }

    /// The rest of today's exercises under the current card (open
    /// layout): name + sets × reps + done count, so the left pane reads
    /// as the whole workout instead of one card floating in space.
    @ViewBuilder
    private func upNextList(for plan: DayPlan, current: ExerciseTemplate) -> some View {
        let rest = exercises.filter { $0.id != current.id }
        if !rest.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Up next")
                    .font(.headline)
                ForEach(rest, id: \.id) { template in
                    HStack {
                        Text(template.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(template.sets) × \(template.repRange) · \(doneCount(for: template))/\(totalSets(for: template)) done")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Shared pieces

    private func moveExercise(id: String, up: Bool) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        let target = up ? index - 1 : index + 1
        guard exercises.indices.contains(target) else { return }
        store.draftExercises.move(fromOffsets: IndexSet(integer: index), toOffset: up ? target : target + 1)
    }

    /// The one top-bar action, FAR RIGHT on the title row. Normally a
    /// vivid "+" whose menu holds Edit, Add exercise and Modify today;
    /// once Edit is picked, the SAME button turns into a check mark —
    /// tap the ✓ to finish editing and it goes back to "+". Same spot,
    /// same size, same accent. (DaRon 22:14: "After clicking edit the
    /// button needs to turn into a check mark to click to be a done.")
    /// Position rule (DaRon 2026-11-10: the "+" drifted between poses):
    /// this button NEVER lives in a toolbar — it sits in the title
    /// row in every layout. Its own trailing 16pt plus the row's
    /// 16pt puts its center exactly 60pt from the right edge, on the
    /// same axis as the card "+" and the floating menu button below,
    /// in all four layouts. (DaRon 21:25: move the button to the far
    /// right; supersedes "by the title" from 21:19.)
    private var workoutActionsMenu: some View {
        Group {
            if store.todayEditing {
                Button { store.todayEditing = false } label: {
                    actionButtonIcon("checkmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done editing")
            } else {
                Menu {
                    Button("Edit") { store.todayEditing = true }
                    Button("Add exercise") { store.todayAddExercise = true }
                    Button("Modify today") { store.todaySessionMod = true }
                } label: {
                    actionButtonIcon("plus")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Workout actions")
            }
        }
        .animation(AppAnimation.snappy, value: store.todayEditing)
        // Open Duo with the workout on the clock's side: the + sits on the
        // same center line as the swap/menu buttons, under the Wi-Fi icon
        // (47pt from the edge; the column's own 16pt inset + 3 + 28).
        // Glides with the pages during a swap (no snap afterwards).
        // (Trailing padding lives in CornerColumnOffset, which reads the
        // pair's values from inside it.)
        // DS layout, page beside the corner buttons: the + moves out into
        // their column (DaRon: "with the other buttons").
        .modifier(CornerColumnOffset())
        // Side status bar on: the + lives in the rail (ContentView); the
        // title row keeps its space.
        .opacity(inRail ? 0 : 1)
        .allowsHitTesting(!inRail)
        .accessibilityHidden(inRail)
    }

    /// The vivid circular action button (56pt, accent fill, glow):
    /// "+" normally, "✓" while editing. One shared shape so both
    /// states are the same size, spot and visibility.
    private func actionButtonIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .scaledFont(size: 26, weight: .bold)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .accentGlass(Circle())
            .shadow(color: Color.accentColor.opacity(0.5), radius: 10, x: 0, y: 4)
    }

    private func header(for plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(plan.title)
                    .font(.title2)
                    .bold()
                Spacer()
                workoutActionsMenu
            }
            // Subtitle in full-bright primary text, larger — the dim
            // secondary gray was unreadable on black. (DaRon 21:25:
            // "i cant read the words under".)
            Text(plan.subtitle)
                .font(.body)
                .foregroundStyle(Theme.text)
            if let mod = store.draftSessionMod, mod.shorterSession {
                Text("Shorter today")
                    .font(.caption)
                    .foregroundStyle(Theme.text)
            }
        }
    }

    private func binding(for template: ExerciseTemplate) -> Binding<[SetLog]> {
        Binding(
            get: { store.draftLogs[template.id] ?? [] },
            set: { store.draftLogs[template.id] = $0 }
        )
    }

    private func currentExerciseID(for plan: DayPlan) -> String? {
        exercises.first { template in
            let sets = store.draftLogs[template.id] ?? []
            return sets.isEmpty || sets.contains { !$0.done }
        }?.id
    }

    /// The exercise the UI treats as current: an explicit selection
    /// (card tap, Tent swipe, lock-screen "Next") if it still exists
    /// in today's list, else the first exercise with sets left, else
    /// the first exercise. Validating the selection stops a removed
    /// or swapped exercise from blanking the regular card.
    private func displayedExerciseID(for plan: DayPlan) -> String? {
        if let id = selectedExerciseID, exercises.contains(where: { $0.id == id }) {
            return id
        }
        return currentExerciseID(for: plan) ?? exercises.first?.id
    }

    /// Fold/unfold morph for the current exercise's card: only the
    /// current card carries the shared "currentCard" id, so it glides
    /// between layouts (compact list ↔ open right pane ↔ tent panel)
    /// instead of popping. Every other card is left alone — attaching
    /// the same id to all of them would collapse them onto one frame.
    /// (DaRon 21:53.)
    @ViewBuilder
    private func foldCard<Content: View>(_ content: Content, isCurrent: Bool) -> some View {
        if isCurrent {
            content.matchedGeometryEffect(id: "currentCard", in: foldNamespace)
        } else {
            content
        }
    }

    /// Scrolls the workout list so the current exercise's card sits at
    /// the top — the user's place survives a pose change. Each layout
    /// has its own ScrollView, so without this a fold/unfold recreates
    /// the list at offset 0 and the current card scrolls out of sight.
    /// (Debug Pass 2, fold glitch): `animated` is FALSE on appear —
    /// the restore lands before the new layout's first frame, so it is
    /// invisible — and TRUE only when the user picks another exercise.
    /// The old version animated on appear too, with a 0.25s snappy
    /// spring while the 0.45s fold spring was morphing the same content:
    /// two springs fighting over one scroll view, which read as judder
    /// mid-fold. Restoring instantly on appear also means the return to
    /// the open display never visibly yanks the list.
    private func scrollToCurrent(proxy: ScrollViewProxy, plan: DayPlan, animated: Bool) {
        if let id = displayedExerciseID(for: plan) {
            if animated {
                withAnimation(AppAnimation.snappy) {
                    proxy.scrollTo("exercise-\(id)", anchor: .top)
                }
            } else {
                proxy.scrollTo("exercise-\(id)", anchor: .top)
            }
        }
    }

    /// Scrolls the focused field into view (anchor .center, so it lands
    /// above the keyboard instead of behind it). The keyboard's height
    /// is bottom inset on every layout, so there is always room to
    /// scroll the field up — without the inset, a field near the
    /// bottom of the list could never clear the keyboard.
    private func scrollToFocusedField(proxy: ScrollViewProxy) {
        if let id = focusedFieldID {
            // The middle of what's above the keyboard (and its floating
            // Done), not of the whole page: the page ignores the keyboard,
            // so .center put the field behind it in landscape (DaRon).
            let h = max(pageContainerSize.height, 1)
            let open = max(h - keyboardHeight - 70, h * 0.2)
            let y = min(0.5, max(0.08, open / h * 0.5))
            withAnimation(AppAnimation.snappy) {
                proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: y))
            }
        }
    }

    private func nextExercise(after id: String, in list: [ExerciseTemplate]) -> ExerciseTemplate? {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        let nextIndex = index + 1
        return nextIndex < list.count ? list[nextIndex] : nil
    }

    private func doneCount(for template: ExerciseTemplate) -> Int {
        (store.draftLogs[template.id] ?? []).filter { $0.done }.count
    }

    /// Planned sets, or the actual draft row count when sets were added
    /// — the list denominator (D1, 2026-11-10).
    private func totalSets(for template: ExerciseTemplate) -> Int {
        max(template.sets, (store.draftLogs[template.id] ?? []).count)
    }

    private func finisherCard(for plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pump finisher")
                .font(.headline)
            Text("Finish every session fully pumped.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            ForEach(plan.finisher.indices, id: \.self) { index in
                Button {
                    if index < store.draftFinisherChecks.count {
                        store.draftFinisherChecks[index].toggle()
                    }
                } label: {
                    HStack {
                        Image(systemName: store.draftFinisherChecks.indices.contains(index) && store.draftFinisherChecks[index]
                              ? "checkmark.circle.fill" : "circle")
                            // Done: faint accent tint, not vivid green.
                            // (DaRon 22:32.)
                            .foregroundStyle(store.draftFinisherChecks.indices.contains(index) && store.draftFinisherChecks[index]
                                             ? CompletedTint.completedGlyph : Theme.tertiaryText)
                        Text(plan.finisher[index])
                            .font(.subheadline)
                            // The finisher line wraps to its full height,
                            // never truncates mid-item ("Lat Pulldown
                            // 2 × 12," — DaRon 2026-11-10).
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private func saveButton(for plan: DayPlan) -> some View {
        Button {
            saveSession(for: plan)
        } label: {
            Text("Finish & Save Session")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func saveSession(for plan: DayPlan) {
        // A double-tap on Finish saved two sessions (a fresh UUID each
        // time). saved is true while the confirmation alert is up, so
        // a second tap in that window is a no-op; once the alert is
        // dismissed the flag clears and a later session can save.
        guard !saved else { return }
        // Save the workout that was actually done: the draft's source
        // plan, not whatever plan is current now. If the plan changed
        // mid-day, the current plan's title would mislabel the session
        // (the 17:39 "Legs" session that held push exercises).
        let sourcePlan = store.draftSourcePlan ?? plan
        let exerciseLogs = exercises.map { template in
            ExerciseLog(
                exerciseId: template.id,
                name: template.name,
                isPair: template.isPair,
                sets: store.draftLogs[template.id] ?? [],
                unitOverride: template.unitOverride
            )
        }
        // The label comes from the session itself (its date and the
        // exercises actually logged) — never copied from a plan — so a
        // train-anyway session or a mid-workout swap can never mislabel
        // it again. See WorkoutStore.sessionLabel.
        let savedAt = Date()
        let label = WorkoutStore.sessionLabel(date: savedAt, plan: sourcePlan, exercises: exerciseLogs, customs: store.customExercises)
        let session = SessionLog(
            id: UUID(),
            date: savedAt,
            dayKey: label.dayKey,
            dayTitle: label.dayTitle,
            exercises: exerciseLogs,
            finisherDone: store.draftFinisherChecks.allSatisfy { $0 },
            finisherNotes: sourcePlan.finisher.joined(separator: "; ")
        )
        store.saveSession(session)
        // Notes written on today's cards land on the Notes page, one
        // note per exercise with text (title = exercise, subtitle =
        // the day). Only saved workouts appear there — the draft is
        // cleared right after, so harvest first.
        for (exerciseID, text) in store.draftNotes {
            if let template = exercises.first(where: { $0.id == exerciseID }) {
                // The note is stamped with when it was typed, not when
                // the workout was saved. (DaRon 21:51.)
                store.addWorkoutNote(exerciseName: template.name, dayTitle: sourcePlan.title, text: text, date: store.draftNoteTimes[exerciseID] ?? Date())
            }
        }
        store.clearDraft()
        saved = true
        store.ensureDraft(for: plan)
        // A "Train anyway" session ends back on the rest-day screen:
        // the override clears, so Today falls back to the rest-day
        // view for today. (On a normal workout day this is nil
        // already — a no-op.) The saved session is dated today either
        // way, and the schedule is unchanged.
        trainingAnywayPlan = nil
    }
}

// MARK: - Rest timer (custom default + per-exercise override, +/- buttons,
// sound + haptic on expiry — the single most-customized setting in the
// category. Leap's REST screen has a "+20s" button and SKIP; Strong/JEFIT
// have +/- while running.)
//
// This card is the FLOATING timer panel now (DaRon 21:28): it lives in
// ContentView, anchored to the floating menu button — it slides up from
// behind the button when a rest starts and back down when the rest ends
// or Stop is tapped. It no longer sits inside any workout layout, so it
// can never resize the body or push the workout list around. All timer
// behavior is unchanged (counts down live, Pause freezes/resumes, Stop
// cancels, +/− adjust, "Drink water" on every rest).

struct RestTimerCard: View {
    @EnvironmentObject var store: WorkoutStore

    /// Tent / Seated glanceable mode: giant countdown and 56pt pills,
    /// readable from a distance while the phone stands on a surface.
    var large: Bool = false
    /// Exactly one mounted RestTimerCard plays the end-of-rest sound and
    /// haptic. The inline copy in the exercise card turns this off; a
    /// hidden copy in ContentView keeps it (Nov 12).
    var playsFeedback: Bool = true
    /// Pill mode (Nov 12): pops up as the compact countdown pill right
    /// above the menu button; tap it for the full controls, the chevron
    /// shrinks it back. Every new rest starts as the pill.
    var pill: Bool = false
    /// The pill's height (the side bar fits it to the room it has).
    var pillHeight: CGFloat = 200

    /// D33 (2026-11-10): collapsed to the compact countdown chip.
    /// Per-rest — resets whenever a new rest starts.
    @State private var collapsed: Bool? = nil
    private var isCollapsed: Bool { collapsed ?? pill }

    /// The app's effective accent (Pro accent, else the default) — the
    /// lava liquid's color.
    private var pillAccent: Color {
        store.isPro ? store.settings.accentColor.color : Theme.accent
    }

    /// The full length of this rest, so the liquid starts full. A +15s
    /// beyond it just keeps the pill full until it drains back down.
    private var restTotal: TimeInterval {
        let template = store.restTemplateID.flatMap { id in store.draftExercises.first { $0.id == id } }
        return max(store.restSeconds(for: template), store.restRemainingSeconds ?? 0)
    }

    var body: some View {
        // The pill's presence is the corner column's call: it keeps
        // drawing while it shrinks away after the rest ends (it used to
        // turn empty at once, so it vanished instead of shrinking).
        if pill || store.restEndsAt != nil || store.restPausedRemaining != nil {
            TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                let remaining = store.restRemainingSeconds ?? 0
                let paused = store.isRestPaused
                if isCollapsed {
                    // D33: collapsed countdown chip (~44pt) — covers
                    // almost nothing, so the set rows stay visible and
                    // editable while the rest runs. Tap to re-expand.
                    Button {
                        withAnimation(AppAnimation.snappy) { collapsed = false }
                    } label: {
                        if pill {
                            // Upright pill (DaRon, Nov 12): the same 56pt
                            // width as the swap and menu buttons below it,
                            // so the three read as one column.
                            // Lava-lamp pill (DaRon, Nov 12): glass filled
                            // with glowing accent liquid that drains to
                            // empty as the rest counts down to zero.
                            VStack(spacing: 8) {
                                Image(systemName: paused ? "pause.fill" : "timer")
                                    .scaledFont(size: 17, weight: .semibold, maxScale: 1.3)
                                Text(formatted(max(0, remaining)))
                                    .scaledFont(size: 15, weight: .heavy, design: .rounded, maxScale: 1.3)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Image(systemName: "chevron.up")
                                    .font(.caption2.weight(.bold))
                                    .opacity(0.8)
                            }
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                            // As tall as three buttons in the column below,
                            // gaps included (3 × 56 + 2 × 16), DaRon Nov 12.
                            .frame(width: 56, height: pillHeight)
                            // Same material as the swap and menu buttons:
                            // frosted, plain border, soft shadow — no gloss.
                            // The liquid sits inside real Liquid Glass, like
                            // the swap and menu buttons below it.
                            .background {
                                LavaLiquidFill(
                                    endsAt: store.restEndsAt,
                                    pausedRemaining: store.restPausedRemaining,
                                    total: restTotal,
                                    color: pillAccent
                                )
                                .clipShape(Capsule())
                            }
                            .liquidGlass(Capsule())
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "timer")
                                    .foregroundStyle(Color.accentColor)
                                Text(paused ? "Paused" : "Rest")
                                    .font(.subheadline.weight(.semibold))
                                Text(formatted(max(0, remaining)))
                                    .font(.subheadline.weight(.bold))
                                    .monospacedDigit()
                                Image(systemName: "chevron.up")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.card)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Expand rest timer")
                } else {
                    // Floating panel (DaRon 21:28): it slides up from the
                    // menu button in ContentView.bottomStack, so unlike
                    // the old inline card it CAN cover set rows while
                    // open — the chevron below collapses it to the chip
                    // (D33). The Tent `large` variant keeps its stacked
                    // giant time.
                    VStack(alignment: .leading, spacing: large ? 10 : 6) {
                    HStack(spacing: large ? 12 : 8) {
                        if large {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(paused ? "Paused" : (remaining > 0 ? "Rest" : "Rest over — time to lift"))
                                    .font(.headline)
                                Text(formatted(max(0, remaining)))
                                    .scaledFont(size: 64, weight: .bold)
                                    .monospacedDigit()
                            }
                        } else {
                            Text(paused ? "Paused" : (remaining > 0 ? "Rest" : "Rest over — time to lift"))
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(formatted(max(0, remaining)))
                                .font(.title)
                                .bold()
                                .monospacedDigit()
                        }
                        Spacer()
                        // The rest length in effect (per-exercise override or global).
                        if let id = store.restTemplateID,
                           let template = store.draftExercises.first(where: { $0.id == id }) {
                            Text("\(Int(store.restSeconds(for: template)))s")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.cardElevated)
                                .clipShape(Capsule())
                        }
                        // D33: collapse to the countdown chip so the panel
                        // stops covering the set rows below it.
                        Button {
                            withAnimation(AppAnimation.snappy) { collapsed = true }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Collapse rest timer")
                    }
                    // Sip reminder between sets — small sips during rest.
                    // It never extends the rest time.
                    HStack(spacing: 6) {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(.blue)
                        Text("Drink water")
                            .font(.subheadline.weight(.medium))
                    }
                    // One-line pill buttons: fixed minimum widths sized to
                    // each label so the text never wraps (DaRon flagged
                    // "Paus e" / "Sto p" / "+2 0s" on the open display,
                    // 19:28). lineLimit(1) + minimumScaleFactor are the
                    // safety net; 44pt min height keeps the tap target
                    // (56pt in the large Tent variant).
                    HStack(spacing: 6) {
                        Button("−15s") { store.adjustRest(by: -15) }
                            .buttonStyle(TimerPillStyle(minWidth: 46, minHeight: large ? 56 : 44))
                        Button("+15s") { store.adjustRest(by: 15) }
                            .buttonStyle(TimerPillStyle(minWidth: 46, minHeight: large ? 56 : 44))
                        Button("+20s") { store.adjustRest(by: 20) }
                            .buttonStyle(TimerPillStyle(minWidth: 46, minHeight: large ? 56 : 44))
                        Spacer()
                        Button(paused ? "Resume" : "Pause") {
                            withAnimation(AppAnimation.snappy) {
                                if paused { store.resumeRest() } else { store.pauseRest() }
                            }
                        }
                        .buttonStyle(TimerPillStyle(minWidth: 62, minHeight: large ? 56 : 44))
                        Button("Stop") {
                            withAnimation(AppAnimation.snappy) { store.cancelRest() }
                        }
                        .buttonStyle(TimerPillStyle(minWidth: 54, minHeight: large ? 56 : 44, prominent: true))
                    }
                }
                .padding(.horizontal, large ? 16 : 12)
                .padding(.vertical, large ? 16 : 8)
                // Pill mode, opened: a fixed-width panel above the button.
                .frame(width: pill ? 340 : nil, alignment: .leading)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
                }
            }
            // D33: collapsed state is per-rest — a new rest re-expands
            // the full panel.
            .onChange(of: store.restEndsAt) { _, _ in collapsed = nil }
            .task(id: store.restEndsAt) {
                // Play sound + haptic the moment the timer ends, then
                // auto-dismiss 5s later. A new set restarts the timer (a new
                // endsAt cancels this task). Pausing clears endsAt, which
                // cancels this task — it restarts on resume.
                guard playsFeedback, let endsAt = store.restEndsAt else { return }
                let untilEnd = endsAt.timeIntervalSinceNow
                if untilEnd > 0 {
                    try? await Task.sleep(for: .seconds(untilEnd))
                    await MainActor.run {
                        if store.restEndsAt == endsAt {
                            playExpiryFeedback()
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(5))
                await MainActor.run {
                    if store.restEndsAt == endsAt {
                        store.restEndsAt = nil
                    }
                }
            }
        }
    }

    private func playExpiryFeedback() {
        if store.settings.restSoundEnabled {
            AudioServicesPlaySystemSound(1005)
        }
        if store.settings.restHapticEnabled && store.settings.hapticsEnabled {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        store.flashRestCompleteSignalIfEnabled()
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

// MARK: - Rest-timer pill button (one-line labels, 44pt tap target)

/// Compact pill for the rest timer: the label is single-line by
/// construction (lineLimit(1) + minimumScaleFactor) and the pill is at
/// least `minWidth` wide, so "Pause" / "Stop" / "−15s" never wrap into
/// two lines even in narrow panes. Blue tint matches the old .bordered
/// look; Stop is prominent red.
private struct TimerPillStyle: ButtonStyle {
    var minWidth: CGFloat
    var minHeight: CGFloat = 44
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .frame(minWidth: minWidth, minHeight: minHeight)
            .background(Capsule().fill(prominent ? Theme.vividRed : Color.accentColor.opacity(0.15)))
            .foregroundStyle(prominent ? Color.white : Color.accentColor)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Exercise card (Fitbod set-table pattern: rest pill, History /
// Replace pills, Add Set; Hevy reorder / swap mid-workout)

struct ExerciseCard: View {
    let template: ExerciseTemplate
    @Binding var sets: [SetLog]
    let hint: String
    let previousLog: ExerciseLog?
    let isCurrent: Bool
    var isEditing: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onRemove: () -> Void = {}
    var onSwap: (ExerciseTemplate) -> Void = { _ in }
    /// One-line injury-swap note for this exercise ("Swapped because of
    /// your shoulder injury"), from the adapted program's swap list.
    /// Nil when the exercise wasn't swapped.
    var swapNote: String? = nil
    /// Reports focus changes up to TodayView ("field-note-<id>",
    /// "field-weight-<id>-<set>", "field-reps-<id>-<set>",
    /// "field-routine-<id>", or nil on blur) so the layout can scroll
    /// the focused field above the keyboard. Nil = no focus reporting.
    var onFieldFocus: ((String?) -> Void)? = nil

    @EnvironmentObject private var store: WorkoutStore
    @State private var showOptions = false
    @State private var showSwap = false
    @State private var showHistory = false
    @State private var showPlates = false
    @State private var noteText: String = ""
    @FocusState private var noteFocused: Bool
    @FocusState private var routineNoteFocused: Bool

    private var isBarbell: Bool {
        ExerciseLibrary.byId(template.id, plus: store.customExercises)?.equipment.contains(.barbell) == true
    }

    private var doneCount: Int { sets.filter { $0.done }.count }

    /// Planned sets, or the actual row count when sets were added —
    /// the header denominator (D1, 2026-11-10): an added set must read
    /// "1/4 done", never "1/3 done".
    private var totalSets: Int { max(template.sets, sets.count) }

    /// Every set done (extra added sets count too — "4/3 done" is fully
    /// done). Drives the muted completed colors for the whole card.
    /// (DaRon 22:32: completed work mutes to a faint accent tint.)
    private var isFullyDone: Bool { !sets.isEmpty && sets.allSatisfy { $0.done } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(template.name)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                if isCurrent {
                    Text("Current")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(isFullyDone ? CompletedTint.completedGlyph : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isFullyDone ? CompletedTint.completedFill : Color.accentColor)
                        .clipShape(Capsule())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                // Rest pill (Fitbod "1:30 rest" pattern) — the rest length
                // in effect for this exercise. The scale factor keeps the
                // pill on one line instead of clipping at narrow widths
                // (the DB Row header was cut off in the open pose, 20:52).
                Text("\(Int(store.restSeconds(for: template)))s rest")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.cardElevated)
                    .clipShape(Capsule())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text("\(template.sets) × \(template.repRange) · \(doneCount)/\(totalSets) done")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let swapNote {
                Label(swapNote, systemImage: "arrow.triangle.swap")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = template.weightNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let cues = template.cues {
                // The cue wraps to its full height, never truncates
                // mid-word ("Pull the bar to your upper c…", "don't
                // lean ba…" — DaRon 2026-11-10).
                Text(cues)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let routineNote = template.note, !routineNote.isEmpty {
                Text("Note: \(routineNote)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Edit-mode reorder / remove (drag-to-reorder is unreliable in a
            // ScrollView; up/down buttons are Duo-friendly and always work).
            if isEditing {
                HStack(spacing: 12) {
                    Button { onMoveUp() } label: {
                        Label("Move up", systemImage: "arrow.up")
                    }
                    Button { onMoveDown() } label: {
                        Label("Move down", systemImage: "arrow.down")
                    }
                    Spacer()
                    Button(role: .destructive) { onRemove() } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            ForEach(Array(sets.enumerated()), id: \.offset) { index, _ in
                SetRow(
                    number: index + 1,
                    set: $sets[index],
                    template: template,
                    previous: previousSet(at: index),
                    onDelete: { store.removeSet(at: index, for: template) },
                    onFieldFocus: onFieldFocus
                )
            }

            // Set-table actions, one compact row (Nov 12 UI pass): a
            // direct "+ Add set" (the common action, one tap) and a
            // "•••" menu for History / Replace / Options. Replaces the
            // 56pt blue "+" that opened all four — it looked identical
            // to the header "+" and the set-type "+", and its own row
            // left a large empty gap in the card.
            HStack(spacing: 12) {
                Button { store.addSet(to: template) } label: {
                    Label("Add set", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isFullyDone ? CompletedTint.completedGlyph : Color.accentColor)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background((isFullyDone ? CompletedTint.completedFill : Color.accentColor.opacity(0.15)),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
                Menu {
                    Button("History") { showHistory = true }
                    Button("Replace") { showSwap = true }
                    Button(showOptions ? "Hide options" : "Options") { showOptions.toggle() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 44, height: 36)
                        .background(Theme.border.opacity(0.35), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More exercise actions")
            }

            if showOptions {
                exerciseOptions
            }

            // Per-exercise session note (Hevy pattern: live-session note for
            // this workout only). Plain text field, so the default QWERTY
            // keyboard is correct here (weight/reps use the numeric
            // keypads). Focus is reported up so the layout scrolls this
            // field above the keyboard; Return dismisses it.
            TextField("Note for this workout (optional)", text: $noteText)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
                .focused($noteFocused)
                .id("field-note-\(template.id)")
                .onChange(of: noteFocused) { _, focused in
                    onFieldFocus?(focused ? "field-note-\(template.id)" : nil)
                }
                .onSubmit { noteFocused = false }
                .onAppear { noteText = store.draftNotes[template.id] ?? "" }
                .onChange(of: noteText) { _, newValue in
                    store.draftNotes[template.id] = newValue
                    // Stamp the moment the note was first typed, not
                    // the moment the workout is saved. (DaRon 21:51:
                    // the note must be timestamped correctly.) Clearing
                    // the text clears the stamp, so a retyped note gets
                    // a fresh time.
                    if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        store.draftNoteTimes.removeValue(forKey: template.id)
                    } else if store.draftNoteTimes[template.id] == nil {
                        store.draftNoteTimes[template.id] = Date()
                    }
                }

            // The hint must read in full — in the Closed pose it was
            // cut off at the card edge. Let it wrap to its full height
            // instead of truncating. (DaRon 21:26, polish queue.)
            // On a fully done card the hint mutes with the rest of the
            // card to the faint completed tint. (DaRon 22:32.)
            Text(hint)
                .font(.caption)
                .foregroundStyle(isFullyDone ? CompletedTint.completedGlyph : Color.accentColor)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .sheet(isPresented: $showSwap) {
            SwapExerciseSheet(current: template) { replacement in
                onSwap(replacement)
            }
        }
        .sheet(isPresented: $showHistory) {
            ExerciseHistorySheet(template: template)
        }
        .sheet(isPresented: $showPlates) {
            PlateCalculatorSheet(template: template)
        }
    }

    private var exerciseOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Plate calculator (barbell exercises only).
            if isBarbell {
                Button("Plate calculator") { showPlates = true }
                    .font(.caption)
                    .buttonStyle(.bordered)
            }
            // Per-exercise rest override.
            HStack {
                Text("Rest")
                    .font(.caption)
                Spacer()
                // Bounded stepper (DaRon 2026-11-10 08:54: the native
                // stepper's + side ran off the right edge, with a heavy
                // black divider and flat muddy gray). Same 60 s floor,
                // same 15 s step, same binding — layout only, so the
                // override still saves exactly as before.
                RowStepper(value: restOverrideBinding, range: 60...300, step: 15) { "\(Int($0))s" }
            }
            // Per-exercise unit override.
            HStack {
                Text("Units")
                    .font(.caption)
                Spacer()
                Picker("Units", selection: unitOverrideBinding) {
                    Text("Default (\(store.settings.weightUnit.label))").tag(WeightUnit?.none)
                    Text("lb").tag(WeightUnit?.some(.lb))
                    Text("kg").tag(WeightUnit?.some(.kg))
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            // Recommend More / Less / Exclude (Fitbod feedback loop).
            HStack {
                Text("Recommend")
                    .font(.caption)
                Spacer()
                Picker("Recommend", selection: preferenceBinding) {
                    ForEach(ExercisePreference.allCases, id: \.self) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                .pickerStyle(.menu)
            }
            // Routine note (shown every time this exercise appears).
            TextField("Routine note (shown every time)", text: routineNoteBinding)
                .font(.caption)
                .textFieldStyle(.roundedBorder)
                .focused($routineNoteFocused)
                .id("field-routine-\(template.id)")
                .onChange(of: routineNoteFocused) { _, focused in
                    onFieldFocus?(focused ? "field-routine-\(template.id)" : nil)
                }
                .onSubmit { routineNoteFocused = false }
        }
        .padding()
        .background(Theme.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
    }

    private var restOverrideBinding: Binding<Double> {
        Binding(
            get: { template.restSeconds ?? store.settings.restSecondsDefault },
            set: { newValue in
                if let index = store.draftExercises.firstIndex(where: { $0.id == template.id }) {
                    store.draftExercises[index].restSeconds = newValue
                }
            }
        )
    }

    private var unitOverrideBinding: Binding<WeightUnit?> {
        Binding(
            get: { template.unitOverride },
            set: { newValue in
                if let index = store.draftExercises.firstIndex(where: { $0.id == template.id }) {
                    store.draftExercises[index].unitOverride = newValue
                }
            }
        )
    }

    private var preferenceBinding: Binding<ExercisePreference> {
        Binding(
            get: { store.preference(for: template.id) },
            set: { store.setPreference($0, for: template.id) }
        )
    }

    private var routineNoteBinding: Binding<String> {
        Binding(
            get: { template.note ?? "" },
            set: { newValue in
                if let index = store.draftExercises.firstIndex(where: { $0.id == template.id }) {
                    store.draftExercises[index].note = newValue.isEmpty ? nil : newValue
                }
            }
        )
    }

    private func previousSet(at index: Int) -> SetLog? {
        guard let previousLog, previousLog.sets.indices.contains(index) else { return nil }
        return previousLog.sets[index]
    }
}

// MARK: - Set row: numbers only, tap-to-edit fields + keypad, set-type badge
// (Strong / Hevy pattern). The two side-by-side steppers overflowed the
// 466pt folded Duo display, so they are gone.

/// The ONE height for every control in a set row (DaRon 2026-11-10
/// 08:19–08:20: the red Delete button was taller than the weight/reps
/// boxes, so the row was not flush). The weight and reps boxes are
/// exactly this tall, which sets the row's height — and the swipe
/// Delete button fills the row, so it is exactly this tall too. One
/// constant, so the controls cannot drift apart again. 44pt is also
/// the minimum tap target: the boxes and the Delete button all get a
/// 44pt hit area at this height, with no padding tricks needed.
private let setRowControlHeight: CGFloat = 44

struct SetRow: View {
    let number: Int
    @Binding var set: SetLog
    let template: ExerciseTemplate
    let previous: SetLog?
    var onDelete: () -> Void = {}
    /// Reports focus changes up to TodayView (field id or nil on blur)
    /// so the layout can scroll the focused field above the keyboard.
    var onFieldFocus: ((String?) -> Void)? = nil

    @EnvironmentObject private var store: WorkoutStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Number fields are fixed narrow (~64pt folded, ~80pt open) and get
    /// layout priority so they never truncate. The grey "previous" text is
    /// the only thing allowed to shrink.
    private var fieldWidth: CGFloat { horizontalSizeClass == .regular ? 80 : 64 }
    private var isPair: Bool { template.isPair }

    private var unit: WeightUnit { store.unit(for: template) }

    /// The weight field displays in the exercise's unit; edits convert back
    /// to stored lb.
    private var weightBinding: Binding<Double?> {
        Binding(
            get: { unit.displayValue(for: set.weightLb) },
            set: { set.weightLb = unit.storedValue(for: $0) }
        )
    }

    private var weightRange: ClosedRange<Double> {
        unit == .kg ? 0...225 : 0...500
    }

    private var repsBinding: Binding<Double?> {
        Binding(
            get: { Double(set.reps) },
            set: { newValue in
                if let newValue {
                    set.reps = max(1, min(30, Int(newValue)))
                }
            }
        )
    }

    private var previousText: String? {
        guard let previous else { return nil }
        if let weight = previous.weightLb, weight > 0 {
            return "Prev \(store.displayWeightLabel(weight, isPair: isPair, for: template)) × \(previous.reps)"
        }
        return "Prev × \(previous.reps)"
    }

    var body: some View {
        // Narrow page (side bar on, line at the hinge): a compact row with
        // smaller boxes, so the whole row fits instead of being cut off.
        ViewThatFits(in: .horizontal) {
            row(compact: false)
            row(compact: true)
        }
    }

    private func row(compact: Bool) -> some View {
        // Row alignment (DaRon 2026-11-10: "the alignment of the set +
        // buttons are off"): the checkbox, the "Set N" label, and the
        // "+" are all exactly 32pt tall inside ONE center-aligned
        // HStack, so all three share one vertical center line — a
        // straight edge through the row hits all three centers. The
        // text's 32pt frame is what makes it exact: a bare Text's line
        // box is shorter than the circles, so its visual center sat
        // above theirs and the row looked ragged.
        HStack(alignment: .center, spacing: compact ? 5 : 8) {
            Button {
                set.done.toggle()
                if set.done {
                    if store.settings.hapticsEnabled {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    // Warm-up sets don't start the rest timer.
                    if set.kind != .warmup {
                        store.startRest(for: template)
                    }
                }
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    // Done: the vivid green mutes to a very light tint
                    // of the accent. (DaRon 22:32.)
                    .foregroundStyle(set.done ? CompletedTint.completedGlyph : Theme.tertiaryText)
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .accessibilityLabel("Mark set \(number) done")

            // Accessibility text sizes: just the number — "Set" no longer
            // fits beside the fixed-width fields and truncated to "S…".
            // VoiceOver still reads "Set N" (accessibilityLabel below).
            Text(dynamicTypeSize.isAccessibilitySize ? "\(number)" : "Set \(number)")
                .font(.subheadline)
                // At large Dynamic Type sizes the fixed-width weight/reps
                // fields leave little room: shrink the label before it
                // truncates to "…", and keep it ahead of the Spacer.
                .lineLimit(1)
                // Never squeezed to "S…": it keeps its full width; the
                // grey Prev hint gives way instead.
                .fixedSize()
                .frame(height: 32)
                .accessibilityLabel("Set \(number)")

            // Set-type button: one bright "+" for working sets, the kind
            // letter (W / D / F) for the rest. Tap to change the kind.
            // (DaRon 21:27: make this a visible plus button as well —
            // the old trigger was a dim "·" at half opacity.)
            Menu {
                ForEach(SetKind.allCases, id: \.self) { kind in
                    Button(kind.label) { set.kind = kind }
                }
            } label: {
                // Neutral chip (Nov 12 UI pass): a blue "+" here read as
                // "add set". Working sets show a small chevron (it's a
                // picker); warm-up / drop / failure show their letter in
                // the accent so special sets stand out.
                Group {
                    if set.kind == .working {
                        Image(systemName: "chevron.down")
                            .scaledFont(size: 11, weight: .bold)
                    } else {
                        Text(set.kind.shortLabel)
                            .scaledFont(size: 14, weight: .bold)
                    }
                }
                .foregroundStyle(set.done ? CompletedTint.completedGlyph
                                 : set.kind == .working ? Theme.secondaryText : Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Theme.border.opacity(set.done ? 0.2 : 0.45), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set type: \(set.kind.label)")

            if let previousText {
                // Shown whole or not at all — a "P…" stub said nothing.
                ViewThatFits(in: .horizontal) {
                    Text(previousText)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                    Color.clear.frame(width: 0)
                }
                .frame(height: 32)
            }

            Spacer()

            HStack(spacing: 2) {
                NumberField(prompt: "–", keyboardType: .decimalPad, range: weightRange, value: weightBinding, width: compact ? 50 : fieldWidth, fieldID: "field-weight-\(template.id)-\(number)", onFocusChange: { focused in
                    onFieldFocus?(focused ? "field-weight-\(template.id)-\(number)" : nil)
                })
                    .layoutPriority(1)
                Text(unit.label)  // pairs too: "lb", not the old "s" (as in "40s")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }

            HStack(spacing: 2) {
                NumberField(prompt: "–", keyboardType: .numberPad, range: 1...30, value: repsBinding, width: compact ? 50 : fieldWidth, fieldID: "field-reps-\(template.id)-\(number)", onFocusChange: { focused in
                    onFieldFocus?(focused ? "field-reps-\(template.id)-\(number)" : nil)
                })
                    .layoutPriority(1)
                Text(compact ? "×" : "reps")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }

            // Visible delete: icon-only red trash can, no text. (DaRon
            // 2026-11-10 08:20: "Just make it a trash can no words".)
            // It used to live in .swipeActions — but the rows sit in a
            // plain VStack inside a ScrollView, not a List, so swipe
            // actions never render and no trash icon ever appeared on
            // screen. The button sits in the row itself, exactly
            // setRowControlHeight tall, so it shares the row's single
            // vertical center line with the checkbox, "Set N", "+", and
            // the weight/reps boxes. The words survive as the
            // VoiceOver label.
            // Grey, not red (Nov 12 UI pass): a red can on every row read
            // as alarming and drew the eye from the numbers. Still one
            // tap, same place.
            Button { onDelete() } label: {
                Image(systemName: "trash")
                    .scaledFont(size: 15, weight: .regular)
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: compact ? 30 : setRowControlHeight, height: setRowControlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete set")
        }
        // Done rows sit back slightly — but only a touch: the old 0.6
        // dim would bury the faint completed tint to near-invisible,
        // and the tint is what says "done" now. (DaRon 22:32.)
        .opacity(set.done ? 0.85 : 1)
    }
}

// MARK: - Tap-to-edit numeric field (decimal / number keypad)

struct NumberField: View {
    let prompt: String
    let keyboardType: UIKeyboardType
    let range: ClosedRange<Double>
    @Binding var value: Double?
    var width: CGFloat = 64
    /// Stable id for scroll-to-focused-field ("field-weight-<id>-<set>"
    /// / "field-reps-<id>-<set>"), and a focus report up to TodayView.
    /// Both default to off — a field without them just edits numbers.
    var fieldID: String? = nil
    var onFocusChange: ((Bool) -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        TextField(prompt, text: $text)
            .keyboardType(keyboardType)
            .multilineTextAlignment(.center)
            .font(.subheadline)
            .monospacedDigit()
            .frame(width: width)
            .minimumScaleFactor(0.8)
            .lineLimit(1)
            .padding(.vertical, 6)
            // The box is exactly setRowControlHeight tall — the one
            // shared height for the row's controls. The frame (not the
            // text + padding) sets the height, so the row is exactly
            // 44pt and the swipe Delete button that fills the row is
            // exactly the boxes' height: the row sits flush.
            .frame(height: setRowControlHeight)
            .background(Theme.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .focused($isFocused)
            .id(fieldID)
            .onAppear { syncFromValue() }
            .onChange(of: value) { syncFromValue() }
            .onChange(of: text) { _, newText in liveUpdate(newText) }
            .onChange(of: isFocused) { _, focused in
                onFocusChange?(focused)
                if !focused { commit() }
            }
            .onSubmit { commit() }
    }

    private func displayText(for value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        if value == value.rounded() { return String(Int(value)) }
        return roundedWeightText(value)
    }

    private func syncFromValue() {
        // Never clobber the text while the user is typing.
        if !isFocused {
            text = displayText(for: value)
        }
    }

    private func liveUpdate(_ newText: String) {
        // D4 (2026-11-10): the field accepted letters ("A2") — the
        // hardware keyboard is not restricted by .keyboardType, so
        // filter here. Weight allows digits + one decimal point, reps
        // digits only (derived from the existing keyboardType).
        let allowed = keyboardType == .decimalPad ? "0123456789." : "0123456789"
        var filtered = newText.filter { allowed.contains($0) }
        if keyboardType == .decimalPad, filtered.filter({ $0 == "." }).count > 1 {
            // Keep only the first decimal point.
            var seenDot = false
            filtered = String(filtered.filter { c in
                if c == "." { if seenDot { return false }; seenDot = true }; return true
            })
        }
        if filtered != newText { text = filtered }  // re-fires onChange once, then passes through
        let cleaned = filtered.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty {
            value = nil
            return
        }
        if let parsed = Double(cleaned), parsed > 0 {
            value = min(max(parsed, range.lowerBound), range.upperBound)
        }
    }

    private func commit() {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty {
            value = nil
        } else if let parsed = Double(cleaned), parsed > 0 {
            value = min(max(parsed, range.lowerBound), range.upperBound)
        }
        text = displayText(for: value)
    }
}

// MARK: - Add exercise sheet (library + customs, with search + dropdown filters)

/// Pick an exercise from the library. Two dropdown menus (Muscle group
/// and Equipment, native SwiftUI Menu style) narrow the list to a short
/// filtered set, so the user picks from a menu instead of scrolling one
/// long list of all 1,583 exercises. Search still works on top of the
/// filters. Rows keep the name + equipment tags, and Cancel stays.
struct AddExerciseSheet: View {
    @EnvironmentObject var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    var onAdd: (ExerciseTemplate) -> Void
    @State private var search = ""
    /// Dropdown filters — nil = all. Picking one narrows the list below.
    @State private var muscleFilter: MuscleGroup? = nil
    @State private var equipmentFilter: Equipment? = nil
    @State private var sortOption: ExerciseSort = .muscle
    @State private var favoritesOnly = false

    /// Sort order for the exercise list. "Newest" has no creation date
    /// on library exercises, so it is reverse library order
    /// (last-emitted = newest). Muscle keeps the grouped display below.
    enum ExerciseSort: String, CaseIterable {
        case muscle, name, newest

        var label: String {
            switch self {
            case .muscle: return "Muscle"
            case .name: return "Name A–Z"
            case .newest: return "Newest"
            }
        }
    }

    private var pool: [LibraryExercise] {
        var all = ExerciseLibrary.all(plus: store.customExercises)
        if favoritesOnly { all = all.filter { store.isFavoriteExercise($0.id) } }
        if let muscleFilter { all = all.filter { $0.muscle == muscleFilter } }
        if let equipmentFilter { all = all.filter { $0.equipment.contains(equipmentFilter) } }
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    /// The pool in the picked order (stable: ties keep library order).
    private var sortedPool: [LibraryExercise] {
        switch sortOption {
        case .muscle: return pool
        case .name: return pool.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .newest: return Array(pool.reversed())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Dropdown filters — always at the top, so the list below
                // is a short filtered set instead of one long scroll.
                Section {
                    HStack(spacing: 12) {
                        filterMenu(
                            title: "Muscle group",
                            allLabel: "All muscles",
                            options: MuscleGroup.allCases.map { ($0.label, $0) },
                            selection: $muscleFilter
                        )
                        filterMenu(
                            title: "Equipment",
                            allLabel: "All equipment",
                            options: Equipment.allCases.map { ($0.label, $0) },
                            selection: $equipmentFilter
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                    // Sort + favorites-only: the same single-pill row as
                    // the filters above — no card behind the pills.
                    HStack(spacing: 12) {
                        sortMenu
                        favoritesToggle
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                }

                if sortedPool.isEmpty {
                    if favoritesOnly {
                        Text("No favorite exercises yet. Tap the heart on an exercise to save it here.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("No exercises match those filters. Try a different muscle or equipment, or clear the search.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if sortOption == .muscle {
                    Section {
                        ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                            let rows = sortedPool.filter { $0.muscle == muscle }
                            if !rows.isEmpty {
                                Section(muscle.label) {
                                    ForEach(rows) { lib in
                                        exerciseRow(lib)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("\(sortedPool.count) exercise\(sortedPool.count == 1 ? "" : "s")")
                    }
                } else {
                    Section {
                        ForEach(sortedPool) { lib in
                            exerciseRow(lib)
                        }
                    } header: {
                        Text("\(sortedPool.count) exercise\(sortedPool.count == 1 ? "" : "s")")
                    }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .oledList()
            .navigationTitle("Add exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// One dropdown filter: a caption + the shared single clean pill
    /// (native Menu with a Picker inside, so the open menu shows a
    /// checkmark on the current pick). 44pt+ tap target, shows the
    /// current pick, shrinks instead of truncating. The pill is ONE
    /// capsule — the old card-in-a-card double pill is gone, and the
    /// row behind it is clear, so no halo wraps it.
    private func filterMenu<T: Hashable>(title: String, allLabel: String, options: [(String, T)], selection: Binding<T?>) -> some View {
        let currentLabel = selection.wrappedValue.flatMap { value in
            options.first { $0.1 == value }?.0
        } ?? allLabel
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            MenuPill(label: currentLabel, isActive: selection.wrappedValue != nil) {
                Picker(title, selection: selection) {
                    Text(allLabel).tag(nil as T?)
                    ForEach(options, id: \.1) { label, value in
                        Text(label).tag(value as T?)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Sort control: the same single clean pill as the filters.
    private var sortMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sort")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            MenuPill(label: sortOption.label) {
                Picker("Sort", selection: $sortOption) {
                    ForEach(ExerciseSort.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Favorites-only switch: the same single clean pill shape, with a
    /// heart — on, the list shows only favorited exercises.
    private var favoritesToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Button {
                favoritesOnly.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                        .font(.caption)
                    Text("Favorites")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(favoritesOnly ? Color.accentColor : Theme.text)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(favoritesOnly ? Color.accentColor.opacity(0.15) : Theme.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(favoritesOnly ? Color.accentColor.opacity(0.4) : Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    /// One exercise row: tap adds it (built through
    /// ProgramGenerator.template, the single source for sets/reps);
    /// the heart favorites it (persists on-device). The heart button
    /// wins over the row button, so favoriting never adds the exercise.
    private func exerciseRow(_ lib: LibraryExercise) -> some View {
        Button {
            let profile = store.profile ?? UserProfile.starter
            onAdd(ProgramGenerator.template(for: lib, profile: profile))
            dismiss()
        } label: {
            HStack {
                Text(lib.name)
                Spacer()
                Text(lib.equipment.map { $0.label }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                favoriteButton(for: lib)
            }
        }
    }

    private func favoriteButton(for lib: LibraryExercise) -> some View {
        Button {
            store.toggleFavoriteExercise(lib.id)
        } label: {
            Image(systemName: store.isFavoriteExercise(lib.id) ? "heart.fill" : "heart")
                .scaledFont(size: 20)
                .foregroundStyle(store.isFavoriteExercise(lib.id) ? Color.accentColor : Theme.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.isFavoriteExercise(lib.id) ? "Remove \(lib.name) from favorites" : "Favorite \(lib.name)")
    }
}

// MARK: - Swap sheet (Fitbod "Replace with: Best" + search)

struct SwapExerciseSheet: View {
    @EnvironmentObject var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    let current: ExerciseTemplate
    var onSwap: (ExerciseTemplate) -> Void
    @State private var search = ""

    /// Substitutes first ("Best"), then same-muscle alternatives — sorted
    /// by how well they match (same equipment, same muscle, not excluded).
    private var ranked: [(lib: LibraryExercise, reason: String)] {
        var results: [(LibraryExercise, String)] = []
        let currentLib = ExerciseLibrary.byId(current.id, plus: store.customExercises)
        let subs = currentLib?.substitutes ?? []
        for subId in subs {
            guard let lib = ExerciseLibrary.byId(subId, plus: store.customExercises),
                  store.preference(for: lib.id) != .exclude,
                  !store.isExcludedByInjury(lib.id) else { continue }
            results.append((lib, "Best match"))
        }
        let muscle = currentLib?.muscle
        for lib in ExerciseLibrary.all(plus: store.customExercises) {
            guard lib.id != current.id, !subs.contains(lib.id),
                  lib.muscle == muscle,
                  store.preference(for: lib.id) != .exclude,
                  lib.equipment.isSubset(of: store.effectiveEquipment),
                  !store.isExcludedByInjury(lib.id) else { continue }
            results.append((lib, "Same muscle"))
        }
        if !search.isEmpty {
            results = results.filter { $0.0.name.localizedCaseInsensitiveContains(search) }
        }
        return results
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Current") {
                    Text(current.name)
                        .font(.headline)
                }
                Section("Replace with") {
                    ForEach(ranked, id: \.lib.id) { item in
                        Button {
                            let profile = store.profile ?? UserProfile.starter
                            onSwap(ProgramGenerator.template(for: item.lib, profile: profile))
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.lib.name)
                                    Text(item.reason)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    if ranked.isEmpty {
                        Text("No substitutes available for this exercise with your equipment.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search replacements")
            .oledList()
            .navigationTitle("Swap exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Exercise history sheet (per-exercise past sets)

struct ExerciseHistorySheet: View {
    @EnvironmentObject var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    let template: ExerciseTemplate

    private var logs: [ExerciseLog] {
        store.sessions
            .sorted { $0.date > $1.date }
            .flatMap { session in
                session.exercises.filter { $0.exerciseId == template.id }
                    .map { (session.date, $0) }
            }
            .map { $0.1 }
    }

    var body: some View {
        NavigationStack {
            List {
                if let best = store.bestSet(for: template.id) {
                    Section("Best set") {
                        Text("\(store.displayWeightLabel(best.weightLb, isPair: template.isPair, for: template)) × \(best.reps)")
                    }
                }
                if let oneRM = store.oneRepMax(for: template.id) {
                    Section("Estimated max lift") {
                        Text(store.displayWeightLabel(oneRM, isPair: template.isPair, for: template))
                    }
                }
                Section("Past sessions") {
                    if logs.isEmpty {
                        Text("No sessions logged for this exercise yet.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(logs, id: \.name) { log in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.sets.map { set in
                                "\(store.displayWeightLabel(set.weightLb, isPair: log.isPair, for: template)) × \(set.reps)"
                            }.joined(separator: ", "))
                            .font(.subheadline)
                        }
                    }
                }
            }
            .oledList()
            .navigationTitle(template.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Plate calculator (barbell only)

struct PlateCalculatorSheet: View {
    @EnvironmentObject var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    let template: ExerciseTemplate

    private var workingWeight: Double {
        store.lastWeight(for: template) ?? template.defaultWeightLb ?? 0
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Plates per side") {
                    let result = platesPerSide(targetLb: workingWeight,
                                               barWeightLb: store.settings.barWeightLb,
                                               inventoryLb: store.settings.plateInventoryLb)
                    if workingWeight <= 0 {
                        Text("Log a weight for this exercise first.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text("Target: \(store.displayWeightLabel(workingWeight, isPair: false, for: template))")
                        Text("Bar: \(store.displayWeightLabel(store.settings.barWeightLb, isPair: false, for: template))")
                        if result.plates.isEmpty {
                            Text("Just the bar.")
                        } else {
                            Text("Per side: " + result.plates.map { store.displayWeightLabel($0, isPair: false, for: template) }.joined(separator: " + "))
                        }
                        if result.achievedLb < workingWeight - 0.5 {
                            Text("Closest loadable: \(store.displayWeightLabel(result.achievedLb, isPair: false, for: template))")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                Section("Warm-up sets") {
                    ForEach(warmUpSets(for: workingWeight, isPair: template.isPair), id: \.weightLb) { set in
                        Text("\(store.displayWeightLabel(set.weightLb, isPair: template.isPair, for: template)) × \(set.reps)")
                    }
                    if workingWeight <= 0 {
                        Text("Log a weight for this exercise first.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Section {
                    Text("Bar weight and plate inventory are set in Profile → Settings.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .oledList()
            .navigationTitle("Plates — \(template.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Session Mod sheet (Fitbod "Training Session Mods" — today only)

struct SessionModSheet: View {
    @EnvironmentObject var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    var onApply: (SessionMod) -> Void
    @State private var shorter = false
    @State private var deload = false
    @State private var focus: MuscleGroup? = nil
    @State private var useCustomEquipment = false
    @State private var selectedEquipment: Set<Equipment> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Today only — your saved program doesn't change") {
                    Toggle("Shorter session (2 sets per exercise)", isOn: $shorter)
                    Toggle("Deload — half the sets", isOn: $deload)
                    if deload {
                        Text("Recovery week: same exercises, half the volume. A deload is cheap insurance for managing fatigue — not a proven requirement. Use one when training feels heavy or progress stalls.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Picker("Focus on", selection: $focus) {
                        Text("No focus").tag(MuscleGroup?.none)
                        ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                            Text(muscle.label).tag(MuscleGroup?.some(muscle))
                        }
                    }
                }
                Section("Equipment for today") {
                    Toggle("Use different equipment today", isOn: $useCustomEquipment)
                    if useCustomEquipment {
                        ForEach(Equipment.allCases, id: \.self) { equipment in
                            Toggle(equipment.label, isOn: Binding(
                                get: { selectedEquipment.contains(equipment) },
                                set: { isOn in
                                    if isOn { selectedEquipment.insert(equipment) }
                                    else { selectedEquipment.remove(equipment) }
                                }
                            ))
                        }
                    }
                }
                Section {
                    Button("Apply for today") {
                        var mod = SessionMod()
                        mod.shorterSession = shorter
                        mod.deload = deload
                        mod.focusMuscle = focus
                        mod.equipment = useCustomEquipment ? selectedEquipment : nil
                        onApply(mod)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .oledList()
            .navigationTitle("Modify this workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                selectedEquipment = store.effectiveEquipment
            }
        }
    }
}

// MARK: - Next-workout preview sheet (rest-day screen, tap the preview)

/// The next scheduled workout in full: date, title, every exercise with
/// sets × reps and its target weight, the finisher — and a "Train this
/// workout" button that starts it today ("Train anyway"). Read-only
/// except for that button: it previews the real plan, it never edits
/// the program or the draft.
struct NextWorkoutPreviewSheet: View {
    @EnvironmentObject var store: WorkoutStore
    @Environment(\.dismiss) private var dismiss
    let plan: DayPlan
    let date: Date
    var onTrain: (DayPlan) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(plan.title) · \(date, format: .dateTime.weekday(.wide).month().day())")
                        .font(.title2)
                        .bold()
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(plan.subtitle)
                        .font(.body)
                        .foregroundStyle(Theme.text)
                    Text("About \(plan.estimatedMinutes) minutes")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exercises")
                            .font(.headline)
                        ForEach(plan.exercises) { exercise in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(exercise.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(exercise.sets) × \(exercise.repRange)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                        .lineLimit(1)
                                        .fixedSize()
                                    if let weight = exercise.defaultWeightLb {
                                        Text(store.displayWeightLabel(weight, isPair: exercise.isPair, for: exercise))
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                }
                                if let note = store.swapNote(for: exercise) {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(Theme.cardElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                        }
                    }
                    if !plan.finisher.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pump finisher")
                                .font(.headline)
                            ForEach(plan.finisher, id: \.self) { item in
                                Text("• \(item)")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Button {
                        onTrain(plan)
                        dismiss()
                    } label: {
                        Text("Train this workout")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle("Next workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Stretch detail sheet (rest-day stretches, tap a row)

/// How to do one stretch: name, muscle, equipment, and its cues. The
/// cues are the library's own text — nothing invented.
struct LibraryExerciseDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: LibraryExercise

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(exercise.name)
                        .font(.title2)
                        .bold()
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(exercise.muscle.label)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    if !exercise.equipment.isEmpty {
                        Text(exercise.equipment.map { $0.label }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let cues = exercise.cues, !cues.isEmpty {
                        Text("How to do it")
                            .font(.headline)
                        Text(cues)
                            .font(.body)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No instructions saved for this stretch yet.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Text("\(exercise.defaultSets) × \(exercise.repRange)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding()
            }
            .navigationTitle("Stretch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}


/// A small upward-pointing triangle (the calendar dropdown's pointer).
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}


/// Shifts a view into the corner-button column on the DS layout's bottom
/// page. Reads the inset where the view is (inside the page pair), not
/// from TodayView, which sits outside it.
private struct CornerColumnOffset: ViewModifier {
    @Environment(\.duoCornerInset) private var inset
    @Environment(\.duoStacked) private var stacked
    @Environment(\.duoSwapProgress) private var progress
    @Environment(\.duoWide) private var wide
    @Environment(\.duoSwapped) private var swapped
    @Environment(\.cornerColumnTop) private var columnTop
    /// Bottom of the + on screen (before the offset, so no feedback).
    @State private var plusBottom: CGFloat = 0
    func body(content: Content) -> some View {
        // DS: the same inset on either half, so the + always sits on the
        // swap/menu buttons' center line (DaRon: "buttons need to line
        // up" — on the top half it used the side-by-side rule, 13pt off).
        let trailing: CGFloat = !wide ? 16
            : stacked ? 3
            : (progress >= 0 ? 3 + 13 * progress : (swapped ? 16 : 3))
        // Short bottom half (line dragged down): the column would land on
        // the swap button, so the + stays beside the column (DaRon).
        let collides = inset > 0 && plusBottom + 12 > columnTop
        content
            .padding(.trailing, trailing)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { plusBottom = $0 }
            .offset(x: collides ? 0 : inset)
            .animation(AppAnimation.snappy, value: collides)
    }
}


/// DS layout: keeps the body pane's labels clear of the fold's fade and
/// the divider grabber. Reads the pair's values from inside it.
private struct FoldClearance: ViewModifier {
    @Environment(\.duoStacked) private var stacked
    func body(content: Content) -> some View {
        content.padding(.bottom, stacked ? FoldFade.reach + 18 : 0)
    }
}
