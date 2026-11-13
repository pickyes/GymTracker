import SwiftUI

/// First-launch gate: until onboarding completes, the intro flow shows.
/// Returning users (flag set, or adopted from before onboarding existed)
/// go straight to the 3-page app.
///
/// Navigation (DaRon, 2026-11-09): there is NO tab bar — not the standard
/// TabView (which goes vertical on the Duo outer display) and not a custom
/// bottom tab bar. Navigation is ONE collapsible floating button, bottom
/// right, like TikTok's round black search button: a round black circle
/// with a white icon, floating over the full-bleed content. Tap it to
/// expand the menu (Today, Calendar, History, Notes, Profile) upward; tap a page
/// to go there and the button collapses; tap it again (or tap outside) to
/// collapse without choosing. The button collapses when not used, so the
/// app fills the page. The four pages themselves are unchanged — only
/// the navigation chrome changed.
///
/// Bars (DaRon, 2026-11-09):
/// - HORIZONTAL, permanently: the iPhone Duo vertical bar is disabled
///   (`.toolbarVerticalBehavior(.disabled)`, iOS 27.1+), so the system
///   status bar stays horizontal across the top and the app fills the
///   whole page — no vertical strip eating space on the side.
/// - ALWAYS VISIBLE, TikTok-style: the status bar is never hidden. The
///   navigation bar background extends under the status bar, which sits
///   on top of it, always visible and horizontal, like TikTok where the
///   video fills the whole page and the bar overlays it. That is how the
///   app fills the page: bar on top, content below it, bar always
///   visible. The page content itself respects the top safe area, so the
///   page title sits tight under the status bar — do NOT ignore the top
///   safe area here (it pushes the title down and leaves a big gap).
struct ContentView: View {
    @EnvironmentObject var store: WorkoutStore
    @State private var selectedPage: Page = .today
    @State private var navExpanded = false
    @State private var showCalendar = false
    /// System setting: Reduce Motion → fades instead of pops and grows.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Open Duo: mirror the two pages (swap button, bottom-left). Kept
    /// across launches.
    /// Swap + swap-button choices, saved to their own file on every tap
    /// so nothing (closing, updates, power-off) can undo them.
    @ObservedObject private var duo = DuoSettings.shared
    private var swapSides: Bool { duo.swapSides }
    /// The page area ignoring the keyboard. Pose decisions (two pages
    /// or one, Today's layout) use this: with the keyboard up the safe
    /// area shrinks, which flipped the open Duo to the folded layout
    /// mid-typing (and closed the note being written).
    @State private var steadySize: CGSize = .zero
    @State private var swapInFlight = false
    private var showSwapButton: Bool { duo.showSwapButton }
    /// The day chosen on the Calendar page (also shown on the open
    /// Duo's other page).
    @State private var calendarDay: Date = Calendar.current.startOfDay(for: Date())

    enum Page: String, CaseIterable {
        case today, history, notes, profile
        var title: String {
            switch self {
            case .today: return "Today"
            case .history: return "Calendar"
            case .profile: return "Profile"
            case .notes: return "Notes"
            }
        }
        var systemImage: String {
            switch self {
            case .today: return "dumbbell"
            case .history: return "calendar"
            case .profile: return "person.fill"
            case .notes: return "note.text"
            }
        }
    }

    var body: some View {
        Group {
            if store.hasCompletedOnboarding {
                GeometryReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        pageStack
                            .environment(\.fabBottomOffset,
                                         fabBottomPadding(safeAreaBottom: proxy.safeAreaInsets.bottom,
                                                          size: proxy.size))
                            // Menu backdrop (DaRon 22:36: "blur background
                            // and make black and white when clicked") —
                            // while the menu is open the page behind goes
                            // blurred and grayscale; the pills and the X
                            // sit on top of it, sharp and in full color.
                            // Animates back to sharp / full color when
                            // the menu collapses. (Blur + desaturation
                            // can't come from an overlay on top — they
                            // have to be applied to the page content
                            // itself; the dim below is the tap catcher.)
                            .blur(radius: navExpanded ? 10 : 0)
                            .saturation(navExpanded ? 0 : 1)
                            .animation(AppAnimation.snappy, value: navExpanded)
                        // Content scrolling up under the status bar blurs
                        // and greys out, ombre-style (Nov 12).
                        // Smaller strip on Today and Profile (DaRon): a hard
                        // blur, then black and white on top of it.
                        let stripHeight: CGFloat = selectedPage == .today || selectedPage == .profile ? 10 : 30
                        // Black and white first, straight onto the page (a
                        // blend can't see through the blur — under it, it
                        // drew a flat grey band); the blur on top then
                        // blurs the greyed content.
                        // The icon zone only where the status bar really is:
                        // across the top, visible. Hidden or turned to run
                        // down the side → no grey spot (DaRon, Nov 12).
                        StatusBarFade(height: stripHeight)
                        // The top bar: an ombré from the page color at the
                        // very top edge to transparent (DaRon, Nov 12) —
                        // replaces the blur bar, which showed as a band.
                        StatusBarOmbre(height: 22)  // a soft fade along the top edge only
                        // Dim + tap-outside-to-collapse while expanded.
                        if navExpanded {
                            Color.black.opacity(0.25)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(AppAnimation.snappy) {
                                        navExpanded = false
                                    }
                                }
                        }
                        // Keeps the end-of-rest sound + haptic running
                        // while the visible timer is the inline one.
                        if restActive && (restShownInline || navExpanded) {
                            RestTimerCard()
                                .frame(width: 0, height: 0)
                                .hidden()
                                .accessibilityHidden(true)
                        }
                        bottomStack
                            // Bottom-right corner, lined up with the
                            // cards' "+" column (see fabTrailingPadding /
                            // fabBottomPadding). The rest-timer panel
                            // shares the same right edge, stacked above
                            // the button.
                            .padding(.trailing, fabTrailingPadding(screenWidth: proxy.size.width))
                            // When the keyboard is up the safe area IS the
                            // keyboard, so the padding grows to keep the
                            // button just above it.
                            .padding(.bottom, fabBottomPadding(safeAreaBottom: proxy.safeAreaInsets.bottom, size: proxy.size))
                            // Fold (Debug Pass 2): the bottom safe-area
                            // inset jumps discretely when the pose flips,
                            // which used to snap the button to its new
                            // bottom edge with no animation at all. Animate
                            // the button's travel on the shared fold spring
                            // so it glides with the rest of the morph.
                            // No glide on fold/unfold (Nov 12): the button is
                            // simply in its corner on the new screen.
                        // Calendar dropdown (DaRon 22:28: "calendar needs
                        // to drop down from the menu not slide up") — a
                        // panel anchored above the menu button that drops
                        // down from the menu instead of a sheet sliding
                        // up. Tap outside to close; Done inside the
                        // calendar closes it too.
                        if showCalendar {
                            Color.black.opacity(0.35)
                                .ignoresSafeArea()
                                .transition(.opacity)
                                .onTapGesture {
                                    withAnimation(AppAnimation.snappy) {
                                        showCalendar = false
                                    }
                                }
                            calendarDropdown(maxHeight: proxy.size.height * 0.68)
                                .padding(.horizontal, 16)
                                .padding(.bottom, fabBottomPadding(safeAreaBottom: proxy.safeAreaInsets.bottom, size: proxy.size) + 56 + 12)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    // Pin the stack to the window. Without this, a page
                    // whose content grows taller than the screen (large
                    // Dynamic Type sizes) grew the ZStack with it, and the
                    // bottom-trailing menu button rode off the bottom edge.
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .background {
                        GeometryReader { steady in
                            Color.clear
                                .onAppear { steadySize = steady.size }
                                .onChange(of: steady.size) { _, size in steadySize = size }
                        }
                        .ignoresSafeArea(.keyboard)
                    }
                }
                // On Today the keyboard doesn't shrink the app: the workout
                // column scrolls clear of it itself, and shrinking lifted the
                // body pane off the top (and flipped the pose before).
                // (keyboard handled inside TodayView)
            } else {
                OnboardingFlowView()
            }
        }
        .disableVerticalBar()
        // Hinge read from launch, 0° to 180°, the whole time.
        .hingeReader()
        // Full-bleed: the navigation bar background extends under the
        // status bar, which sits on top of it, always visible and
        // horizontal (TikTok-style). The page content itself respects the
        // top safe area so the page title sits tight under the status bar
        // instead of being pushed down — do NOT ignore the top safe area
        // here (it adds a big gap above the title).
        .statusBarHidden(false)
        // Pending onboarding decision (Debug Pass 2): finishing a retake
        // while DaRon's preset is active stashes the result in
        // `pendingOnboarding` instead of silently replacing the preset.
        // This alert lives here, NOT in OnboardingFlowView — that view
        // unmounts when the retake finishes, so a dialog there would
        // never be seen. Dismissing without choosing keeps the current
        // program (the binding's setter resolves with keep: true), the
        // safe default — the preset stays active.
        .alert("Your new program is ready", isPresented: Binding(
            get: { store.pendingOnboarding != nil },
            set: { if !$0 { store.resolvePendingOnboarding(keepCurrentProgram: true) } }
        )) {
            Button("Keep my current program", role: .cancel) {
                store.resolvePendingOnboarding(keepCurrentProgram: true)
            }
            Button("Switch to the new program") {
                store.resolvePendingOnboarding(keepCurrentProgram: false)
            }
        } message: {
            Text("Setup finished with a new program. Keep DaRon's 5-Day Split, or switch to the new program? You can switch back from Programs any time.")
        }
    }

    /// All three pages stay in the hierarchy so each page's navigation
    /// state survives switching pages; only the selected one is visible
    /// and hit-testable. Hidden pages are also pruned from the
    /// VoiceOver tree (opacity 0 + allowsHitTesting false does NOT
    /// prune them) — only the visible page is exposed.
    private var pageStack: some View {
        GeometryReader { geo in
            // The keyboard-free size, unless it's not measured yet or came
            // back degenerate (a zero height blanked the whole Today page).
            let steadyOK = steadySize.width > 200 && steadySize.height > 200
            let size = steadyOK ? steadySize : geo.size
            let wide = Self.isWide(size)
            ZStack {
                TodayView()
                    .environment(\.pageContainerSize, size)
                    // Today makes room for the keyboard itself (its column
                    // scrolls clear of it); the page as a whole doesn't get
                    // squeezed or lifted, so the body pane stays in place.
                    .ignoresSafeArea(.keyboard)
                    .opacity(selectedPage == .today ? 1 : 0)
                    .allowsHitTesting(selectedPage == .today)
                    .accessibilityHidden(selectedPage != .today)
                unfoldPage(.history, wide: wide) { HistoryView(selectedDay: $calendarDay) } companion: { historyCompanion }
                // Notes and Profile split themselves when wide, like
                // Apple's Notes and Settings: list on one page, the
                // open note / section on the other.
                fullPage(.profile) { ProfileView() }
                fullPage(.notes) { NotesView() }
            }
            .environment(\.duoWide, wide)
            .environment(\.duoSwapped, wide && swapSides)
        }
    }

    /// The status bar's height when it runs across the top of the screen
    /// and is showing; 0 when it's hidden or turned down the side. (Takes
    /// the page size only so it re-reads whenever the screen rotates.)
    static func horizontalStatusBarHeight(_ pageSize: CGSize) -> CGFloat {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let manager = scene.statusBarManager,
              !manager.isStatusBarHidden else { return 0 }
        let frame = manager.statusBarFrame
        guard frame.height > 0, frame.width > frame.height, frame.minY <= 1 else { return 0 }
        return frame.height
    }

    /// Two pages side by side: the open inner display only (669×951 /
    /// 951×669), never the outer screen held sideways (678×466).
    static func isWide(_ size: CGSize) -> Bool {
        size.width >= TodayView.outerDisplayWidth + 150 && size.height >= 520
    }

    /// Mirrors the two pages on the open Duo.
    private var swapSidesButton: some View {
        Button {
            swapPages()
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .scaledFont(size: 20, weight: .semibold, maxScale: 1.3)
                .foregroundStyle(.primary)
                // Same 56pt Liquid Glass circle as the menu button below
                // it, so the two line up as one column (DaRon).
                .frame(width: 56, height: 56)
                .liquidGlass(Circle())
        }
        .buttonStyle(.plain)
        // Never holds keyboard focus: with a hardware keyboard a focused
        // button takes the space bar, so typing a note flipped the pages.
        .focusable(false)
        .accessibilityLabel("Swap sides")
        .accessibilityHint(swapSides ? "Puts the front-screen page back on the right" : "Puts the front-screen page on the left")
    }

    /// Trades the two pages' sides like swapping two apps on iPhone Duo:
    /// both lift into rounded cards, slide past each other, then settle
    /// back to full screen. Reduce Motion: a plain cross-fade.
    private func swapPages() {
        guard !swapInFlight else { return }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) { duo.swapSides.toggle() }
            return
        }
        swapInFlight = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // One motion (DaRon): a single curve slides the pages across and
        // the lift rides it. Eases in and lands cleanly at a fixed time
        // (a spring's long tail kept the cards creeping into place).
        withDuoSwapAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 0.55)) { duo.swapSides.toggle() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
            try? await Task.sleep(for: .milliseconds(250))
            swapInFlight = false
        }
    }

    @ViewBuilder
    private func fullPage<Main: View>(_ page: Page, @ViewBuilder main: () -> Main) -> some View {
        main()
            .opacity(selectedPage == page ? 1 : 0)
            .allowsHitTesting(selectedPage == page)
            .accessibilityHidden(selectedPage != page)
    }

    /// Same unfold as Today (Nov 12): the page keeps the folded screen's
    /// width (and compact size class, so it lays out exactly as folded)
    /// on the right; opening the Duo reveals a companion page on the left
    /// that is already there, waiting. Folded, the companion is absent.
    /// Swapped, the two trade places.
    @ViewBuilder
    private func unfoldPage<Main: View, Side: View>(
        _ page: Page, wide: Bool,
        @ViewBuilder main: () -> Main,
        @ViewBuilder companion: () -> Side
    ) -> some View {
        let swapped = wide && swapSides
        let companionPage = companion()
        let mainPage = main()
        DuoPagePair(wide: wide, swapped: swapped) {
            companionPage
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .hingeReveal()
        } main: {
            mainPage
                .modifier(CompactWhen(wide))
        }
        .opacity(selectedPage == page ? 1 : 0)
        .allowsHitTesting(selectedPage == page)
        .accessibilityHidden(selectedPage != page)
    }

    /// Calendar's companion (open Duo): the chosen day, with the
    /// training heatmap pinned under it (Nov 12 layout DaRon picked).
    private var historyCompanion: some View {
        historyCompanionDay
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TrainingHeatmap(selectedDay: $calendarDay)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .background(Theme.background)
            }
    }

    /// The chosen day's workout in full, or what was planned that day.
    @ViewBuilder private var historyCompanionDay: some View {
        let cal = Calendar.current
        if let session = store.sessions.first(where: { cal.isDate($0.date, inSameDayAs: calendarDay) }) {
            NavigationStack { SessionDetailView(session: session) }
                .id(session.id)
                // On the left page (no clock there) it starts at the very
                // top, level with the Calendar title (Nov 12).
                .ignoresSafeArea(edges: swapSides ? [] : .top)
        } else if let plan = store.programDay(for: calendarDay) {
            let isPast = calendarDay < cal.startOfDay(for: Date())
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(calendarDay, format: .dateTime.weekday(.wide).month().day())
                        .font(.headline)
                        .foregroundStyle(Theme.secondaryText)
                    Text(plan.title).font(.largeTitle.bold())
                    Text(isPast ? "Missed" : "Planned")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isPast ? Theme.vividOrange : Color.accentColor)
                    ForEach(plan.exercises) { template in
                        HStack {
                            Text(template.name).font(.body.weight(.semibold))
                            Spacer()
                            Text("\(template.sets) × \(template.repRange)")
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(14)
                        .themeCard(cornerRadius: 14)
                    }
                }
                .padding(24)
                .padding(.top, 20)
            }
        } else {
            ContentUnavailableView("Rest day", systemImage: "moon.zzz",
                                   description: Text("Pick a day on the calendar to see that workout here."))
        }
    }

    /// Bottom padding for the floating nav button: bottom-right corner,
    /// `fabBottomInset` above the safe-area bottom (Nov 12: DaRon chose
    /// the corner over the old 74%-height placement, which sat on top of
    /// the workout — note field, set rows, rest labels — on the Duo).
    /// When the keyboard is up, the safe area IS the keyboard
    /// (safeAreaBottom > 100): the padding becomes the keyboard height
    /// + 12, so the button sits 12pt above the keyboard.
    private func fabBottomPadding(safeAreaBottom: CGFloat, size: CGSize) -> CGFloat {
        if safeAreaBottom > 100 { return safeAreaBottom + 12 }
        // 16pt above the safe-area bottom in every pose. (An earlier 48pt
        // landscape value compensated for the root ZStack overflowing the
        // window — the same overflow that later pushed the button off
        // screen at large text sizes. With the ZStack pinned to the
        // window, 16 fits everywhere; measured on screen Nov 12.)
        return 16
    }

    /// Trailing padding for the floating nav button: its center sits 60pt
    /// from the right edge in every pose, the same column as the exercise
    /// cards' "+" buttons (DaRon 21:23 line-up). The button is 56pt, so
    /// the padding is 60 - 28 = 32.
    private func fabTrailingPadding(screenWidth: CGFloat) -> CGFloat {
        // Open Duo: the button column sits directly under the status
        // bar's Wi-Fi icon, ~47pt from the right edge in both open
        // orientations (measured Nov 12) → 47 − 28 (half the button).
        Self.isWide(steadySize) ? 19 : 32
    }

    /// Everything anchored to the bottom-right corner, top to bottom:
    /// the expanded page pills, then the rest-timer panel (when a rest
    /// is running), then the round menu button itself. The timer panel
    /// sits directly above the button, so when a rest starts it slides
    /// up from behind the button — and slides back down behind it when
    /// the rest ends or Stop is tapped. (DaRon 21:28: "make the timer
    /// a button that slides up from the shadows of the menu button.")
    /// The panel is the same RestTimerCard the workout layouts used to
    /// show inline — same countdown, same controls, same "Drink water",
    /// just floating now, so it can never resize the body or push the
    /// workout list around.
    /// Spacing (DaRon 22:35: "X and profile need more space"): 16pt
    /// between every row so the gaps are even and roomy, plus 12pt
    /// under the pills — the enlarged X (1.25x) grows 7pt past its
    /// layout box toward the lowest pill, so without the extra padding
    /// the blue Profile pill nearly touches the blue X.
    private var bottomStack: some View {
        VStack(alignment: .trailing, spacing: 16) {
            if navExpanded {
                navPills
                    .padding(.bottom, 12)
            }
            // Tent pose shows its own big countdown on the page, so the
            // floating card would only cover the weight × reps.
            // Rest timer (Nov 12, DaRon): an upright pill at the top of the
            // button column (above swap), growing out of the corner. Tap
            // it for the full controls. Tent pose has its own tile.
            if restActive && !isTentPose && !navExpanded && !store.calendarDropdownOpen {
                RestTimerCard(pill: true)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity))
            }
            // Swap sides (open Duo only): above the menu button (and
            // above the rest pill while one runs). Hidden while the menu
            // is open.
            if showSwapButton && Self.isWide(steadySize) && !navExpanded && !store.calendarDropdownOpen {
                swapSidesButton
                    // Always fully there and tappable while the Duo is
                    // open, at any hinge angle (it used to fade and blur
                    // with the hinge and looked disabled mid-close). It
                    // still fades in when it first appears.
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.6)).animation(.easeOut(duration: 0.6)),
                        removal: .opacity.animation(.easeIn(duration: 0.15))))
            }
            // Notes: the blue compose button sits beside the menu button
            // (DaRon, Nov 12).
            HStack(spacing: 16) {
                if selectedPage == .notes && !navExpanded {
                    Button { store.composeNoteRequest += 1 } label: {
                        Image(systemName: "square.and.pencil")
                            .scaledFont(size: 22, weight: .semibold, maxScale: 1.3)
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(effectiveAccent, in: Circle())
                            .shadow(color: effectiveAccent.opacity(0.5), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New note")
                    .transition(.scale.combined(with: .opacity))
                }
                fabButton
            }
            .animation(AppAnimation.snappy, value: selectedPage)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: restActive)
    }

    /// Today on the folded screen held sideways / in tent pose (the same
    /// rule TodayView uses for its tent layout).
    private var isTentPose: Bool {
        selectedPage == .today && steadySize.width > steadySize.height * 1.2 && steadySize.height < 520
    }

    /// Tent pose shows the rest timer in its own tile (no pill there).
    private var restShownInline: Bool { isTentPose }

    /// A rest is running (counting down) or paused.
    private var restActive: Bool {
        store.restEndsAt != nil || store.restPausedRemaining != nil
    }

    /// The expanded menu, top to bottom: Today, Calendar, History,
    /// Notes, Profile. (DaRon 22:11: Today, History, Notes, Profile —
    /// in that order; DaRon 22:20: Calendar sits right under Today.)
    /// Calendar is an ACTION, not a page: it presents the same
    /// CalendarView the long-press opens, as a dropdown from the menu
    /// (DaRon 22:28), and it never takes the
    /// active-page highlight — only the real pages (Today / History /
    /// Notes / Profile) light up when you are on them (DaRon 22:15).
    private var navPills: some View {
        ForEach(Page.allCases, id: \.self) { page in
            // History and Calendar are one page now (Nov 12), so the
            // old Calendar action pill is gone.
            pagePill(page)
        }
    }

    /// One page pill: dim black, or lit in the effective accent color
    /// when it is the page you are on.
    private func pagePill(_ page: Page) -> some View {
        Button {
            withAnimation(AppAnimation.snappy) {
                selectedPage = page
                navExpanded = false
            }
        } label: {
            pillLabel(systemImage: page.systemImage, title: page.title, isActive: page == selectedPage)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// The Calendar action pill: same look as a dim page pill, never
    /// highlighted (it is not a page). Tapping it closes the menu and
    /// drops the calendar down from the menu.
    private var calendarPill: some View {
        Button {
            withAnimation(AppAnimation.snappy) {
                navExpanded = false
                showCalendar = true
            }
        } label: {
            pillLabel(systemImage: "calendar", title: "Calendar", isActive: false)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// The calendar dropdown panel (DaRon 22:28: "calendar needs to
    /// drop down from the menu not slide up"): the same CalendarView
    /// the long-press opens, in a card anchored above the floating
    /// menu button. It drops down from the menu (moves in from the top
    /// + fades) instead of sliding up as a sheet, and never covers the
    /// button itself — its bottom edge sits 12pt above the button, the
    /// same gap the menu pills and timer panel use. Capped at
    /// `maxHeight` so it never runs under the status bar; the calendar
    /// scrolls internally. Closes via Done, tap-outside, or the menu
    /// button. A rest keeps counting underneath and the timer panel
    /// reappears when the dropdown closes.
    private func calendarDropdown(maxHeight: CGFloat) -> some View {
        CalendarView(onDone: {
            withAnimation(AppAnimation.snappy) { showCalendar = false }
        })
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
        .shadow(radius: 16)
    }

    /// The shared pill look: icon + title, white on dim black, or
    /// white on the effective accent when active (lit).
    private func pillLabel(systemImage: String, title: String, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // 44pt minimum tap target (VoiceOver / touch audit, P2-3):
        // subheadline text + 24pt vertical padding measured ~39–41pt.
        // minHeight floors the whole pill at 44 without changing its
        // look when it already measures taller.
        .frame(minHeight: 44)
        .background(isActive ? effectiveAccent : Color.black.opacity(0.85))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(isActive ? effectiveAccent : Theme.border, lineWidth: 1))
        .shadow(color: isActive ? effectiveAccent.opacity(0.5) : .black.opacity(0.3), radius: isActive ? 8 : 4)
    }

    /// The round menu button itself (TikTok search-button pattern).
    /// (DaRon 22:11): when the menu is open the button ENLARGES and
    /// HIGHLIGHTS in the app's effective accent color — the same rule
    /// the Live Activity resolves through (free: Theme.accent vivid
    /// blue; Pro: the accent picked in Settings). It is read from
    /// `effectiveAccent`, never hardcoded, so when accent colors
    /// become interchangeable at the paid tier the button follows the
    /// new choice with no rework. When the menu closes it shrinks back
    /// to the plain black circle.
    private var fabButton: some View {
        Button {
            withAnimation(AppAnimation.snappy) {
                // Today's calendar open: the button is its Done (✓).
                if store.calendarDropdownOpen {
                    store.calendarDropdownOpen = false
                } else if showCalendar {
                    showCalendar = false
                } else {
                    navExpanded.toggle()
                }
            }
        } label: {
            let calendarDone = store.calendarDropdownOpen
            let open = navExpanded || showCalendar || calendarDone
            let icon = Image(systemName: calendarDone ? "checkmark" : open ? "xmark" : "list.bullet")
                .contentTransition(.symbolEffect(.replace))
                .font(.title3.weight(.semibold))
                .frame(width: 56, height: 56)
            Group {
                if open {
                    // Accent when open, as before.
                    icon.foregroundStyle(.white)
                        .background(effectiveAccent, in: Circle())
                        .controlBorder(Circle(), tint: effectiveAccent)
                        .shadow(color: effectiveAccent.opacity(0.55), radius: 14)
                } else {
                    // Closed: Liquid Glass, following the system setting.
                    icon.foregroundStyle(.primary)
                        .liquidGlass(Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(navExpanded || showCalendar ? 1.25 : 1.0)
        .animation(AppAnimation.snappy, value: navExpanded)
        .animation(AppAnimation.snappy, value: showCalendar)
        .accessibilityLabel(store.calendarDropdownOpen ? "Done with calendar" : showCalendar ? "Close calendar" : navExpanded ? "Close navigation" : "Open navigation")
    }

    /// The app's effective accent color — the same rule the Live
    /// Activity resolves through (Models.effectiveAccentHex): free
    /// users get Theme.accent, Pro users get the accent they picked
    /// in Settings. One shared source, no hardcoded color.
    private var effectiveAccent: Color {
        store.isPro ? store.settings.accentColor.color : Theme.accent
    }
}

// MARK: - Page title (tight under the status bar)

/// A page title that sits tight under the horizontal status bar, top-left,
/// with only a small margin above it. Used on the root pages (Today,
/// History, Profile) instead of the system large title — the large title's
/// navigation bar is what left the big gap above the title. Pushed detail
/// views keep their own nav bar (back button), so this is root pages only.
/// The title carries no padding of its own; each layout gives it the same
/// 16pt leading as its page's content, so the title lines up exactly with
/// the content below it (never flush to the edge, never clipped).
struct PageTitle: View {
    let text: String
    var body: some View {
        // No padding of its own — the layout places it with the same
        // leading as the page's content, directly under the status bar.
        Text(text)
            .font(.largeTitle)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Disable the iPhone Duo vertical bar (horizontal bars, permanently)

/// Opts out of the iPhone Duo vertical bar (iOS 27.1+). With the vertical
/// bar disabled, the system status bar returns to horizontal across the
/// top and the right-side strip disappears, so the app fills the whole
/// page. On iOS before 27.1 this is a no-op (bars are horizontal there
/// anyway). DaRon explicitly wants horizontal bars permanently, folded
/// and open — this is the API for it (Apple Tech Talks 111462/111466,
/// UIKit `preferredVerticalBarBehavior = .disabled`).
struct DisableVerticalBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.toolbarVerticalBehavior(.disabled)
        } else {
            content
        }
    }
}

extension View {
    func disableVerticalBar() -> some View {
        modifier(DisableVerticalBar())
    }
}


/// Forces the compact size class only when `on`, so a page kept at the
/// folded width on the open Duo lays out exactly as it does folded.
private struct CompactWhen: ViewModifier {
    let on: Bool
    init(_ on: Bool) { self.on = on }
    func body(content: Content) -> some View {
        if on { content.environment(\.horizontalSizeClass, .compact) } else { content }
    }
}
