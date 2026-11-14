import SwiftUI

@main
struct GymTrackerApp: App {
    @StateObject private var store = WorkoutStore()
    @StateObject private var subscription = SubscriptionState()
    @StateObject private var mcpServer = MCPServer()
    @StateObject private var calendarSync = CalendarSyncManager()
    @Environment(\.scenePhase) private var scenePhase

    /// Opaque navigation bars, app-wide (D10, 2026-11-10): with the
    /// default transparent bar, scrolled content slid visibly under
    /// the toolbar icons and the status-bar time. One opaque
    /// appearance, in the app's exact background colour, so the bar
    /// reads as a continuation of the page, not a stripe.
    init() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.background)
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    /// Cold-start loading screen. True only on a fresh process (the app
    /// tapped from the home screen while NOT in the app switcher) — the
    /// @State lives for the process lifetime, so resuming from the app
    /// switcher (same process) never shows it again.
    @State private var isLoading = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    // Where iOS runs its side bar, in the same layout pass.
                    .modifier(SystemBarEdgeBridge())
                    .environmentObject(store)
                    .environmentObject(subscription)
                    .environmentObject(mcpServer)
                    .environmentObject(calendarSync)
                    // Theme + accent (Pro: Dark/Light + accent colors; free uses
                    // the system appearance and the default blue accent).
                    .preferredColorScheme(colorScheme)
                    .tint(accentColor)
                    .onAppear {
                        mcpServer.attach(store: store)
                        store.isPro = subscription.isPro
                    }
                    .onChange(of: subscription.isPro) { _, isPro in
                        // Pro status gates the accent picker, which the
                        // rest-timer Live Activity follows.
                        store.isPro = isPro
                    }
                if isLoading {
                    LoadingView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                // Cold-start loading screen: ~1.9s for the logo assembly,
                // then fade into the app (intro for new users, Today for
                // returning users). Only runs on a fresh process.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
                    withAnimation(.easeOut(duration: 0.35)) { isLoading = false }
                    // The cold-start greeting starts once the loading
                    // screen has faded and Today is visible: "Hi DaRon"
                    // for 5 seconds, then it morphs into "Today".
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        store.showColdStartGreeting = true
                    }
                }
            }
                .onChange(of: scenePhase) { _, phase in
                    // The phone MCP server runs only while foregrounded and
                    // enabled. Backgrounding stops it (up to ~5 min grace).
                    switch phase {
                    case .active:
                        if mcpServer.isEnabled {
                            mcpServer.start()
                        }
                        // A Live Activity intent may have mutated the
                        // draft from the lock screen (set checked / next
                        // exercise) while the app was backgrounded — pull
                        // it in so Today shows the real state.
                        store.reconcileFromDefaults()
                        // Apple Calendar: re-sync when the app comes back
                        // (catches day rollover and plan edits made while
                        // backgrounded). No-op unless the integration is on.
                        Task { await calendarSync.syncIfEnabled(store: store) }
                    case .background, .inactive:
                        mcpServer.stop()
                    @unknown default:
                        break
                    }
                }
                // Apple Calendar: when the plan changes (new program,
                // regenerated program), push the new planned days to
                // the calendar so it never goes stale. No-op unless
                // the integration is on.
                .onChange(of: store.activeProgram) { _, _ in
                    Task { await calendarSync.syncIfEnabled(store: store) }
                }
                .onChange(of: store.generatedProgram) { _, _ in
                    Task { await calendarSync.syncIfEnabled(store: store) }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    private var colorScheme: ColorScheme? {
        switch store.settings.colorScheme {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var accentColor: Color {
        // Free users get the vivid blue accent; Pro picks an accent.
        // The name-to-color mapping lives on AccentColorName.color —
        // the one shared source the Live Activity resolves through too.
        guard subscription.isPro else { return Theme.accent }
        return store.settings.accentColor.color
    }

    /// Deep links: gymtracker://today, gymtracker://workout?day=legs,
    /// (The old preset/daron unlock link was removed — see below.)
    /// Opens the app to the requested screen. Structured results go back
    /// through the MCP server, not the URL scheme.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "gymtracker" else { return }
        // Preset claim (DaRon's device only): restores his 5-day split,
        // marks the device unlocked, and clears a stale draft for today.
        // The `gymtracker` scheme is already registered in Info.plist
        // (CFBundleURLTypes) — no plist change needed for this path.
        // Invite claim: a tapped invite link stashes its code so the
        // redeem field in Invite friends is prefilled next open.
        if url.host == "invite", let code = InviteCode.code(from: url) {
            SharedDefaults.store.set(code, forKey: InviteCode.deepLinkCodeKey)
            return
        }
        // The old `gymtracker://preset/daron` unlock is gone: any web page
        // or message could open it and silently replace the active program
        // (a hidden unlock is an App Review 2.3.1 risk). Devices that
        // already claimed the preset keep it — the unlock flag is stored.
        // Today is the default landing screen (the TabView opens on Today).
        // A specific day is not directly navigable in v1 — the app opens to
        // Today, which shows that day's plan when it matches.
        _ = url.host
    }
}

// MARK: - Loading screen (cold start)

/// The cold-start loading screen. When the app is tapped from the home
/// screen and is NOT already open in the app switcher, the process is
/// fresh and this shows while the app starts: the Status dumbbell
/// logo assembles GameCube / Nintendo Switch style — the two halves
/// slide in from the sides and CLICK together to form the white dumbbell
/// on the brand blue (#007AFF, the app icon), with a haptic at the click
/// — then "Status" fades in below and the app opens.
///
/// It only shows on a cold start: `isLoading` lives in the App struct's
/// @State, which persists for the process lifetime, so resuming from the
/// app switcher (same process) never shows it again.
struct LoadingView: View {
    /// The two halves of the dumbbell, sliding in to click together.
    @State private var halvesTogether = false
    /// The click pulse (scale + glow) at the moment the halves meet.
    @State private var clicked = false
    /// "Status" fading in after the click.
    @State private var showName = false

    /// Brand blue (the app icon background, #007AFF).
    private static let brandBlue = Color(red: 0.0, green: 0.478, blue: 1.0)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Self.brandBlue.ignoresSafeArea()
                VStack(spacing: 28) {
                    // The dumbbell, in two halves.
                    HStack(spacing: 0) {
                        DumbbellHalf(isLeft: true)
                            .offset(x: halvesTogether ? 0 : -(proxy.size.width / 2 + 160))
                        DumbbellHalf(isLeft: false)
                            .offset(x: halvesTogether ? 0 : (proxy.size.width / 2 + 160))
                    }
                    .frame(width: 200, height: 100)
                    .scaleEffect(clicked ? 1.07 : 1.0)
                    .shadow(color: .white.opacity(clicked ? 0.7 : 0), radius: clicked ? 24 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.62), value: halvesTogether)
                    .animation(.spring(response: 0.22, dampingFraction: 0.5), value: clicked)
                    // The click haptic as the halves meet.
                    .sensoryFeedback(.impact(weight: .medium), trigger: clicked)

                    Text("Status")
                        .scaledFont(size: 32, weight: .bold)
                        .foregroundStyle(.white)
                        .opacity(showName ? 1 : 0)
                        .offset(y: showName ? 0 : 8)
                        .animation(AppAnimation.snappy, value: showName)
                }
            }
        }
        .onAppear(perform: runAnimation)
    }

    private func runAnimation() {
        // Halves slide in and click together (the spring overshoots
        // slightly, so they land with a click).
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
            halvesTogether = true
        }
        // The click: scale/glow pulse as the halves meet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
                clicked = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.easeOut(duration: 0.2)) { clicked = false }
            }
        }
        // Name fades in after the click.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(AppAnimation.snappy) { showName = true }
        }
    }
}

/// One half of the white dumbbell logo (the app icon), drawn in code.
/// Left half: outer plate + inner plate + the left half of the bar.
/// Right half: the right half of the bar + inner plate + outer plate.
/// Each half is a 100×100 canvas; the two sit side by side (spacing 0)
/// to form the full 200×100 dumbbell.
private struct DumbbellHalf: View {
    let isLeft: Bool

    var body: some View {
        Path { p in
            if isLeft {
                // Outer plate (tall).
                p.addRoundedRect(in: CGRect(x: 0, y: 3, width: 25, height: 94),
                                 cornerSize: CGSize(width: 8, height: 8))
                // Inner plate (shorter).
                p.addRoundedRect(in: CGRect(x: 27, y: 21, width: 21, height: 58),
                                 cornerSize: CGSize(width: 7, height: 7))
                // Bar (left half, to the center).
                p.addRoundedRect(in: CGRect(x: 48, y: 43, width: 52, height: 14),
                                 cornerSize: CGSize(width: 4, height: 4))
            } else {
                // Bar (right half, from the center).
                p.addRoundedRect(in: CGRect(x: 0, y: 43, width: 52, height: 14),
                                 cornerSize: CGSize(width: 4, height: 4))
                // Inner plate.
                p.addRoundedRect(in: CGRect(x: 52, y: 21, width: 21, height: 58),
                                 cornerSize: CGSize(width: 7, height: 7))
                // Outer plate (tall).
                p.addRoundedRect(in: CGRect(x: 75, y: 3, width: 25, height: 94),
                                 cornerSize: CGSize(width: 8, height: 8))
            }
        }
        .fill(Color.white)
        .frame(width: 100, height: 100)
    }
}
