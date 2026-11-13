import SwiftUI
import Network

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
    #if DEBUG
    /// The -sampleHistory launch argument loads once, not on every appear.
    private static var sampleArgLoaded = false
    #endif
    @ObservedObject private var hinge = HingeState.shared
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
    @ObservedObject private var identity = ProfileIdentity.shared
    @Namespace private var railNS
    private var swapSides: Bool { duo.swapSides }
    /// The page area ignoring the keyboard. Pose decisions (two pages
    /// or one, Today's layout) use this: with the keyboard up the safe
    /// area shrinks, which flipped the open Duo to the folded layout
    /// mid-typing (and closed the note being written).
    @State private var steadySize: CGSize = .zero
    @State private var swapInFlight = false
    /// The software keyboard is on screen.
    @State private var keyboardShown = false
    /// The software keyboard's height, from its own notification.
    @State private var keyboardHeight: CGFloat = 0
    /// The on-screen keyboard is really up (not a hardware keyboard's bar).
    private var softKeyboardUp: Bool { keyboardShown && keyboardHeight > 120 }
    /// Top of the swap/menu column on screen, so Today's + never sits on it.
    @State private var cornerColumnTop: CGFloat = .infinity
    /// Where the system puts the vertical status bar (nil: nowhere).
    @State private var verticalBarEdge: HorizontalEdge?
    /// UIInterfaceOrientation raw value: which end of the side bar the
    /// folded screen's camera hole is at.
    @State private var interfaceOrientation = 0
    /// Folded and sideways: the camera hole sits at one end of the side
    /// bar. Never put a button there (DaRon).
    // Upright (portrait) and turned left: camera at the top of the bar;
    // upside down and turned right: at the bottom (measured on the Duo).
    private var cameraAtTop: Bool {
        // Seen on the Duo: at the top in both sideways turns and upright.
        !Self.isWide(steadySize) && interfaceOrientation != UIInterfaceOrientation.portraitUpsideDown.rawValue
    }
    private var cameraAtBottom: Bool {
        !Self.isWide(steadySize) && interfaceOrientation == UIInterfaceOrientation.portraitUpsideDown.rawValue
    }
    /// Settings → Status bar on the side, on a screen that has one: the
    /// buttons move into a rail along that edge (DaRon, like Reddit).
    /// Where the status bar runs down the side, on that edge. Open and
    /// upright (DS), where iOS keeps it on top, the bar still shows on the
    /// right (DaRon picked this).
    private var rail: HorizontalEdge? {
        // The side bar is the Duo's (DaRon): a slab iPhone never gets it,
        // in any orientation.
        guard duo.sideStatusBar, hinge.hasHinge else { return nil }
        if let verticalBarEdge { return verticalBarEdge }
        let dsMode = Self.isWide(steadySize) && steadySize.height > steadySize.width
        return dsMode ? .trailing : nil
    }
    /// The Duo with the side status bar on: the pages live in a real tab
    /// view, so iOS draws its own side bar (tab bar, Back, toolbar items)
    /// wherever it presents bars vertically.
    private var useTabs: Bool { duo.sideStatusBar && hinge.hasHinge }
    /// iOS is drawing the side bar itself right now (folded, and open
    /// sideways). Open and upright it keeps bars horizontal, so the app's
    /// own bar shows there instead.
    private var nativeBar: Bool { useTabs && verticalBarEdge != nil }
    private var railWidth: CGFloat { rail == nil ? 0 : Self.railWidth }
    /// The side bar is showing where iOS's status bar is horizontal.
    private var drawsOwnStatusBar: Bool { rail != nil && verticalBarEdge == nil }
    static let railWidth: CGFloat = 84
    /// The app's own side bar (open, upright): button width and how far in
    /// from the screen edge, both measured from iOS's own side bar.
    static let appBarButtonWidth: CGFloat = 47
    static let appBarInset: CGFloat = 24
    /// Side status bar on: the buttons' own column beside the strip.
    static let buttonColumn: CGFloat = 76
    /// Side bar: where Today's + sits, below the status icons.
    static let railButtonTop: CGFloat = 132

    /// Side bar: the rest pill fills the room between the page list and
    /// the buttons below it (DaRon: big, never overlapping).
    /// Side bar: how tall the page list is, labeled or icons only.
    private func railListHeight(labeled: Bool) -> CGFloat {
        let back: CGFloat = 52 + (labeled ? 6 : 4)
        return labeled ? back + 4 * 58 + 3 * 6 : back + 58 + 3 * 44 + 3 * 4
    }

    /// The buttons stacked at the bottom of the side bar, gaps included.
    private var railButtonsHeight: CGFloat {
        // The tallest page's buttons (+ or compose), so the list sits in
        // the same place on every page.
        var b: CGFloat = 56 + 16
        if showSwapButton && Self.isWide(steadySize) { b += 56 + 16 }
        return b
    }

    /// Where the side bar's list starts.
    /// Where the side bar's list starts: below the status icons, moved up
    /// (never past the camera) when the screen is too short for the list
    /// and the buttons, so nothing overlaps.
    private var railTop: CGFloat {
        // The same spot folded and open (DaRon: the front display's icons
        // sat lower, so they jumped when the phone opened). The camera only
        // pushes the status icons down; the page icons start below them
        // either way.
        let wanted = Self.railButtonTop
        let fits = steadySize.height - railBottom - railButtonsHeight - 12 - railListHeight(labeled: false)
        return max(cameraAtTop ? 84 : 20, min(wanted, fits))
    }

    private var railBottom: CGFloat { cameraAtBottom ? Self.cameraClearance : 16 }

    /// Room between the list (plus a gap) and the buttons, for the pill.
    private func railPillRoom(labeled: Bool) -> CGFloat {
        steadySize.height - railTop - railListHeight(labeled: labeled) - 16
            - railButtonsHeight - railBottom
    }

    /// Back button showing in the side bar: the rest pill shrinks to a
    /// round button like the others (DaRon).
    private var railPillAsButton: Bool { sideBar && store.canGoBack.contains(selectedPage.rawValue) }

    /// Labels unless a running rest pill needs the room.
    private var railLabeled: Bool {
        // Folded and open sideways decide together, from the tighter of the
        // two (the open screen is a touch shorter and has the swap button),
        // so every icon sits at the same height when the phone opens. Only
        // the tall upright open screen has room for labels.
        let upright = Self.isWide(steadySize) && steadySize.height > steadySize.width
        let height = upright ? steadySize.height : min(steadySize.height, 669)
        let buttons = upright ? railButtonsHeight : 56 + 16 + (showSwapButton ? 56 + 16 : 0)
        let free = height - railTop - railListHeight(labeled: true) - buttons - railBottom
        // Same on every page (icons only whenever the tallest case needs
        // it), so switching pages never re-lays out the list.
        return free - 72 >= (restActive && !navExpanded ? 56 : 0)
    }

    /// The pill fills exactly the room left, never overlapping (DaRon).
    private var sideBarPillHeight: CGFloat {
        railPillAsButton ? 56 : max(56, min(240, railPillRoom(labeled: railLabeled)))
    }

    /// The grey side bar is showing (Settings → Side bar strip).
    private var sideBar: Bool { rail != nil }

    /// The app draws the side bar itself (open and upright, where iOS keeps
    /// its bars across the top). It copies iOS's own side bar (DaRon): the
    /// page's buttons grouped in a glass capsule under the clock, the rest
    /// pill below them, and the page icons in a glass capsule at the bottom.
    private var appBar: Bool { rail != nil && !nativeBar }

    @ViewBuilder private var appSideBar: some View {
        VStack(spacing: 12) {
            railBackButton
            appBarActions
            if restActive && !isTentPose && !navExpanded {
                // Same width as iOS's own bar buttons (47pt).
                RestTimerCard(pill: true, pillHeight: 176, pillWidth: 47)
                    .transition(.opacity)
            }
            Spacer(minLength: 12)
            VStack(spacing: 4) {
                ForEach(Page.allCases, id: \.self) { appBarNavItem($0) }
            }
            .padding(.vertical, 4)
            .background {
                Color.clear.liquidGlass(Capsule())
            }
        }
        .animation(AppAnimation.page, value: restActive)
        .animation(AppAnimation.snappy, value: selectedPage)
    }

    /// The current page's buttons, one glass capsule (iOS's toolbar group).
    @ViewBuilder private var appBarActions: some View {
        let today = selectedPage == .today && !softKeyboardUp
        let notes = selectedPage == .notes && !softKeyboardUp
        let swap = showSwapButton && Self.isWide(steadySize)
        if today || notes || swap {
            VStack(spacing: 0) {
                if today {
                    if store.todayEditing {
                        Button { store.todayEditing = false } label: { appBarIcon("checkmark") }
                            .accessibilityLabel("Done editing")
                    } else {
                        Menu {
                            Button("Edit", systemImage: "pencil") { store.todayEditing = true }
                            Button("Add exercise", systemImage: "plus") { store.todayAddExercise = true }
                            Button("Modify today", systemImage: "slider.horizontal.3") { store.todaySessionMod = true }
                        } label: { appBarIcon("plus") }
                            .accessibilityLabel("Workout actions")
                    }
                }
                if notes {
                    Button { store.composeNoteRequest += 1 } label: { appBarIcon("square.and.pencil") }
                        .accessibilityLabel("New note")
                }
                if swap {
                    Button { store.swapSidesRequest += 1 } label: { appBarIcon("arrow.left.arrow.right") }
                        .accessibilityLabel("Swap sides")
                }
            }
            .buttonStyle(PressSqueeze())
            .padding(.vertical, 4)
            .liquidGlass(Capsule())
        }
    }

    /// A page in the bottom capsule, like iOS's tab bar down the side:
    /// icon only; the current one in the accent on a dark circle.
    private func appBarNavItem(_ page: Page) -> some View {
        let active = page == selectedPage
        return Button {
            dismissKeyboard()
            withAnimation(AppAnimation.snappy) { selectedPage = page }
        } label: {
            Image(systemName: page == .profile ? "person.fill" : page.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(active ? effectiveAccent : Theme.text)
                .frame(width: 47, height: 47)
                .background {
                    if active {
                        Circle()
                            .fill(Color.black.opacity(0.55))
                            .matchedGeometryEffect(id: "appBarHighlight", in: railNS)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(PressSqueeze())
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func appBarIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title3.weight(.semibold))
            .foregroundStyle(effectiveAccent)
            .frame(width: 47, height: 44)
            .contentShape(Rectangle())
    }

    /// One page in the side bar: icon over a short label, lit when current.
    /// Back, in the side bar, when the page has somewhere to go back to
    /// (DaRon: not top left).
    @ViewBuilder private var railBackButton: some View {
        if store.canGoBack.contains(selectedPage.rawValue) {
            Button { store.requestBack(selectedPage.rawValue) } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 52, height: 52)
                    .liquidGlass(Circle())
            }
            .buttonStyle(PressSqueeze())
            // A clear gap under the pages' capsule.
            .padding(.top, 6)
            .accessibilityLabel("Back")
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// Bottom of the side bar kept clear of the camera hole.
    static let cameraClearance: CGFloat = 92


    private func railNavItem(_ page: Page, labeled: Bool, width: CGFloat = 70) -> some View {
        let active = page == selectedPage
        return Button {
            dismissKeyboard()
            withAnimation(AppAnimation.snappy) { selectedPage = page }
        } label: {
            VStack(spacing: 4) {
                // Profile shows your photo and name when set (Settings).
                Group {
                    if page == .profile && identity.photo != nil {
                        ProfileAvatar(size: 26)
                    } else {
                        Image(systemName: page.systemImage)
                            .font(.title3.weight(.semibold))
                    }
                }
                // The current page's icon grows a little (DaRon).
                .scaleEffect(active ? 1.22 : 1)
                .animation(AppAnimation.press, value: active)
                // Icons-only bar: the selected page still shows its name.
                if labeled || active {
                    Text(page == .profile && !identity.name.trimmingCharacters(in: .whitespaces).isEmpty
                         ? identity.name.trimmingCharacters(in: .whitespaces) : page.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            // Selected: lit white on the accent highlight (DaRon).
            .foregroundStyle(active ? Color.white : Theme.secondaryText)
            .frame(width: width, height: labeled || active ? 58 : 44)
            .background {
                // One highlight that slides to the page you pick.
                if active {
                    // Liquid Glass, tinted with the accent (DaRon).
                    RailGlassHighlight(tint: duo.sideTint ? effectiveAccent : nil)
                        .matchedGeometryEffect(id: "railHighlight", in: railNS)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressSqueeze())
        // The bar is a fixed-width strip, like a tab bar: its icons stop
        // growing at xx-Large (bigger text made them overlap), and a long
        // press shows the large-content preview instead.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityShowsLargeContentViewer {
            Label(page.title, systemImage: page.systemImage)
        }
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
    /// The Calendar companion page's width (narrow when upright).
    @State private var companionSize: CGSize = .zero
    private var showSwapButton: Bool { duo.showSwapButton }
    /// The day chosen on the Calendar page (also shown on the open
    /// Duo's other page).
    @State private var calendarDay: Date = Calendar.current.startOfDay(for: Date())

    enum Page: String, CaseIterable, Hashable {
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
            case .notes: return "pencil"
            }
        }
    }

    var body: some View {
        Group {
            if store.hasCompletedOnboarding {
                GeometryReader { proxy in
                    ZStack(alignment: rail == .leading ? .bottomLeading : .bottomTrailing) {
                        // The rail: the system's vertical bar strip (its safe
                        // area), topped up to the full width if it gives less.
                        let systemRail = rail == .leading ? proxy.safeAreaInsets.leading
                            : rail == .trailing ? proxy.safeAreaInsets.trailing : 0
                        // Strip off (Settings): the pages run under the side
                        // status bar; only the button column stays clear.
                        // The app's own grey bar: only where iOS isn't drawing
                        // the side bar itself.
                        let strip = rail != nil && !nativeBar
                        // Only as wide as the bar's buttons reach (iOS's layout: 47pt
                        // wide, 24pt in), so each page sits its usual 16pt
                        // from them (DaRon: the gap was twice that).
                        let extraRail = strip ? max(0, Self.appBarInset + Self.appBarButtonWidth - systemRail) : 0
                        let railTotal = strip ? systemRail + extraRail : 0
                        // The status icons sit centered in the system's own
                        // strip at the edge; everything in the bar lines up
                        // on that same center (DaRon: with the WiFi icon).
                        // The camera and status icons sit a touch in from the
                        // strip's middle (toward the page): line up with them.
                        let iconCenter = strip ? Self.appBarInset + Self.appBarButtonWidth / 2 : systemRail > 0 ? systemRail / 2 + 5 : railTotal / 2
                        // Highlight fits inside the bar on both sides with an
                        // even 6pt margin (it ran into the bar's edge).
                        let railItemWidth = max(44, min(70, 2 * min(iconCenter, railTotal - iconCenter) - 12))
                        // The pages stop at the rail. They're drawn edge to edge
                        // (ignoring safe areas), and a view that touches the
                        // safe area's edge spreads into it — so they stop 1pt
                        // short of the rail (the rail covers that point).
                        pageStack
                            // Plus a clear column for the buttons beside the
                            // strip, so nothing runs under them (DaRon).
                            // Strip on: stop short of the strip. Strip off: just
                            // run under the status bar on that edge (forcing a
                            // wider frame slid the page off the far edge).
                            .frame(width: strip ? proxy.size.width - extraRail - 1 : nil)
                            .frame(maxWidth: .infinity, alignment: rail == .leading ? .trailing : .leading)
                            .ignoresSafeArea(.container, edges: [])
                            // Nothing drawn past the page area's sides (shadows,
                            // glows); top and bottom still run to the edges.
                            // (Not over iOS's own side bar, which sits outside
                            // the page area.)
                            .mask(Rectangle().padding(.vertical, -600).padding(.horizontal, nativeBar ? -200 : 0))
                            .environment(\.railEdge, rail)
                            // Where the hinge is across the pages.
                            .environment(\.duoHingeX,
                                         (proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing) / 2
                                         - (rail == .leading && strip ? railTotal + 1 : 0))
                            .environment(\.cornerButtonsInRail, strip)
                            .environment(\.systemSideBar, nativeBar)
                            .environment(\.appDrawsKeyboardDone, true)
                            .environment(\.cornerColumnTop, cornerColumnTop)
                            .environment(\.pageTitleTop,
                                         rail != nil || hinge.hasHinge ? 30 : proxy.safeAreaInsets.top + 2)
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
                        // Both step aside while the pages swap: drawn over
                        // the cards, they painted the gap above them dark,
                        // so the top was the one edge with no gap (DaRon).
                        Group {
                            StatusBarFade(height: stripHeight)
                            // The top bar: an ombré from the page color at the
                            // very top edge to transparent (DaRon, Nov 12) —
                            // replaces the blur bar, which showed as a band.
                            StatusBarOmbre(height: 22)  // a soft fade along the top edge only
                            // The same at the bottom edge (DaRon).
                            StatusBarFade(height: stripHeight, bottom: true)
                            StatusBarOmbre(height: 22, bottom: true)
                        }
                        .opacity(swapInFlight ? 0 : 1)
                        // On or off, never half faded: a blend under a
                        // partial opacity draws a grey band (red team).
                        .transaction { $0.animation = nil }
                        // Above the edge fades too: nothing from the pages
                        // tints the side bar (DaRon).
                        // Over the pages (their backgrounds bleed to the edge).
                        if let rail, strip {
                            GeometryReader { full in
                                // On the page's own black, like iOS's side bar
                                // (DaRon: the grey strip wasn't the side bar he
                                // wanted).
                                Rectangle()
                                    .fill(Theme.background)
                                    .frame(width: railTotal + 1, height: full.size.height)
                                    .position(x: rail == .leading ? (railTotal + 1) / 2 : full.size.width - (railTotal + 1) / 2,
                                              y: full.size.height / 2)
                            }
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            // Today's blue + lives in the side bar, under the
                            // status icons (DaRon: "an actual side bar").
                            if drawsOwnStatusBar {
                                RailStatusBar()
                                    .frame(width: iconCenter * 2)
                                    .padding(.top, 22)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                                           alignment: rail == .leading ? .topLeading : .topTrailing)
                                    .ignoresSafeArea(.container, edges: rail == .leading ? [.leading, .top] : [.trailing, .top])
                                    .allowsHitTesting(false)
                            }
                            // The pages, listed like Claude's side bar (DaRon):
                            // tap to go, the current one lit up.
                            if !store.calendarDropdownOpen {
                                appSideBar
                                    .frame(width: iconCenter * 2)
                                    .padding(.top, railTop)
                                    .padding(.bottom, railBottom)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                                           alignment: rail == .leading ? .leading : .trailing)
                                    .ignoresSafeArea(.container, edges: rail == .leading ? [.leading, .top, .bottom] : [.trailing, .top, .bottom])
                                    .transition(.opacity)
                            }
                        }
                        // iOS's side bar: the rest pill sits in the bar's free
                        // gap, between the buttons at the top and the tabs.
                        if nativeBar && restActive && !isTentPose && !store.calendarDropdownOpen {
                            // Same width and center line as the system's own
                            // buttons in the bar (measured: 47pt wide, 24pt in).
                            RestTimerCard(pill: true, pillHeight: 176, pillWidth: 47)
                                .padding(.top, 236)
                                .padding(verticalBarEdge == .leading ? .leading : .trailing, 24)
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: verticalBarEdge == .leading ? .topLeading : .topTrailing)
                                .ignoresSafeArea()
                                .transition(.opacity)
                        }
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
                        if restActive && (restShownInline || navExpanded || store.calendarDropdownOpen) {
                            RestTimerCard()
                                .frame(width: 0, height: 0)
                                .hidden()
                                .accessibilityHidden(true)
                        }
                        bottomStack
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
                                // The open menu's pills don't count.
                                if !navExpanded { cornerColumnTop = y }
                            }
                            // Bottom-right corner, lined up with the
                            // cards' "+" column (see fabTrailingPadding /
                            // fabBottomPadding). The rest-timer panel
                            // shares the same right edge, stacked above
                            // the button.
                            // Side status bar: the column sits on the page just
                            // beside the strip, which stays clear (DaRon).
                            // Measured from the screen's own edge.
                            .padding(rail == .leading ? .leading : .trailing,
                                     strip ? max(2, iconCenter - 28) : fabTrailingPadding(screenWidth: proxy.size.width))
                            // When the keyboard is up the safe area IS the
                            // keyboard, so the padding grows to keep the
                            // button just above it.
                            // Side bar: the camera hole sits at the bottom of
                            // the bar on the folded screen; keep the buttons
                            // well above it (DaRon: never under the camera).
                            // (Folded only: the open screen has no camera there,
                            // and the buttons sit at the bottom as usual.)
                            .padding(.bottom, strip && cameraAtBottom
                                     ? max(Self.cameraClearance - proxy.safeAreaInsets.bottom, 12)
                                     : fabBottomPadding(safeAreaBottom: proxy.safeAreaInsets.bottom, size: proxy.size))
                            .frame(maxWidth: .infinity, maxHeight: .infinity,
                                   alignment: rail == .leading ? .bottomLeading : .bottomTrailing)
                            .ignoresSafeArea(.container, edges: rail == nil || nativeBar ? [] : (rail == .leading ? .leading : .trailing))
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
                        // Done for the keyboard, floating a clear gap above
                        // it (the system's sat right on the keys, DaRon).
                        // Only for the on-screen keyboard (a hardware keyboard
                        // reports a short bar and needs no Done).
                        if keyboardShown && keyboardHeight > 120 && !navExpanded {
                            Button { dismissKeyboard() } label: {
                                Text("Done")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 22)
                                    .frame(height: 44)
                                    .liquidGlass(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Done typing")
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            // Left of the button column, so it never sits on
                            // the menu button.
                            .padding(.trailing, sideBar ? (rail == .trailing ? railTotal + 12 : 16) : 16 + 56 + 16)
                            .padding(.bottom, keyboardHeight + 14)
                            .ignoresSafeArea(.all)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
                        }
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
                        VerticalBarEdgeReader(edge: $verticalBarEdge, orientation: $interfaceOrientation)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
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
                // body pane and the corner buttons with it (red team).
                .ignoresSafeArea(selectedPage == .today ? .keyboard : [], edges: .bottom)
            } else {
                OnboardingFlowView()
            }
        }
        .disableVerticalBar()
        #if DEBUG
        // Testing: launch with -sampleHistory veteran|regular|newLifter.
        .onAppear {
            guard !Self.sampleArgLoaded else { return }
            Self.sampleArgLoaded = true
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-sampleHistory"), i + 1 < args.count,
               let p = SampleProfile(rawValue: args[i + 1]) { store.loadSampleHistory(p) }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
            withAnimation(AppAnimation.snappy) { keyboardShown = true; keyboardHeight = frame.height }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(AppAnimation.snappy) { keyboardShown = false; keyboardHeight = 0 }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            // Floating or undocked keyboards change frame without a hide.
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .zero
            let screenH = UIScreen.main.bounds.height
            if frame.minY >= screenH - 1 || frame.height < 120 {
                keyboardHeight = 0
            } else if keyboardShown {
                keyboardHeight = frame.height   // docked again
            }
        }
        // Hinge read from launch, 0° to 180°, the whole time.
        .hingeReader()
        // Full-bleed: the navigation bar background extends under the
        // status bar, which sits on top of it, always visible and
        // horizontal (TikTok-style). The page content itself respects the
        // top safe area so the page title sits tight under the status bar
        // instead of being pushed down — do NOT ignore the top safe area
        // here (it adds a big gap above the title).
        // Open and upright with the side bar: iOS keeps its status bar
        // across the top, so it's hidden and the app draws the time,
        // Wi-Fi and battery down the side bar instead (DaRon).
        .statusBarHidden(drawsOwnStatusBar)
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
            // A width change (unfold, rotate) is never the keyboard: take
            // the live size at once instead of a frame late (red team).
            // The keyboard only ever changes the height: keep the page's own
            // width and the keyboard-free height (the old width test never
            // matched beside the side bar, so typing flipped the layout).
            let size = steadyOK ? CGSize(width: geo.size.width, height: steadySize.height) : geo.size
            // Open or folded comes from the whole screen: the side bar's
            // width narrowed the pages under the "open" cut-off in DS mode.
            let wide = Self.isWide(steadyOK ? steadySize : size)
            Group {
                if useTabs {
                    // A real tab view: iOS presents its tab bar down the
                    // side of the Duo with the system's own buttons.
                    TabView(selection: $selectedPage) {

                TodayView()
                    .environment(\.pageContainerSize, size)
                    .environment(\.screenIsOpen, wide)
                    // Today makes room for the keyboard itself (its column
                    // scrolls clear of it); the page as a whole doesn't get
                    // squeezed or lifted, so the body pane stays in place.
                    .ignoresSafeArea(.keyboard)
                    .modifier(StillWhenHidden(hidden: selectedPage != .today))
                    .opacity(selectedPage == .today ? 1 : 0)
                    .allowsHitTesting(selectedPage == .today)
                    .accessibilityHidden(selectedPage != .today)
                            .tabPage(.today, barShown: nativeBar, edge: verticalBarEdge)
                unfoldPage(.history, wide: wide) { HistoryView(selectedDay: $calendarDay) } companion: { historyCompanion }
                            .tabPage(.history, barShown: nativeBar, edge: verticalBarEdge)
                        fullPage(.notes) { NotesView() }
                            .tabPage(.notes, barShown: nativeBar, edge: verticalBarEdge)
                        fullPage(.profile) { ProfileView() }
                            .tabPage(.profile, barShown: nativeBar, edge: verticalBarEdge)
                    }
                } else {
                    ZStack {
                TodayView()
                    .environment(\.pageContainerSize, size)
                    .environment(\.screenIsOpen, wide)
                    // Today makes room for the keyboard itself (its column
                    // scrolls clear of it); the page as a whole doesn't get
                    // squeezed or lifted, so the body pane stays in place.
                    .ignoresSafeArea(.keyboard)
                    .modifier(StillWhenHidden(hidden: selectedPage != .today))
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
                }
            }
            .environment(\.duoWide, wide)
            .environment(\.duoSwapped, wide && swapSides)
            .onChange(of: store.swapSidesRequest) { _, _ in swapPages() }
            .onChange(of: selectedPage) { _, _ in dismissKeyboard() }
            // A note's linked workout: open the Calendar on that day.
            .onChange(of: store.calendarJumpRequest) { _, day in
                guard let day else { return }
                calendarDay = Calendar.current.startOfDay(for: day)
                withAnimation(AppAnimation.snappy) { selectedPage = .history }
                store.calendarJumpRequest = nil
            }
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
        .buttonStyle(PressSqueeze())
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
            withDuoSwapAnimation(AppAnimation.quick) { duo.swapSides.toggle() }
            return
        }
        swapInFlight = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // One motion (DaRon): a single curve slides the pages across and
        // the lift rides it. Eases in and lands cleanly at a fixed time
        // (a spring's long tail kept the cards creeping into place).
        withDuoSwapAnimation(.timingCurve(0.4, 0, 0.3, 1, duration: 0.75)) { duo.swapSides.toggle() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
            try? await Task.sleep(for: .milliseconds(250))
            swapInFlight = false
        }
    }

    @ViewBuilder
    private func fullPage<Main: View>(_ page: Page, @ViewBuilder main: () -> Main) -> some View {
        main()
            .modifier(StillWhenHidden(hidden: selectedPage != page))
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
        _ page: Page, wide: Bool, stacksWhenTall: Bool = true, halves: Bool = false,
        @ViewBuilder main: () -> Main,
        @ViewBuilder companion: () -> Side
    ) -> some View {
        let swapped = wide && swapSides
        let companionPage = companion()
        let mainPage = main()
        DuoPagePair(wide: wide, swapped: swapped,
                    mainWidth: halves ? nil : TodayView.outerDisplayWidth,
                    stacksWhenTall: stacksWhenTall,
                    // The divider never squeezes the page below the width
                    // it's laid out for (Calendar bunched up, DaRon).
                    mainMinWidth: 380) {
            companionPage
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .hingeReveal()
        } main: {
            mainPage
                .modifier(CompactWhen(wide))
        }
        .modifier(StillWhenHidden(hidden: selectedPage != page))
        .opacity(selectedPage == page ? 1 : 0)
        .allowsHitTesting(selectedPage == page)
        .accessibilityHidden(selectedPage != page)
    }

    /// Calendar's companion (open Duo): the chosen day, with the
    /// training heatmap pinned under it (Nov 12 layout DaRon picked).
    private var historyCompanion: some View {
        // DS layout (the Duo open and upright): the Calendar's half is wide
        // and short, so the day's workout and the heatmap sit side by side
        // (DaRon). Landscape keeps the heatmap under the workout.
        let clockSide = swapSides
        // DS mode (open and upright): always side by side, however the
        // line is dragged (DaRon); the half's shape alone flipped it.
        let dsHalf = Self.isWide(steadySize) && steadySize.height > steadySize.width
            || companionSize.width > companionSize.height * 1.2
        return Group {
            if dsHalf {
                HStack(alignment: .top, spacing: 0) {
                    historyCompanionDay
                        .frame(width: companionSize.width * 0.55)
                        .frame(maxHeight: .infinity, alignment: .top)
                    // Fills the rest of the half, below the clock row and
                    // clear of the corner buttons when they're on this half.
                    TrainingHeatmap(selectedDay: $calendarDay, fill: true)
                        .padding(.top, 104)
                        .padding(.bottom, 20)
                        .padding(.leading, 8)
                        .padding(.trailing, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                historyCompanionWithHeatmapBelow(clockSide: clockSide)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { companionSize = $0 }
    }

    private func historyCompanionWithHeatmapBelow(clockSide: Bool) -> some View {
        historyCompanionDay
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TrainingHeatmap(selectedDay: $calendarDay)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    // Clear of the swap and menu buttons on their side.
                    .padding(.trailing, clockSide && rail == nil ? 56 : 0)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                    .background(Theme.background)
                    // The workout above fades out into the heatmap, the
                    // same eased fade as the top of the screen (DaRon: the
                    // cards were cut off flat against it).
                    .background(alignment: .top) {
                        LinearGradient(stops: [
                            .init(color: Theme.background.opacity(0), location: 0),
                            .init(color: Theme.background.opacity(0.1), location: 0.2),
                            .init(color: Theme.background.opacity(0.26), location: 0.4),
                            .init(color: Theme.background.opacity(0.52), location: 0.6),
                            .init(color: Theme.background.opacity(0.8), location: 0.8),
                            .init(color: Theme.background, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                        .frame(height: 64)
                        .offset(y: -64)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
            }
    }

    /// The chosen day's workout in full, or what was planned that day.
    @ViewBuilder private var historyCompanionDay: some View {
        let cal = Calendar.current
        if let session = store.sessions.first(where: { cal.isDate($0.date, inSameDayAs: calendarDay) }) {
            NavigationStack {
                SessionDetailView(session: session)
                    // No bar background or hairline: the share/trash
                    // buttons float like the rest of the page.
                    .toolbarBackground(.hidden, for: .navigationBar)
                    // Scrolled sets fade softly under the title (the system's
                    // soft edge) instead of the hard-edged frosted band.
                    .softTopEdge()
            }
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
                        .themeCard()
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
        VStack(alignment: rail == .leading ? .leading : .trailing, spacing: 16) {
            if navExpanded {
                navPills
                    .padding(.bottom, 12)
            }
            // Tent pose shows its own big countdown on the page, so the
            // floating card would only cover the weight × reps.
            // Rest timer (Nov 12, DaRon): an upright pill at the top of the
            // button column (above swap), growing out of the corner. Tap
            // it for the full controls. Tent pose has its own tile.
            if restActive && !nativeBar && !appBar && !isTentPose && !navExpanded && !store.calendarDropdownOpen {
                RestTimerCard(pill: true, pillHeight: sideBar ? sideBarPillHeight : 200)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity))
            }
            // Notes: the blue compose button joins the button column, on
            // the same center line as swap and menu (DaRon: "the 3
            // buttons" need to line up).
            // Hidden while typing: you're already writing one, and with
            // the keyboard up a third button pushed the column into the
            // clock (landscape).
            if selectedPage == .notes && !nativeBar && !appBar && !navExpanded && !store.calendarDropdownOpen && !softKeyboardUp {
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
            // Swap sides (open Duo only): above the menu button (and
            // above the rest pill while one runs). Hidden while the menu
            // is open.
            // Today's + joins the rail too, above swap (DaRon).
            // (With the grey strip on, it sits in the strip instead.)
            // Hidden only behind a real on-screen keyboard (a stale flag
            // from a hardware keyboard hid it on the phone).
            if rail != nil && !nativeBar && !appBar && selectedPage == .today && !navExpanded && !store.calendarDropdownOpen && !softKeyboardUp {
                railTodayActions
                    .transition(.scale.combined(with: .opacity))
            }
            if showSwapButton && !nativeBar && !appBar && Self.isWide(steadySize) && !navExpanded && !store.calendarDropdownOpen {
                swapSidesButton
                    // Always fully there and tappable while the Duo is
                    // open, at any hinge angle (it used to fade and blur
                    // with the hinge and looked disabled mid-close). It
                    // still fades in when it first appears.
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.6)).animation(AppAnimation.page),
                        removal: .opacity.animation(AppAnimation.quick)))
            }
            // Side bar: the pages are listed in the bar, so no menu button.
            if !sideBar { fabButton }
        }
        .animation(AppAnimation.page, value: restActive)
        .animation(AppAnimation.snappy, value: selectedPage)
    }

    /// Today on the folded screen held sideways / in tent pose (the same
    /// rule TodayView uses for its tent layout).
    private var isTentPose: Bool {
        selectedPage == .today && steadySize.width > steadySize.height * 1.2 && steadySize.height < 520
    }

    /// Today's + (Edit / Add exercise / Modify today, ✓ while editing),
    /// in the side rail. Same actions as the + in Today's title row.
    @ViewBuilder private var railTodayActions: some View {
        Group {
            if store.todayEditing {
                Button { store.todayEditing = false } label: { railActionIcon("checkmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Done editing")
            } else {
                Menu {
                    Button("Edit") { store.todayEditing = true }
                    Button("Add exercise") { store.todayAddExercise = true }
                    Button("Modify today") { store.todaySessionMod = true }
                } label: { railActionIcon("plus") }
                    .buttonStyle(PressSqueeze())
                    .accessibilityLabel("Workout actions")
            }
        }
        .animation(AppAnimation.snappy, value: store.todayEditing)
    }

    private func railActionIcon(_ name: String) -> some View {
        Image(systemName: name)
            .scaledFont(size: 26, weight: .bold)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .accentGlass(Circle(), tint: effectiveAccent)
            .shadow(color: effectiveAccent.opacity(0.5), radius: 10, x: 0, y: 4)
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
            dismissKeyboard()
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
            // One view in both states (red team): the symbol morphs
            // (list ↔ ✕) and the accent fades in over the glass. Two
            // separate views cross-faded with both glyphs showing.
            Image(systemName: calendarDone ? "checkmark" : open ? "xmark" : "list.bullet")
                .contentTransition(.symbolEffect(.replace))
                .font(.title3.weight(.semibold))
                .foregroundStyle(open ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                .frame(width: 56, height: 56)
                .background {
                    Circle().fill(effectiveAccent).opacity(open ? 1 : 0)
                }
                // Closed: Liquid Glass, following the system setting.
                .liquidGlass(Circle())
                .shadow(color: effectiveAccent.opacity(open ? 0.55 : 0), radius: 14)
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
    /// Settings → Status bar on the side turns the system's vertical bar
    /// back on (DaRon, like Reddit on the Duo).
    @ObservedObject private var duo = DuoSettings.shared
    /// Only on a phone that folds: a slab iPhone keeps its status bar on top.
    @ObservedObject private var hinge = HingeState.shared
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.toolbarVerticalBehavior(duo.sideStatusBar && hinge.hasHinge ? .automatic : .disabled)
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


/// Hidden pages take every change at once: a swap used to run the slide
/// on all the pages, visible or not, and dropped frames (red team).
private struct StillWhenHidden: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        content
            .transaction { if hidden { $0.animation = nil } }
            .environment(\.pageVisible, !hidden)
    }
}

/// Forces the compact size class only when `on`, so a page kept at the
/// folded width on the open Duo lays out exactly as it does folded.
private struct CompactWhen: ViewModifier {
    let on: Bool
    init(_ on: Bool) { self.on = on }
    func body(content: Content) -> some View {
        // One branch: an if/else rebuilt the whole page (scroll, open
        // day, open tool) every time the Duo opened or closed (red team).
        content.transformEnvironment(\.horizontalSizeClass) { if on { $0 = .compact } }
    }
}


/// Reports the edge where the system puts the vertical status bar
/// (UITraitCollection.verticalBarEdge, iOS 27.1), or nil where there is none.
struct VerticalBarEdgeReader: UIViewRepresentable {
    @Binding var edge: HorizontalEdge?
    @Binding var orientation: Int

    func makeUIView(context: Context) -> EdgeView {
        let view = EdgeView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: EdgeView, context: Context) {
        view.onChange = { new in if edge != new { edge = new } }
        view.onOrientation = { o in if orientation != o { orientation = o } }
    }

    final class EdgeView: UIView {
        var onChange: ((HorizontalEdge?) -> Void)?
        var onOrientation: ((Int) -> Void)?
        private var lastOrientation = -1
        private var last: HorizontalEdge?? = .none

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
            // A 180° turn keeps the same size and traits, so nothing above
            // fires; the camera end would stay wrong (red team).
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.report() }
                }
            }
        }
        private var observer: NSObjectProtocol?
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        override func traitCollectionDidChange(_ previous: UITraitCollection?) {
            super.traitCollectionDidChange(previous); report()
        }

        private func report() {
            if let o = window?.windowScene?.effectiveGeometry.interfaceOrientation {
                let raw = o.rawValue
                if raw != lastOrientation {
                    lastOrientation = raw
                    DispatchQueue.main.async { [weak self] in self?.onOrientation?(raw) }
                }
            }
            var value: HorizontalEdge?
            if #available(iOS 27.1, *) {
                switch traitCollection.verticalBarEdge {
                case .leading: value = .leading
                case .trailing: value = .trailing
                default: value = nil
                }
            }
            if case .some(let old) = last, old == value { return }
            last = .some(value)
            let send = value
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(send)
            }
        }
    }
}


/// The side bar's current-page highlight: the same accent and glow as
/// the + button (DaRon: identical), with Liquid Glass on top.
private struct RailGlassHighlight: View {
    var tint: Color?
    var body: some View {
        // Rounded to nest inside the pages' glass capsule.
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let fill = tint ?? Theme.text.opacity(0.18)
        if #available(iOS 26.0, *) {
            Color.clear
                .accentGlass(shape, tint: tint ?? Theme.text.opacity(0.18))
                .shadow(color: (tint ?? .clear).opacity(0.5), radius: 10, x: 0, y: 4)
        } else {
            shape.fill(fill)
                .shadow(color: (tint ?? .clear).opacity(0.5), radius: 10, x: 0, y: 4)
        }
    }
}


/// The time, Wi-Fi and battery, stacked down the side bar, for the pose
/// where iOS only offers a horizontal status bar.
struct RailStatusBar: View {
    @StateObject private var net = NetworkWatch()
    @State private var battery: Float = UIDevice.current.batteryLevel
    @State private var charging = false

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.everyMinute) { ctx in
                Text(ctx.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
            }
            Image(systemName: net.wifi ? "wifi" : (net.connected ? "antenna.radiowaves.left.and.right" : "wifi.slash"))
                .font(.system(size: 15, weight: .semibold))
            if battery >= 0 {
                VStack(spacing: 2) {
                    Image(systemName: charging ? "battery.100.bolt" : batterySymbol)
                        .font(.system(size: 17))
                    Text("\(Int((battery * 100).rounded()))")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }
        }
        .foregroundStyle(Theme.text)
        .accessibilityElement(children: .combine)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in refresh() }
    }

    private var batterySymbol: String {
        switch battery {
        case ..<0.13: return "battery.0"
        case ..<0.38: return "battery.25"
        case ..<0.63: return "battery.50"
        case ..<0.88: return "battery.75"
        default: return "battery.100"
        }
    }

    private func refresh() {
        battery = UIDevice.current.batteryLevel
        let st = UIDevice.current.batteryState
        charging = st == .charging || st == .full
    }
}

/// Connected / on Wi-Fi, from the system's network path.
final class NetworkWatch: ObservableObject {
    @Published var connected = true
    @Published var wifi = true
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.connected = path.status == .satisfied
                self?.wifi = path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: DispatchQueue(label: "status.net"))
    }
    deinit { monitor.cancel() }
}


extension View {
    /// One page of the Duo's tab view: its tab bar entry, and the tab bar
    /// hidden where the app draws its own bar instead.
    func tabPage(_ page: ContentView.Page, barShown: Bool, edge: HorizontalEdge?) -> some View {
        self
            // No inset of our own: iOS only runs a page's toolbar down the
            // side when the page reaches that edge, and it insets the
            // content for its bar itself.
            .toolbar(barShown ? .automatic : .hidden, for: .tabBar)
            .tabItem {
                Label(page.title, systemImage: page.systemImage)
                    // Notes keeps the outlined pencil (the tab bar fills
                    // symbols by default; DaRon's reference is the outline).
                    .environment(\.symbolVariants, page == .notes ? .none : .fill)
            }
            .tag(page)
    }
}
