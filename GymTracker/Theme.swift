import SwiftUI
import UIKit
import CoreMotion

/// OLED dark theme (DaRon, 2026-11-09: "make dark mode oled", "high
/// contrast", "vibrant colors"). This supersedes the old "keeps its light
/// look" rule — the app is dark by default now.
///
/// Rules the palette follows:
/// - TRUE BLACK backgrounds in dark mode (#000000) — OLED pixels turn off.
///   Card surfaces are near-black (#0D0D0D / #1A1A1A), never dark gray,
///   and every card carries a visible border so it reads on the black.
/// - HIGH CONTRAST: primary text is white, secondary text is #D9D9D9 —
///   never washed-out gray-on-black. No `.secondary` system text anywhere
///   in dark mode (it renders at ~60% white and looks faded).
/// - VIBRANT colors: saturated accents (iOS dark-mode vibrant values) —
///   vivid blue accent, vivid green/red for trends, vivid orange for the
///   body highlight. In light mode the same names resolve to the matching
///   saturated system colors.
///
/// All colors are dynamic (UIColor trait-collection providers), so they
/// resolve per color scheme automatically — no view has to thread the
/// scheme through. The app forces dark by default
/// (`AppSettings.colorScheme == .dark`); Light / Dark (OLED) / Auto is in
/// Settings → Appearance, free for everyone.
enum Theme {
    /// Screen background: true black in dark mode, system background in light.
    static let background = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? .black : .systemBackground
    })

    /// The side rail (status bar on the side): a dark grey strip in dark
    /// mode, like Reddit's on the Duo; light grey in light mode.
    static let railBackground = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1) : .secondarySystemBackground
    })

    /// Card surface: near-black in dark mode (reads as black, separates
    /// from the true-black base), secondary system background in light.
    static let card = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.05, alpha: 1) : .secondarySystemBackground
    })

    /// Elevated card (nested rows, timer pills, text fields).
    static let cardElevated = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.10, alpha: 1) : .tertiarySystemBackground
    })

    /// Borders and dividers: strong white in dark mode so edges read on
    /// black; subtle black in light mode.
    static let border = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.22) : UIColor(white: 0, alpha: 0.12)
    })

    /// Primary text: white on black, label on white.
    static let text = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? .white : .label
    })

    /// Secondary text: bright, never washed out — #D9D9D9 on black.
    static let secondaryText = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.85, alpha: 1) : .secondaryLabel
    })

    /// Tertiary text: still readable — #A6A6A6 on black.
    static let tertiaryText = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 0.65, alpha: 1) : .tertiaryLabel
    })

    /// Track (rings, progress bars, chart gridlines, unselected chips).
    static let track = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.18) : .tertiarySystemFill
    })

    /// Vivid accent blue — brighter than #007AFF on black.
    static let accent = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)
            : UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1)
    })

    /// Vivid green (trends up, done states, "have" checks).
    static let vividGreen = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.188, green: 0.819, blue: 0.345, alpha: 1)
            : .systemGreen
    })

    /// Vivid red (trends down, destructive states).
    static let vividRed = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.271, blue: 0.227, alpha: 1)
            : .systemRed
    })

    /// Vivid orange (body highlight, warm accents).
    static let vividOrange = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.624, blue: 0.039, alpha: 1)
            : .systemOrange
    })

    /// Vivid pink (fresh-muscle state).
    static let vividPink = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.216, blue: 0.373, alpha: 1)
            : .systemPink
    })

    /// Vivid purple (recovering-muscle state).
    static let vividPurple = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.749, green: 0.353, blue: 0.949, alpha: 1)
            : .systemPurple
    })

    /// Vivid teal.
    static let vividTeal = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 0.392, green: 0.824, blue: 1.0, alpha: 1)
            : .systemTeal
    })

    /// Vivid yellow.
    static let vividYellow = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.839, blue: 0.039, alpha: 1)
            : .systemYellow
    })
}

/// Completed-state tints (DaRon 22:32): when a set or a whole exercise
/// is completed, its colors mute to a very, very light tint of the
/// original accent — not grey, not full color, just a faint whisper of
/// the accent so completed work reads as done but still carries it.
/// The accent comes from Color.accentColor (the app's tint: the
/// Pro-picked accent, or Theme.accent blue when free), so a Pro accent
/// change flows through automatically. Uncompleted work keeps its full
/// vivid colors. The single shared definition — Today, History, and
/// anywhere else a done checkmark appears use this, never a local copy.
enum CompletedTint {
    /// Faint accent wash for filled shapes (done "+" disc, "Current"
    /// pill on a done card).
    static var completedFill: Color { Color.accentColor.opacity(0.15) }
    /// Faint accent for glyphs and text on completed work (the check
    /// itself, the "+" glyph, "All sets done", the hint on a done card,
    /// done set dots).
    static var completedGlyph: Color { Color.accentColor.opacity(0.35) }
}

/// Bottom clearance shared by every scrollable screen (Debug Pass 2,
/// DaRon 2026-11-10: "UI elements shouldn't be cut off at the bottom").
/// One rule, one constant — no per-screen magic numbers. The floating
/// stack in ContentView (menu button, and the rest-timer panel above it
/// while a rest runs) floats over every page, so scrollable content
/// must end this far above its container's bottom edge for the last
/// element to scroll fully into view, clear of the floating stack.
/// The clearance is measured from the scroll container's bottom edge
/// (the bottom safe area), while the floating stack is measured from
/// the screen's bottom edge — the safe area only ever adds room, so
/// these values clear on every device and pose.
enum LayoutClearance {
    /// 96pt — clears the floating menu button alone: 56pt button +
    /// 24pt above the screen's bottom edge + 16pt gap. The button's
    /// top is 80pt above the screen bottom; 96pt from the safe-area
    /// bottom always exceeds it.
    static let fab: CGFloat = 96

    /// The floating rest-timer panel's height, compact layout
    /// (RestTimerCard: ~34pt header row + 6 + ~20pt water row + 6 +
    /// 44pt pill row + 16pt vertical padding ≈ 126pt). The panel sits
    /// 16pt above the menu button, so while a rest runs the floating
    /// stack's top is 96 + 126 = 222pt above the screen's bottom edge
    /// — and it would cover the Finish & Save button at scroll-bottom
    /// if content only cleared the menu button.
    static let restTimerPanelHeight: CGFloat = 126

    /// 238pt — clears the whole floating stack while a rest runs:
    /// 96 (menu-button zone) + 126 (timer panel) + 16 (gap). Same
    /// safe-area reasoning as `fab`: measured from the safe-area
    /// bottom, it always exceeds the panel top's height above the
    /// screen bottom on every device.
    static let withRestTimer: CGFloat = fab + restTimerPanelHeight + 16

    /// The clearance in effect right now: the timer value while a rest
    /// is running or paused (the panel is on screen), else the
    /// menu-button value.
    ///
    /// `fabOffset` is how far the menu button's bottom edge sits above
    /// the safe-area bottom (ContentView measures it and publishes it as
    /// `\.fabBottomOffset`). The approved placement puts the button at
    /// 26% of the screen height, far above the old 24pt rule the fixed
    /// constants assume, so on tall screens (iPad, Duo landscape) content
    /// couldn't scroll clear of it and Finish & Save stayed hidden.
    static func bottom(restActive: Bool, fabOffset: CGFloat = 24) -> CGFloat {
        let extra = max(0, fabOffset - 24)
        return (restActive ? withRestTimer : fab) + extra
    }
}

/// How far the floating menu button's bottom edge sits above the
/// safe-area bottom, published by ContentView for scroll clearance.
private struct FabBottomOffsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 24
}

/// The page area ContentView actually gives a page (inside the safe
/// area). Today decides its pose from this, not from the GeometryReader
/// inside its own NavigationStack: on the Duo's outer screen held
/// sideways that stack reported ~520–568pt of height on a 466pt screen,
/// which picked the open-book split layout while folded (Nov 12).
private struct PageContainerSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

/// The open Duo shows two pages side by side. `duoWide` is true while
/// it does; `duoSwapped` mirrors the two pages (the swap button in the
/// bottom-left corner, Nov 12) for people who want the front-screen
/// page on the left instead of the right.
private struct DuoWideKey: EnvironmentKey { static let defaultValue = false }
private struct DuoSwappedKey: EnvironmentKey { static let defaultValue = false }
/// How far the open Duo's pages are through a swap, 0 (pane on the
/// left) to 1 (pane on the right), moving smoothly while they slide.
/// Side-dependent details read it so they glide with the pages.
/// How far this page is pulled in on the right to clear the corner
/// buttons (the DS layout's bottom page). Things that belong in the
/// button column (Today's +) shift right by it.
private struct DuoCornerInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private struct DuoSwapProgressKey: EnvironmentKey { static let defaultValue: Double = -1 }

extension EnvironmentValues {
    var fabBottomOffset: CGFloat {
        get { self[FabBottomOffsetKey.self] }
        set { self[FabBottomOffsetKey.self] = newValue }
    }
    var pageContainerSize: CGSize {
        get { self[PageContainerSizeKey.self] }
        set { self[PageContainerSizeKey.self] = newValue }
    }
    var duoWide: Bool {
        get { self[DuoWideKey.self] }
        set { self[DuoWideKey.self] = newValue }
    }
    var duoSwapped: Bool {
        get { self[DuoSwappedKey.self] }
        set { self[DuoSwappedKey.self] = newValue }
    }
    var duoCornerInset: CGFloat {
        get { self[DuoCornerInsetKey.self] }
        set { self[DuoCornerInsetKey.self] = newValue }
    }
    var duoSwapProgress: Double {
        get { self[DuoSwapProgressKey.self] }
        set { self[DuoSwapProgressKey.self] = newValue }
    }
    /// The corner buttons live in the side rail (Settings → Status bar on
    /// the side), so pages no longer need to keep clear of them.
    /// The corner buttons stay on the pages beside the rail (DaRon: keep
    /// the side strip clear), so pages keep their usual gaps for them.
    var cornerButtonsInRail: Bool {
        get { self[CornerButtonsInRailKey.self] }
        set { self[CornerButtonsInRailKey.self] = newValue }
    }
    /// Side status bar on: Today's + joins the corner column.
    var todayPlusInColumn: Bool { railEdge != nil }
    /// The edge of the side rail, when it's shown.
    var railEdge: HorizontalEdge? {
        get { self[RailEdgeKey.self] }
        set { self[RailEdgeKey.self] = newValue }
    }
    /// Where a main page's big title starts, from the screen's top edge.
    /// The Duo's status icons sit only at the top right, so the title
    /// shares their row (30); a slab iPhone's clock is at the top left,
    /// so the title starts below the status bar there.
    var pageTitleTop: CGFloat {
        get { self[PageTitleTopKey.self] }
        set { self[PageTitleTopKey.self] = newValue }
    }
    /// iOS is drawing the Duo's side bar itself (its tab bar, Back and
    /// toolbar items run down the side): the page's actions go in the
    /// toolbar instead of floating buttons.
    /// This page keeps itself clear of the system side bar (off where a
    /// container already does, or the page isn't the one beside it).
    var sideBarInset: Bool {
        get { self[SideBarInsetKey.self] }
        set { self[SideBarInsetKey.self] = newValue }
    }
    var systemSideBar: Bool {
        get { self[SystemSideBarKey.self] }
        set { self[SystemSideBarKey.self] = newValue }
    }

    var cornerColumnTop: CGFloat {
        get { self[CornerColumnTopKey.self] }
        set { self[CornerColumnTopKey.self] = newValue }
    }
    /// ContentView draws the keyboard's Done button itself (main pages).
    var appDrawsKeyboardDone: Bool {
        get { self[AppDrawsKeyboardDoneKey.self] }
        set { self[AppDrawsKeyboardDoneKey.self] = newValue }
    }
    /// The hinge's x within the page area (the screen's middle, minus a
    /// side bar on the left). 0 = unknown.
    var duoHingeX: CGFloat {
        get { self[DuoHingeXKey.self] }
        set { self[DuoHingeXKey.self] = newValue }
    }
    /// The phone is open (whole screen, not the page beside a side bar).
    var screenIsOpen: Bool {
        get { self[ScreenIsOpenKey.self] }
        set { self[ScreenIsOpenKey.self] = newValue }
    }
    /// This page is the one on screen (hidden pages stay mounted).
    var pageVisible: Bool {
        get { self[PageVisibleKey.self] }
        set { self[PageVisibleKey.self] = newValue }
    }
    /// The pair is in the DS layout (halves stacked at the fold).
    var duoStacked: Bool {
        get { self[DuoStackedKey.self] }
        set { self[DuoStackedKey.self] = newValue }
    }
}

private struct DuoStackedKey: EnvironmentKey { static let defaultValue = false }
private struct RailEdgeKey: EnvironmentKey { static let defaultValue: HorizontalEdge? = nil }
private struct CornerButtonsInRailKey: EnvironmentKey { static let defaultValue = false }
private struct PageVisibleKey: EnvironmentKey { static let defaultValue = true }
private struct ScreenIsOpenKey: EnvironmentKey { static let defaultValue = false }
private struct DuoHingeXKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private struct PageTitleTopKey: EnvironmentKey { static let defaultValue: CGFloat = 30 }
private struct SystemSideBarKey: EnvironmentKey { static let defaultValue = false }
private struct SideBarInsetKey: EnvironmentKey { static let defaultValue = true }
private struct CornerColumnTopKey: EnvironmentKey { static let defaultValue: CGFloat = .infinity }
private struct AppDrawsKeyboardDoneKey: EnvironmentKey { static let defaultValue = false }

// MARK: - Duo page pair (swap like two apps, Nov 12)

/// Marks the swap-sides animation, so it passes through views that
/// otherwise switch animation off (Today's content does, to keep
/// unfolding seamless).
private struct DuoSwapTransactionKey: TransactionKey { static let defaultValue = false }

extension Transaction {
    var duoSwap: Bool {
        get { self[DuoSwapTransactionKey.self] }
        set { self[DuoSwapTransactionKey.self] = newValue }
    }
}

/// Runs `body` with `animation`, marked as part of a swap.
func withDuoSwapAnimation(_ animation: Animation, _ body: () -> Void) {
    var t = Transaction(animation: animation)
    t.duoSwap = true
    withTransaction(t, body)
}

/// The open Duo's two pages: the waiting `pane` and the front screen's
/// `main` page. Unswapped the pane is on the left; swapped, the right.
///
/// Swapping is ONE motion, like trading two apps' sides on iPhone Duo:
/// a single animated value carries both pages across, and the slight
/// lift (cards a hair smaller, rounded, shadowed) is part of that same
/// curve: it rises and falls with the slide, full size at both ends.
/// Nothing re-lays out: both pages keep their size and identity the
/// whole way; only their positions move.
struct DuoPagePair<Pane: View, Main: View>: View {
    var wide: Bool
    var swapped: Bool
    /// The main page's width (the front screen's), nil to share equally.
    var mainWidth: CGFloat? = TodayView.outerDisplayWidth
    /// Stack the pages DS style when the open Duo is held upright. Every
    /// page does except Profile (DaRon), which stays side by side.
    var stacksWhenTall = true
    /// Draw a hairline at the hinge between the pages (Notes).
    var showsDivider = false
    /// On the DS bottom half, pull the companion page in to clear the
    /// corner buttons. Today's body stays centered (DaRon), so it doesn't.
    var paneClearsCorner = true
    /// Same for the main page. Notes' list keeps its full width (its
    /// search bar stopped short); its last rows scroll clear instead.
    var mainClearsCorner = true
    /// Side by side: the main page never gets narrower than this when the
    /// line is dragged (Today's workout rows need the folded width).
    var mainMinWidth: CGFloat? = nil
    @ViewBuilder var pane: () -> Pane
    @ViewBuilder var main: () -> Main

    /// The most of the width the companion page may take, so the main page
    /// keeps its minimum.
    static func maxPaneShare(total: CGFloat, mainMinWidth: CGFloat?) -> Double {
        guard let m = mainMinWidth, total > 0 else { return 1 }
        return max(Double(1 - m / total), 0)
    }

    /// The fold's band while the Duo is partly open, left to right in the
    /// pair's space; nil when open flat, folded, or before iOS 27.1.
    static func activeFold(in geo: GeometryProxy) -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        return geo.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
            .first(where: \.isActive)?.frame
    }

    /// The companion page's default share of the width side by side.
    static func sideDefault(total: CGFloat, mainWidth: CGFloat?) -> Double {
        guard total > 0 else { return 0.5 }
        return Double(max(total - min(mainWidth ?? total / 2, total), 0) / total)
    }

    @Environment(\.layoutDirection) private var direction
    @Environment(\.duoHingeX) private var hingeX
    /// The page size without the keyboard: the keyboard must never flip
    /// the DS layout or move its split off the hinge (red team).
    @State private var steady: CGSize = .zero
    /// DS layout: where the line between the halves sits, as a share of
    /// the height from the top. DaRon can drag it; 0.5 is the hinge.
    /// One setting for every page.
    @AppStorage("duoFoldSplit") private var split: Double = 0.5
    /// Side by side: how far the line has been dragged from its default
    /// (the main page at the front screen's width), as a share of the
    /// width. One setting for every page.
    @AppStorage("duoSideShift") private var sideShift: Double = 0
    /// While a line is being dragged: only this pair moves, and the
    /// setting is saved once on release.
    @State private var liveSplit: Double?
    @State private var liveShift: Double?
    /// When the pair last changed size (a plain reference: noting it never
    /// causes another pass).
    @State private var sizeClock = SizeClock()
    final class SizeClock {
        private var size: CGSize = .zero
        private var since: Date = .distantPast
        func note(_ s: CGSize) {
            if abs(s.width - size.width) > 0.5 || abs(s.height - size.height) > 0.5 { size = s; since = Date() }
        }
        var stable: Bool { Date().timeIntervalSince(since) > 0.6 }
    }

    var body: some View {
        GeometryReader { geo in
            // A width change (unfold, rotate) is never the keyboard: use the
            // live size at once, or one frame drew the old layout (red team).
            let s = steady.width > 0 && abs(steady.width - geo.size.width) < 1 ? steady : geo.size
            let stacked = wide && stacksWhenTall && s.height > s.width
            // Partly open, iOS reserves a band down the fold ("division",
            // with its margins). Like Settings and the home screen, the
            // pages step clear of it, and back when the Duo opens flat.
            let fold = wide && !stacked ? Self.activeFold(in: geo) : nil
            // Glide only when the hinge moves on a screen that's already
            // showing (partly open <-> open: same size). Coming from closed
            // the screen has just changed size, and it appears with the
            // pages already clear of the fold, as Settings does.
            let _ = sizeClock.note(geo.size)
            let foldGlides = sizeClock.stable && HingeState.shared.settledOpen
            // Open and upright (DaRon: Nintendo DS style): one page on
            // each half, top and bottom of the fold; the companion page is
            // the top screen. Same view either way (only the frames and
            // offsets change), so rotating never rebuilds the pages — a
            // separate stacked view lost the open note mid-typing.
            DuoPairStage(progress: wide && swapped ? 1 : 0,
                         wide: wide,
                         stacked: stacked,
                         showsDivider: showsDivider,
                         paneClearsCorner: paneClearsCorner,
                         mainClearsCorner: mainClearsCorner,
                         // Stacked keeps the keyboard-free height, so the
                         // halves stay on the hinge; pages still get the
                         // keyboard's safe area and scroll above it.
                         size: stacked ? CGSize(width: geo.size.width, height: s.height) : geo.size,
                         // Pages lay out at the saved split only; while a line
                         // is dragged just the line moves (no re-layout every
                         // frame, which made the pages flicker), and the pages
                         // slide over once on release (DaRon).
                         split: .constant(split),
                         sideShift: .constant(sideShift),
                         dragSplit: Binding(get: { liveSplit ?? split }, set: { liveSplit = $0 }),
                         dragShift: Binding(get: { liveShift ?? sideShift }, set: { liveShift = $0 }),
                         hingeX: hingeX,
                         commit: {
                             withAnimation(AppAnimation.page) {
                                 if let v = liveSplit { split = v }
                                 if let v = liveShift { sideShift = v }
                             }
                             liveSplit = nil; liveShift = nil
                         },
                         mainMinWidth: mainMinWidth,
                         // Side by side on the tall upright screen (Profile):
                         // half each. At the folded width the section page
                         // got only ~216pt and every page in it wrapped.
                         mainWidth: wide && !stacked && s.height > s.width ? nil : mainWidth,
                         direction: direction,
                         fold: fold,
                         foldGlides: foldGlides,
                         pane: pane, main: main)
        }
        // The pages span the whole screen, edge to edge (their content
        // still gets the safe areas). Only the top used to be ignored, so
        // the cards were sized to the screen minus the home-indicator
        // strip: a hairline gap at the top, a wide one at the bottom.
        .ignoresSafeArea(.container)
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { steady = g.size }
                    .onChange(of: g.size) { _, size in steady = size }
            }
            .ignoresSafeArea(.container)
            .ignoresSafeArea(.keyboard)
        }
    }
}

/// Lays the two pages out. NOT animated itself (Nov 13, animations were
/// laggy): each page takes its final size and place at once, with no
/// animation, and only light visual modifiers (SwapMotion, SwapFade) play
/// the slide. Animating the whole stage re-laid out both pages at a new
/// width on every frame of a swap (the pages trade widths) and rebuilt
/// their content each frame: the swap ran at about 23 fps.
private struct DuoPairStage<Pane: View, Main: View>: View {
    /// Where the swap ends: 0 = unswapped, 1 = swapped. The slide between
    /// them is animated by the modifiers that read it.
    var progress: Double
    var wide: Bool
    /// DS layout: halves stacked top and bottom instead of side by side.
    var stacked = false
    var showsDivider = false
    var paneClearsCorner = true
    var mainClearsCorner = true
    var size: CGSize
    @Binding var split: Double
    @Binding var sideShift: Double
    @Binding var dragSplit: Double
    @Binding var dragShift: Double
    var hingeX: CGFloat = 0
    var commit: () -> Void
    var mainMinWidth: CGFloat?
    var mainWidth: CGFloat?
    var direction: LayoutDirection
    /// The fold's band while partly open (see DuoPagePair.activeFold).
    var fold: CGRect? = nil
    var foldGlides = true
    var pane: () -> Pane
    var main: () -> Main

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cornerButtonsInRail) private var inRail

    var body: some View {
        let total = size.width
        // DS: the line between the halves (draggable, 0.5 = the hinge).
        let topH = stacked ? size.height * DuoSplitHandle.clamp(split) : size.height / 2
        // Side by side: the companion page's share of the width, dragged
        // from its default and kept between a third and two thirds.
        // Its usual spot is the real hinge (DaRon), on every page.
        let maxPane = DuoPagePair<Pane, Main>.maxPaneShare(total: total, mainMinWidth: mainMinWidth)
        // Upright the hinge runs across, not down the middle: there the
        // pages share the width equally (at "the hinge" the side bar's
        // width all came out of the right page, which got ~216pt).
        let sideDefault = hingeX > 0 && total > 0 && size.width >= size.height
            ? Double(min(max(hingeX / total, 0), 1))
            : DuoPagePair<Pane, Main>.sideDefault(total: total, mainWidth: mainWidth)
        let e: Double = progress >= 0.5 ? 1 : 0
        let swappedEnd = e == 1
        // The left page's share: the line stays where it is when the pages
        // swap (they trade widths), at the hinge unless dragged (DaRon),
        // and the main page never gets narrower than its minimum.
        func capLeft(_ v: Double) -> Double {
            let c = DuoSplitHandle.clamp(v)
            return swappedEnd ? max(c, 1 - maxPane) : min(c, maxPane)
        }
        let leftShare = capLeft(sideDefault + sideShift)
        let paneShare = min(swappedEnd ? 1 - leftShare : leftShare, maxPane)
        let botH = size.height - topH
        // Side by side: the main page keeps the front screen's width.
        // Stacked (DS): both pages are full width, half height each.
        let mainW = stacked ? total : (wide ? total * (1 - paneShare) : total)
        let paneW = stacked ? total : max(total - mainW, 0)
        // Stacked: each page takes the size of the half it ends in.
        let paneH = stacked ? (swappedEnd ? botH : topH) : size.height
        let mainH = stacked ? (swappedEnd ? topH : botH) : size.height
        let layout = SwapLayout(total: total, paneW: paneW, mainW: mainW, topH: topH,
                                stacked: stacked, rtl: direction == .rightToLeft,
                                wide: wide, calm: reduceMotion)
        let paneEnd = layout.position(.pane, slide: e)
        let mainEnd = layout.position(.main, slide: e)
        // Partly open: a page that reaches into the fold's band stops at
        // its near edge instead.
        func clearOfFold(_ x: CGFloat, _ w: CGFloat) -> (x: CGFloat, w: CGFloat) {
            guard let f = fold, w > 0, x < f.maxX, x + w > f.minX else { return (x, w) }
            if x + w / 2 < f.midX { return (x, max(f.minX - x, 0)) }
            return (f.maxX, max(x + w - f.maxX, 0))
        }
        let paneFit = clearOfFold(paneEnd.x, paneW)
        let mainFit = clearOfFold(mainEnd.x, mainW)
        let cornerSlide: CGFloat = e
        return ZStack(alignment: .topLeading) {
            // A grey backdrop behind the cards, like Duo multitasking.
            Color(.systemGray3)
                .modifier(SwapFade(progress: e) { p in min(1, layout.lift(p) * 3) })
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if wide {
                pane()
                    .environment(\.layoutDirection, direction)
                    // DS: the bottom half keeps clear of the corner buttons.
                    .safeAreaPadding(.trailing, stacked && paneClearsCorner && !inRail ? 76 * cornerSlide : 0)
                    .environment(\.duoCornerInset, stacked && paneClearsCorner && !inRail ? 76 * cornerSlide : 0)
                    .frame(width: paneFit.w, height: paneH, alignment: .top)
                    .clipped()
                    // Real layout position (not a visual-only offset), so
                    // safe areas and hit areas match where the page is.
                    .alignmentGuide(.leading) { _ in -paneFit.x }
                    .alignmentGuide(.top) { _ in -paneEnd.y }
                    .modifier(SwapLayoutStill())
                    .modifier(SwapMotion(progress: e, target: e, role: .pane, layout: layout,
                                         size: CGSize(width: paneFit.w, height: paneH)))
            }
            main()
                .environment(\.layoutDirection, direction)
                .safeAreaPadding(.trailing, stacked && mainClearsCorner && !inRail ? 76 * (1 - cornerSlide) : 0)
                .environment(\.duoCornerInset, stacked && mainClearsCorner && !inRail ? 76 * (1 - cornerSlide) : 0)
                .frame(width: mainFit.w, height: mainH, alignment: .top)
                .clipped(antialiased: stacked)
                .alignmentGuide(.leading) { _ in wide ? -mainFit.x : 0 }
                .alignmentGuide(.top) { _ in -mainEnd.y }
                .modifier(SwapLayoutStill())
                .modifier(SwapMotion(progress: e, target: e, role: .main, layout: layout,
                                     size: CGSize(width: mainFit.w, height: mainH)))
                // The front screen's page passes over the other one.
                .zIndex(1)
            // At rest: a hairline at the hinge (DS fold, or Notes' pages).
            if wide && !stacked {
                // Side by side: the same fade as the DS fold, on both
                // sides of the line between the pages, wherever it's
                // dragged (DaRon). (Notes' hairline is part of it.)
                let x = swappedEnd ? mainW : paneW
                FoldFade(width: size.height, vertical: true)
                    .offset(x: (direction == .rightToLeft ? total - x : x) - FoldFade.reach)
                    .modifier(SwapFade(progress: e) { p in layout.lift(p) > 0 ? 0 : 1 })
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(2)
            }
            if stacked {
                // The fold gets the same treatment as the top of the screen
                // (DaRon), on both sides of the line: content loses its
                // color and fades into the page as it nears the hinge.
                FoldFade(width: total)
                    .offset(y: topH - FoldFade.reach)
                    // Off for the whole swap, never half faded: a blend
                    // under a partial opacity draws a grey band (red team).
                    .modifier(SwapFade(progress: e) { p in layout.lift(p) > 0 ? 0 : 1 })
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .zIndex(2)
                // Drag the line to give either half more room (DaRon).
                DuoSplitHandle(share: $dragSplit, length: size.height, span: total,
                               horizontal: true, rest: 0.5, onCommit: commit)
                    .offset(y: size.height * DuoSplitHandle.clamp(dragSplit) - DuoSplitHandle.grab / 2)
                    .modifier(SwapFade(progress: e) { p in layout.lift(p) > 0 ? 0 : 1 })
                    .zIndex(3)
            }
            if wide && !stacked {
                // The line between side-by-side pages: dragging right gives
                // the left page more room. Swapped, the main page is on the
                // left, so the same drag shrinks the companion.
                // Follows the finger; the pages catch up on release.
                let dragLeft = capLeft(sideDefault + dragShift)
                let lineX = total * (direction == .rightToLeft ? 1 - dragLeft : dragLeft)
                let mirrored = direction == .rightToLeft
                DuoSplitHandle(
                    share: Binding(
                        get: { mirrored ? 1 - dragLeft : dragLeft },
                        set: { dragShift = capLeft(mirrored ? 1 - $0 : $0) - sideDefault }
                    ),
                    length: total, span: size.height,
                    horizontal: false,
                    rest: mirrored ? 1 - sideDefault : sideDefault,
                    onCommit: commit)
                    .offset(x: lineX - DuoSplitHandle.grab / 2)
                    .modifier(SwapFade(progress: e) { p in layout.lift(p) > 0 ? 0 : 1 })
                    .zIndex(3)
            }
        }
        // Stepping clear of the fold and back glides like the home screen
        // (Reduce Motion: no glide).
        .animation(reduceMotion || !foldGlides ? nil : AppAnimation.hinge, value: fold)
        .frame(width: total, height: size.height, alignment: .topLeading)
        // One solid layer: the fold's black-and-white strip blends with the
        // pages under it. Without a solid backdrop, a page fading in (page
        // switch) left it blending with nothing, so it showed as a grey
        // band and then popped back (red team, animations).
        .background(wide ? Theme.background : Color.clear)
        .compositingGroup()
        // Reduce Motion: the pages trade places under a quick fade.
        .modifier(SwapFade(progress: e) { p in reduceMotion && wide ? abs(1 - 2 * p) * 0.85 + 0.15 : 1 })
        .environment(\.layoutDirection, .leftToRight)
        // -1 = not in a pair (the + button falls back to duoSwapped).
        .environment(\.duoSwapProgress, wide ? e : -1)
        .environment(\.duoStacked, stacked)
    }
}

/// The numbers a swap needs, from its end state: where each page sits at
/// any point of the slide, how far the cards lift, and their insets.
private struct SwapLayout {
    enum Role { case pane, main }
    var total: CGFloat, paneW: CGFloat, mainW: CGFloat, topH: CGFloat
    var stacked: Bool, rtl: Bool, wide: Bool, calm: Bool

    static func smooth(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }

    /// One continuous motion in three overlapping beats: the cards lift in
    /// place, slide past each other, and land. Reduce Motion: no slide.
    func slide(_ p: Double) -> Double { calm ? (p < 0.5 ? 0 : 1) : Self.smooth((p - 0.2) / 0.6) }

    /// 0 at rest, 1 for most of the slide: the cards lift off quickly,
    /// hold their card shape while they cross, and settle at the end.
    func lift(_ p: Double) -> Double {
        wide && !calm ? Self.smooth(p / 0.22) * Self.smooth((1 - p) / 0.22) : 0
    }

    /// Left-to-right position of a page at a point of the slide.
    func position(_ role: Role, slide s: Double) -> CGPoint {
        var x: CGFloat, y: CGFloat
        switch role {
        case .pane: x = stacked ? 0 : s * mainW; y = stacked ? s * topH : 0
        case .main: x = stacked ? 0 : (1 - s) * paneW; y = stacked ? (1 - s) * topH : 0
        }
        if rtl && !stacked { x = total - x - (role == .pane ? paneW : mainW) }
        return CGPoint(x: x, y: y)
    }

    /// Even spacing all around (DaRon): each card pulls in a full gap at
    /// the screen edge and half a gap on the side facing the other card.
    func insets(_ role: Role, slide s: Double) -> (leading: CGFloat, trailing: CGFloat) {
        let g = DuoSwapCard.inset, half = g / 2
        if stacked { return (g, g) }
        var r: (CGFloat, CGFloat) = role == .pane
            ? (g - half * s, half + half * s)
            : (half + half * s, g - half * s)
        if rtl { r = (r.1, r.0) }
        return (leading: r.0, trailing: r.1)
    }
}

/// A page's slide and lift for one frame of a swap: only a visual offset
/// and the card effect (scale, corners, shadow), so the page itself is
/// never laid out again mid-swap. At rest it's exactly the page.
private struct SwapMotion: ViewModifier, Animatable {
    var progress: Double
    /// Where the swap ends (not animated): the page's real place.
    var target: Double
    var role: SwapLayout.Role
    var layout: SwapLayout
    var size: CGSize
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        let p = min(max(progress, 0), 1)
        let s = layout.slide(p)
        let now = layout.position(role, slide: s)
        let rest = layout.position(role, slide: target)
        let inset = layout.insets(role, slide: s)
        content
            .modifier(DuoSwapCard(lift: layout.lift(p), size: size,
                                  leading: inset.leading, trailing: inset.trailing))
            .offset(x: now.x - rest.x, y: now.y - rest.y)
    }
}

/// An opacity that follows the swap frame by frame.
private struct SwapFade: ViewModifier, Animatable {
    var progress: Double
    var value: (Double) -> Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.opacity(value(min(max(progress, 0), 1)))
    }
}

/// A swap moves pages only visually (SwapMotion): their size and place
/// change at once, never frame by frame (that re-laid out the whole page
/// on every frame).
private struct SwapLayoutStill: ViewModifier {
    func body(content: Content) -> some View {
        content.transaction { if $0.duoSwap { $0.animation = nil } }
    }
}

/// A page mid-swap: inset so every gap is 10pt, rounded
/// and shadowed in proportion to `lift`; exactly the page at rest.
struct DuoSwapCard: ViewModifier {
    var lift: Double
    /// The page's size, so the insets come out in points.
    var size: CGSize
    /// How far the card pulls in on its left and right (at full lift);
    /// top and bottom always pull in the full gap.
    var leading: CGFloat = inset
    var trailing: CGFloat = inset
    /// The one gap used everywhere mid-swap: screen edges and between
    /// the two cards (DaRon: even space all around).
    static let inset: CGFloat = 10

    func body(content: Content) -> some View {
        let l = leading * lift, r = trailing * lift, v = Self.inset * lift
        let sx = size.width > 0 ? max(0, 1 - (l + r) / size.width) : 1
        let sy = size.height > 0 ? max(0, 1 - 2 * v / size.height) : 1
        // Always the same modifiers (only their amounts change), so the
        // page is never rebuilt when a swap starts or ends. At rest the
        // mask sits far outside the page and nothing is clipped.
        let edge = min(1, lift * 4)
        content
            // Always solid: a see-through card let the grey backdrop tint
            // the whole page at the end of a swap, then pop back to black
            // (the flicker DaRon saw).
            .background(Theme.background)
            .mask {
                // Close to the Duo's own screen corners.
                RoundedRectangle(cornerRadius: 36 * lift, style: .continuous)
                    .padding(-200 * (1 - edge))
            }
            .shadow(color: .black.opacity(0.35 * lift), radius: 14 * lift, y: 6 * lift)
            // Inset evenly: the same gap at the top, bottom and sides
            // (a plain percentage left the tall pages more space top and
            // bottom than at the sides).
            .scaleEffect(x: sx, y: sy)
            // Unequal side insets: shift so each side lands where it should.
            .offset(x: (l - r) / 2)
    }
}

/// The ONE fold/unfold animation scheme (Debug Pass 2, fold glitch,
/// Tue 2026-11-10): every pose-driven change in the app animates on
/// this spring, so all elements finish together instead of popping in
/// sequence. One spring, one namespace scheme — no per-screen curves.
///
/// - `morph`: the fold morph itself. Same 0.25s response as
///   `AppAnimation.snappy` (Models.swift:617 — read-only here, do not
///   move the enum) so fold morphs and in-flight snappy animations
///   finish together, but near-critically damped (0.9 vs snappy's 0.8)
///   so the morph never overshoots and pops back — overshoot on a
///   frame interpolation reads as a jump. The old fold spring
///   (0.45/0.85, since removed) settled in ~0.8s, longer than the physical fold, so
///   the UI was still settling after the hinge stopped — that lag IS
///   the glitch. This settles in ~0.45s, inside the fold.
/// - `settle`: the 150–200ms ease-out for fades that ride the fold
///   (Track 3: continuity transitions are 150–200ms ease-out).
enum FoldAnimation {
    static let morph = Animation.spring(response: 0.25, dampingFraction: 0.9)
    static let settle = Animation.easeOut(duration: 0.2)
}

extension View {
    /// OLED card: near-black surface + a visible border so the card reads
    /// on the true-black background. Use for the top-level cards (exercise
    /// cards, timer card, stat cards, day cards).
    /// Every page-level card uses the default 12pt corners (one radius
    /// app-wide); controls nested inside a card use 10.
    func themeCard(cornerRadius: CGFloat = 12) -> some View {
        background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.border, lineWidth: 1))
    }

    /// OLED list/form: true-black base behind the rows, near-black rows,
    /// visible separators. System dark-mode rows are #1C1C1E gray — this
    /// replaces them. Apply to every List/Form in the app.
    func oledList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background)
            .listRowBackground(Theme.card)
            .listRowSeparatorTint(Theme.border)
    }

    /// Dismiss the keyboard from any screen — the shared dismiss behind
    /// the keyboard Done button and tap-outside-to-dismiss. Resigning
    /// the first responder is the whole mechanism; each field's save
    /// path already runs live (Profile bodyweight saves on every
    /// keystroke, Today weight/reps commit on focus loss, notes save on
    /// every keystroke, editors save via their Save button), so
    /// dismissing IS confirming — nothing extra to wire per field.
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Native keyboard toolbar: exactly ONE Done button, directly above
    /// the keyboard (iOS 27.2 native standard). No floating Done, no
    /// custom dismiss button over content. Apply to every view that
    /// contains an editable field — the toolbar only appears while the
    /// keyboard is up. (DaRon 2026-11-10 08:49: Profile bodyweight had
    /// no Done button at all — the keyboard had no way out.)
    /// `system: true` for sheets: the app's floating Done sits behind them.
    func withKeyboardDoneToolbar(system: Bool = false) -> some View {
        modifier(KeyboardDoneToolbar(forceSystem: system))
    }

    /// Tap-outside-to-dismiss: a tap on empty space dismisses the
    /// keyboard — the second dismissal path besides Done. WARNING: do
    /// NOT apply this to a List/Form whose rows are themselves
    /// tap targets (Picker/Toggle rows): the parent .onTapGesture
    /// eats those row taps in the gesture arena — Buttons win, row
    /// taps do not (D20/D24/D39, 2026-11-10). It is safe only where
    /// the controls are Buttons/fields, e.g. the Today page and
    /// Notes, where it is verified working on screen.
    func dismissKeyboardOnTapOutside() -> some View {
        onTapGesture { dismissKeyboard() }
    }
}

/// The system's keyboard Done (its toolbar sat right on the keys, DaRon).
/// Skipped on the main pages, where ContentView floats its own Done with
/// a gap above the keyboard.
private struct KeyboardDoneToolbar: ViewModifier {
    var forceSystem = false
    @Environment(\.appDrawsKeyboardDone) private var appDraws
    func body(content: Content) -> some View {
        if appDraws && !forceSystem {
            content
        } else {
            content.toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { content.dismissKeyboard() }
                }
            }
        }
    }
}

/// One clean menu pill: a single capsule with one background and one
/// border, native iOS Menu styling. Use for EVERY dropdown filter and
/// sort control. The old per-view filterMenu helpers each drew a card
/// inside the List row's own card (the "double pill": a halo around a
/// gray pill), and the List's default button style tinted the label
/// accent blue. This pill has exactly one fill + one stroke, an
/// explicit text color, and `.buttonStyle(.plain)` so the List can
/// never re-tint it. Active (a filter is picked, not "All"): accent
/// tint, so the active state reads at a glance.
struct MenuPill<Content: View>: View {
    var label: String
    var isActive: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu(content: content) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(isActive ? Color.accentColor : Theme.secondaryText)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .background(isActive ? Color.accentColor.opacity(0.15) : Theme.card)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isActive ? Color.accentColor.opacity(0.4) : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// − / value / + stepper that always fits its row (DaRon 2026-11-10
/// 08:54: the "Default rest 90s" native stepper was clipped at the
/// right edge — the + side ran off-screen — with a heavy black divider
/// and flat muddy gray). Fixed 44pt hit targets, a bounded width (two
/// 44pt buttons + a centered value label), Theme.cardElevated fill with
/// a 1pt Theme.border outline and hairline dividers — never the system
/// stepper's gray pill. The control sizes itself to its content, so it
/// can never run off the screen edge in any pose. Value changes go
/// through the same binding the native Stepper used (same floor, same
/// step, clamped to the range), so saving is unchanged.
/// A label with its stepper: side by side when the row has room, the
/// stepper under the label when it doesn't (a narrow pane on the open Duo
/// broke "Default rest" into "De-fault rest" beside the stepper).
struct StepperRow<Stepper: View>: View {
    let title: String
    @ViewBuilder var stepper: Stepper

    init(_ title: String, @ViewBuilder stepper: () -> Stepper) {
        self.title = title
        self.stepper = stepper()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).lineLimit(1).fixedSize()
                Spacer(minLength: 12)
                stepper
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                stepper
            }
        }
    }
}

struct RowStepper<Value: Strideable>: View where Value.Stride: Comparable {
    var value: Binding<Value>
    var range: ClosedRange<Value>
    var step: Value.Stride
    var label: (Value) -> String

    private var canDecrement: Bool { value.wrappedValue > range.lowerBound }
    private var canIncrement: Bool { value.wrappedValue < range.upperBound }

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemImage: "minus", label: "Decrease", disabled: !canDecrement) {
                value.wrappedValue = max(value.wrappedValue.advanced(by: -step), range.lowerBound)
            }
            Rectangle().fill(Theme.border).frame(width: 1)
            Text(label(value.wrappedValue))
                .font(.subheadline.monospacedDigit())
                .frame(minWidth: 48)
                .padding(.horizontal, 4)
            Rectangle().fill(Theme.border).frame(width: 1)
            stepButton(systemImage: "plus", label: "Increase", disabled: !canIncrement) {
                value.wrappedValue = min(value.wrappedValue.advanced(by: step), range.upperBound)
            }
        }
        .background(Theme.cardElevated)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .foregroundStyle(Theme.text)
    }

    private func stepButton(systemImage: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .scaledFont(size: 16, weight: .semibold)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .accessibilityLabel(label)
    }
}

// MARK: - Dynamic Type for fixed point sizes

/// A fixed point size that follows the system text size (Settings →
/// Display & Brightness → Text Size, and Accessibility → Larger Text),
/// updating live when it changes. Use instead of `.font(.system(size:))`,
/// which never scales.
///
/// The size scales like the nearest text style (so a 17pt label grows
/// like Body, a 34pt number like Large Title) and is capped at `maxScale`
/// so glyphs inside fixed-size controls (56pt round buttons, 32pt circles)
/// can't overflow them at the largest accessibility sizes.
struct ScaledFont: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design
    private let maxScale: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, maxScale: CGFloat) {
        self.size = size
        self.weight = weight
        self.design = design
        self.maxScale = maxScale
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: Self.textStyle(for: size))
    }

    func body(content: Content) -> some View {
        content.font(.system(size: min(scaledSize, size * maxScale), weight: weight, design: design))
    }

    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<13: return .footnote
        case ..<18: return .body
        case ..<23: return .title3
        case ..<29: return .title2
        default: return .largeTitle
        }
    }
}

extension View {
    /// `.font(.system(size:weight:design:))` that follows the system text size.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular,
                    design: Font.Design = .default, maxScale: CGFloat = 1.6) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, maxScale: maxScale))
    }
}


// MARK: - The hinge (iPhone Duo, iOS 27.1+)

/// The Duo's hinge, read the whole time the app runs with Apple's
/// `onHingeChange` (180° = flat). Layout never follows the angle (Apple:
/// hinge data is for effects; layout follows size changes and the fold's
/// reserved region, see DuoPagePair.activeFold).
/// Whether this phone folds, on its own (Nov 13). Pages and the root read
/// only this; the live angle (HingeState) changes many times a second while
/// the hinge moves, and the whole app was re-rendering on every sample —
/// Apple: hinge data is for effects, layout follows size changes only.
final class HingePresence: ObservableObject {
    static let shared = HingePresence()
    @Published fileprivate(set) var hasHinge = UserDefaults.standard.bool(forKey: "deviceHasHinge")
}

final class HingeState {
    static let shared = HingeState()
    /// This phone folds (it has reported a hinge), remembered across
    /// launches. Slab iPhones never set it.
    var hasHinge: Bool { HingePresence.shared.hasHinge }

    enum Pose { case closed, partial, full, none }

    private var pose: Pose = .none
    /// When the hinge last left closed (the inner screen came on).
    private var openedAt: Date = .distantPast

    /// The inner screen has been showing for a moment. Coming from closed,
    /// the screen should already show the right layout (Settings fades in
    /// with its pages clear of the fold), so only a hinge move while the
    /// screen is showing glides.
    var settledOpen: Bool { Date().timeIntervalSince(openedAt) > 0.8 }

    /// Not observed: nothing re-renders on a sample (Apple: hinge data is
    /// for effects; layout follows size changes and reserved regions).
    func update(degrees deg: Double, pose new: Pose) {
        if new != .none, !HingePresence.shared.hasHinge {
            HingePresence.shared.hasHinge = true
            UserDefaults.standard.set(true, forKey: "deviceHasHinge")
        }
        if pose == .closed && new != .closed { openedAt = Date() }
        pose = new
    }
}

/// Attach once at the root: keeps HingeState current from 0° to 180°.
struct HingeReader: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in
                let pose: HingeState.Pose
                let deg: Double
                if let hinge = context.hinge {
                    deg = hinge.angle.degrees
                    switch hinge.status {
                    case .closed: pose = .closed
                    case .fullyOpen: pose = .full
                    default: pose = .partial
                    }
                } else {
                    // No hinge in this hierarchy: show everything as open.
                    deg = 180; pose = .none
                }
                // No animation: a sample isn't a layout change (an animated
                // transaction per sample re-animated everything watching).
                HingeState.shared.update(degrees: deg, pose: pose)
            }
        } else {
            content
        }
    }
}

extension View {
    func hingeReader() -> some View { modifier(HingeReader()) }
}

/// Hosts a view in its own small SwiftUI graph. For views that redraw
/// every frame (the rest pill's water): drawn inside the app's graph, each
/// frame made SwiftUI walk the whole app marking it changed — 22% of the
/// main thread while a rest ran, which made every other animation lag.
struct IsolatedHost<Content: View>: UIViewRepresentable {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    final class Coordinator { var host: UIHostingController<Content>? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.safeAreaRegions = []
        context.coordinator.host = host
        return host.view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.host?.rootView = content
    }
}

// MARK: - Lava-lamp liquid (rest pill, Nov 12)

/// A glass capsule filled with glowing accent-colored liquid, like a lava
/// lamp: a wavy surface that sloshes gently, soft blobs rising and
/// drifting inside, a rounded 3D shade, and a glass highlight on top. The
/// level drains smoothly from full to empty as the rest counts down to
/// zero, and everything freezes while the rest is paused.
struct LavaLiquidFill: View {
    /// When the rest ends (nil while paused).
    var endsAt: Date?
    /// Seconds left while paused.
    var pausedRemaining: TimeInterval?
    /// The full rest length — the level is remaining / total.
    var total: TimeInterval
    var color: Color

    /// The simulation lives as long as the pill does (a reference, so
    /// stepping it every frame never re-renders anything by itself).
    @State private var sim = LiquidSim()
    @State private var motionOn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Paused: the water holds still and nothing redraws (it ran at
        // full frame rate the whole pause).
        TimelineView(.animation(minimumInterval: nil, paused: endsAt == nil)) { context in
            let now = context.date
            let remaining = endsAt.map { max(0, $0.timeIntervalSince(now)) } ?? pausedRemaining ?? 0
            let level = total > 0 ? min(1, remaining / total) : 0
            Canvas { ctx, size in
                let surfaceY = size.height * (1 - level)
                // Reduce Motion: still water — the level just drains.
                if reduceMotion {
                    ctx.fill(Path(CGRect(x: 0, y: surfaceY, width: size.width, height: size.height - surfaceY)),
                             with: .color(color))
                    return
                }
                sim.step(to: now, size: size)
                // Back sheet: the far side of the water, a touch behind and
                // less tilted — gives the surface depth.
                ctx.fill(sim.surfacePath(size: size, surfaceY: surfaceY + 3, tiltScale: 0.75), with: .color(color.opacity(0.5)))
                ctx.fill(sim.surfacePath(size: size, surfaceY: surfaceY, tiltScale: 1), with: .color(color))
                // Bubbles drift slowly up through the water, like the gyro
                // water face DaRon picked. Worked out from the clock,
                // so nothing is stored between frames.
                if level > 0.02 {
                    let t = now.timeIntervalSinceReferenceDate
                    let depth = size.height - surfaceY
                    for i in 0..<6 {
                        let seed = Double(i) * 12.9898
                        let speed = 0.12 + (sin(seed) * 0.5 + 0.5) * 0.14
                        let phase = (t * speed + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
                        let x0 = (sin(seed * 1.7) * 0.5 + 0.5) * Double(size.width - 12) + 6
                        let y = Double(size.height) - phase * Double(depth + 4)
                        guard y > Double(surfaceY) + 1 else { continue }
                        let wobble = sin(t * 1.6 + seed) * 2
                        let r = 1.2 + (sin(seed * 3.1) * 0.5 + 0.5) * 1.8
                        let rect = CGRect(x: x0 + wobble - r, y: y - r, width: r * 2, height: r * 2)
                        // A hole through the water, so the pill's background
                        // shows inside it (DaRon), with a fine rim.
                        var hole = ctx
                        hole.blendMode = .clear
                        hole.fill(Path(ellipseIn: rect), with: .color(.black))
                        ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.4)), lineWidth: 0.7)
                    }
                    // (No surface pops: calm water.)
                    for i in 0..<0 {
                        let seed = Double(i) * 78.233
                        let cycle = (t * 1.3 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                        guard cycle < 0.3 else { continue }
                        let x = (sin(seed) * 0.5 + 0.5) * Double(size.width - 10) + 5
                        let r = 2 + cycle * 10
                        let rect = CGRect(x: x - r, y: Double(surfaceY) - r * 0.6, width: r * 2, height: r * 1.2)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.45 * (1 - cycle / 0.3))), lineWidth: 1)
                    }
                }
                // Spray thrown off the glass.
                for drop in sim.drops {
                    let r = drop.size / 2
                    ctx.fill(Path(ellipseIn: CGRect(x: drop.x - r, y: drop.y - r, width: drop.size, height: drop.size)),
                             with: .color(color.opacity(min(1, drop.life * 1.5))))
                }
            }
        }
        // Stop exactly what this pill started, even if Reduce Motion
        // changed in between (motion kept running).
        .onAppear { if !reduceMotion { MotionSource.shared.start(); motionOn = true } }
        .onDisappear { if motionOn { MotionSource.shared.stop(); motionOn = false } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Liquid physics (rest pill)

/// The phone's real gravity and shakes, in screen coordinates (x right,
/// y down) for the current interface orientation. Device motion needs no
/// permission prompt.
final class MotionSource {
    static let shared = MotionSource()
    private let manager = CMMotionManager()
    private var users = 0

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        // 120 Hz, to match ProMotion: the liquid reads the gyro every
        // frame instead of every other one.
        manager.deviceMotionUpdateInterval = 1.0 / 120
        manager.startDeviceMotionUpdates()
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }

    /// Gyro: how fast the phone is spinning in the plane of the screen
    /// (rad/s, + = counter-clockwise). Twisting the phone throws the water.
    func spinRate() -> Double? {
        manager.deviceMotion?.rotationRate.z
    }

    /// Effective gravity felt by the liquid: real gravity minus the
    /// phone's own acceleration (a shove to the right throws the water
    /// left, like a real cup).
    func screenGravity() -> CGVector? {
        guard let m = manager.deviceMotion else { return nil }
        let dx = m.gravity.x - m.userAcceleration.x
        let dy = m.gravity.y - m.userAcceleration.y
        let orientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation ?? .portrait
        switch orientation {
        case .landscapeLeft: return CGVector(dx: dy, dy: dx)
        case .landscapeRight: return CGVector(dx: -dy, dy: -dx)
        case .portraitUpsideDown: return CGVector(dx: -dx, dy: dy)
        default: return CGVector(dx: dx, dy: -dy)
        }
    }
}

/// A small real-time water simulation:
/// - Slosh: the surface's tilt is a damped oscillator pulled toward
///   level-with-gravity, so tilting or shoving the phone makes the water
///   swing past level, climb the far wall, and settle.
/// - Ripples: the surface is a row of spring-connected water columns
///   (the classic "water springs" model); waves run, reflect off the
///   glass, interfere, and die down on their own.
/// - Spray: when water hits a wall fast enough, drops fly off and fall
///   back under the same gravity.
final class LiquidSim {
    private let n = 20
    private var h: [Double]        // column heights (in points, + = up)
    private var v: [Double]
    private var tilt = 0.0         // surface slope (dy/dx)
    private var tiltV = 0.0
    private var last: Date?
    private var width: CGFloat = 56
    private var gravity = CGVector(dx: 0, dy: 1)
    private(set) var drops: [Drop] = []

    struct Drop { var x: CGFloat; var y: CGFloat; var vx: CGFloat; var vy: CGFloat; var size: CGFloat; var life: Double }

    init() {
        h = Array(repeating: 0, count: n)
        v = Array(repeating: 0, count: n)
    }

    func step(to now: Date, size: CGSize) {
        width = size.width
        let dt = min(1.0 / 20, max(0, now.timeIntervalSince(last ?? now)))
        last = now
        guard dt > 0 else { return }

        // Gravity: the real phone, or a gentle hand-held sway where there
        // is no motion sensor (the simulator).
        let t = now.timeIntervalSinceReferenceDate
        let g = MotionSource.shared.screenGravity()
            ?? CGVector(dx: 0.16 * sin(t * 0.9) + 0.05 * sin(t * 2.1), dy: 1)
        gravity = g
        let target = max(-1.4, min(1.4, -Double(g.dx) / max(0.25, Double(g.dy))))

        // On a real phone the water is driven only by the gyro and
        // accelerometer (DaRon: "based off gyro"): a twist of the wrist
        // spins the surface past level and it sloshes back.
        let spin = MotionSource.shared.spinRate()
        if let spin {
            // Gyro water (DaRon's video): a twist nudges the surface, but
            // it glides back level rather than rocking.
            tiltV -= spin * dt * 2
        }

        let steps = 4
        let s = dt / Double(steps)
        for _ in 0..<steps {
            // Slosh mode: under-damped, so it overshoots and rocks.
            // Natural slosh: ~1.1 s swing that settles in about two.
            // Gyro water: the surface follows real gravity with a smooth,
            // nearly critically damped glide and a tiny overshoot.
            let accel = -40 * (tilt - target) - 10.5 * tiltV
            tiltV += accel * s
            tilt += tiltV * s
            // The rocking surface throws water up the walls it swings at.
            let wallKick = tiltV * 1.2
            v[0] -= wallKick * s * 6
            v[n - 1] += wallKick * s * 6

            // Columns: each a damped spring back to the surface line.
            for i in 0..<n {
                let a = -64 * h[i] - 2.6 * v[i]
                v[i] += a * s
                h[i] += v[i] * s
            }
            // Neighbors share height — this is what makes waves travel.
            for _ in 0..<2 {
                for i in 0..<n {
                    if i > 0 { v[i - 1] += 0.32 * (h[i] - h[i - 1]) * s * 60 }
                    if i < n - 1 { v[i + 1] += 0.32 * (h[i] - h[i + 1]) * s * 60 }
                }
            }
        }

        // Spray: water leaving a wall fast throws drops.
        // (Gyro water has no splashes: spray only on a violent shake.)
        for (i, side) in [(0, 1.0), (n - 1, -1.0)] where v[i] > 400 && drops.count < 8 {
            let x: CGFloat = i == 0 ? 3 : width - 3
            drops.append(Drop(x: x, y: 0, vx: CGFloat(side) * CGFloat.random(in: 10...28),
                              vy: -CGFloat(v[i]) * CGFloat.random(in: 0.9...1.5),
                              size: CGFloat.random(in: 1.8...3.6), life: 1))
            v[i] *= 0.85
        }
        // Drops fly under the same gravity and fade.
        drops = drops.compactMap { d in
            var d = d
            d.vx += g.dx * 900 * dt
            d.vy += g.dy * 900 * dt
            d.x += d.vx * dt
            d.y += d.vy * dt
            d.life -= dt * 1.8
            return d.life > 0 ? d : nil
        }
    }

    /// Where the surface sits at column i (in points), for a resting level.
    private func surface(_ i: Int, _ size: CGSize, _ surfaceY: CGFloat, _ tiltScale: Double) -> CGFloat {
        let x = size.width * CGFloat(i) / CGFloat(n - 1)
        return surfaceY + CGFloat(tilt * tiltScale) * (x - size.width / 2) - CGFloat(h[i])
    }

    func surfacePath(size: CGSize, surfaceY: CGFloat, tiltScale: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: size.height))
        let pts = (0..<n).map { i in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(n - 1),
                    y: min(size.height, surface(i, size, surfaceY, tiltScale)))
        }
        p.addLine(to: pts[0])
        // Smooth curve through the column tops.
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i - 1])
        }
        p.addLine(to: pts[pts.count - 1])
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.closeSubpath()

        // Spray positions are relative to the wall's water line.
        if tiltScale == 1 {
            let leftY = pts[0].y, rightY = pts[pts.count - 1].y
            for k in drops.indices where drops[k].y == 0 {
                drops[k].y = drops[k].x < size.width / 2 ? leftY : rightY
            }
        }
        return p
    }
}

extension Color {
    /// Blends toward another color (0 = self, 1 = other). iOS 17-safe
    /// stand-in for Color.mix(with:by:).
    func blend(with other: Color, by amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = CGFloat(min(max(amount, 0), 1))
        return Color(red: Double(r1 + (r2 - r1) * f), green: Double(g1 + (g2 - g1) * f),
                     blue: Double(b1 + (b2 - b1) * f), opacity: Double(a1 + (a2 - a1) * f))
    }
}


// MARK: - System accessibility settings (Nov 12: "respect all system settings")

/// Frosted glass that turns solid when Reduce Transparency is on.
struct GlassFill<S: Shape>: View {
    var shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            shape.fill(Theme.card)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

extension View {
    /// The corner buttons' border: a quiet hairline normally, a strong
    /// edge when Increase Contrast is on.
    func controlBorder<S: Shape>(_ shape: S, lineWidth: CGFloat = 1.5, tint: Color? = nil) -> some View {
        modifier(ControlBorder(shape: shape, lineWidth: lineWidth, tint: tint))
    }
}

private struct ControlBorder<S: Shape>: ViewModifier {
    var shape: S
    var lineWidth: CGFloat
    var tint: Color?
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.overlay(
            shape.stroke(tint ?? (contrast == .increased ? Theme.text.opacity(0.8) : Theme.border),
                         lineWidth: contrast == .increased ? max(lineWidth, 2) : lineWidth)
        )
    }
}


/// The strip under the status bar (Nov 12): whatever scrolls up into it
/// turns black and white (DaRon: "I just want the top part of the screen
/// to turn black and white"), fading back to full color just above the
/// page titles. A grey layer with the .saturation blend mode keeps the
/// brightness of what's underneath and takes away its color; the blend
/// mode is the LAST modifier so it mixes with the page below instead of
/// inside its own layer.
/// The DS fold: a hairline with, on each side, the top bar's two
/// effects mirrored toward the line: a black-and-white strip (keeps
/// brightness, drops color) and an eased fade into the page color.
/// The line between the two pages, made draggable (DaRon): a grab band
/// along the line with a small pill in the middle. `share` is the room
/// before the line (top, or left), kept between a third and two thirds
/// of the screen. It sticks to its usual spot (`rest`) when dragged
/// close, and a double tap puts it back there.
struct DuoSplitHandle: View {
    @Binding var share: Double
    /// Screen length across the line (height for the DS fold line).
    var length: CGFloat
    /// Length of the line itself.
    var span: CGFloat
    /// true: a horizontal line (DS); false: a vertical one (side by side).
    var horizontal: Bool
    var rest: Double
    /// Called when the drag ends: the pair saves the setting then (saving
    /// every frame re-laid out every page, hidden ones too).
    var onCommit: () -> Void = {}
    /// Thickness of the touch band centred on the line.
    static let grab: CGFloat = 28
    static func clamp(_ v: Double) -> Double { min(max(v, 1.0 / 3), 2.0 / 3) }

    @State private var start: Double?
    @State private var dragging = false
    /// Where the drag last was: snapped to rest, at a limit, or free. One
    /// haptic per change, exactly when it happens (DaRon).
    @State private var zone = 0
    /// True only while a finger is down: a drag cut off by a banner,
    /// Control Center or a rotation never reaches onEnded.
    @GestureState private var pressing = false
    @State private var haptic = UIImpactFeedbackGenerator(style: .rigid)

    var body: some View {
        Color.clear
            .frame(width: horizontal ? span : Self.grab, height: horizontal ? Self.grab : span)
            .contentShape(Rectangle())
            .overlay {
                // While held: the whole line in the accent, where the split
                // will land when you let go.
                Rectangle()
                    .fill(Color.accentColor.opacity(dragging ? 0.8 : 0))
                    .frame(width: horizontal ? span : 2, height: horizontal ? 2 : span)
                    .animation(AppAnimation.quick, value: dragging)
                Capsule()
                    // Accent while held (DaRon).
                    .fill(dragging ? Color.accentColor : Theme.secondaryText.opacity(0.45))
                    .frame(width: horizontal ? (dragging ? 56 : 40) : 5,
                           height: horizontal ? 5 : (dragging ? 56 : 40))
                    .animation(AppAnimation.snappy, value: dragging)
            }
            .gesture(
                // Measured on the screen, not on the handle: the handle
                // moves with the line, so its own translation fed back on
                // itself and the line shook (DaRon).
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .updating($pressing) { _, s, _ in s = true }
                    .onChanged { value in
                        if start == nil {
                            start = share; dragging = true
                            haptic.prepare()
                            zone = abs(share - rest) < 0.0001 ? 1 : 0
                        }
                        let moved = horizontal ? value.translation.height : value.translation.width
                        let raw = (start ?? share) + moved / max(length, 1)
                        var next = Self.clamp(raw)
                        // Sticks to its usual spot when close.
                        if abs(next - rest) < 0.02 { next = rest }
                        let newZone = next == rest ? 1 : (raw <= 1.0 / 3 || raw >= 2.0 / 3 ? 2 : 0)
                        if newZone != zone {
                            // Snap in and hitting a limit: firm; leaving: light.
                            haptic.impactOccurred(intensity: newZone == 0 ? 0.45 : 1)
                            haptic.prepare()
                            zone = newZone
                        }
                        var t = Transaction(); t.animation = nil
                        withTransaction(t) { share = next }
                    }
                    .onEnded { _ in start = nil; dragging = false; onCommit() }
            )
            .onTapGesture(count: 2) {
                withAnimation(AppAnimation.snappy) { share = rest }
                onCommit()
            }
            .onChange(of: pressing) { _, down in
                if !down && start != nil { start = nil; dragging = false; onCommit() }
            }
            .onDisappear { if start != nil { start = nil; dragging = false; onCommit() } }
            .accessibilityElement()
            .accessibilityLabel("Divider")
            .accessibilityValue("\(Int((Self.clamp(share) * 100).rounded())) percent")
            .accessibilityAdjustableAction { dir in
                withAnimation(AppAnimation.snappy) {
                    share = Self.clamp(share + (dir == .increment ? 0.05 : -0.05))
                }
                onCommit()
            }
    }
}

struct FoldFade: View {
    /// Length of the line (the screen's width for the DS fold).
    var width: CGFloat
    /// A vertical line (pages side by side) instead of the DS fold.
    var vertical = false
    /// How far each effect reaches from the line.
    static let reach: CGFloat = 26

    var body: some View {
        let r = Self.reach
        // Eased stops, like StatusBarOmbre (no visible start or end).
        let ease: [Gradient.Stop] = [
            .init(color: Theme.background.opacity(0), location: 0),
            .init(color: Theme.background.opacity(0.1), location: 0.2),
            .init(color: Theme.background.opacity(0.26), location: 0.4),
            .init(color: Theme.background.opacity(0.48), location: 0.6),
            .init(color: Theme.background.opacity(0.72), location: 0.8),
            .init(color: Theme.background.opacity(0.9), location: 1),
        ]
        let w = vertical ? r * 2 : width, h = vertical ? width : r * 2
        let start: UnitPoint = vertical ? .leading : .top
        let end: UnitPoint = vertical ? .trailing : .bottom
        ZStack(alignment: .topLeading) {
            // Black and white toward the line, from both sides.
            Rectangle()
                .fill(Color(white: 0.5))
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.5),
                    .init(color: .clear, location: 1),
                ], startPoint: start, endPoint: end))
                .frame(width: w, height: h)
                .blendMode(.saturation)
            Group {
                if vertical {
                    HStack(spacing: 0) {
                        LinearGradient(stops: ease, startPoint: .leading, endPoint: .trailing)
                            .frame(width: r, height: h)
                        LinearGradient(stops: ease, startPoint: .trailing, endPoint: .leading)
                            .frame(width: r, height: h)
                    }
                } else {
                    VStack(spacing: 0) {
                        LinearGradient(stops: ease, startPoint: .top, endPoint: .bottom)
                            .frame(width: w, height: r)
                        LinearGradient(stops: ease, startPoint: .bottom, endPoint: .top)
                            .frame(width: w, height: r)
                    }
                }
            }
            Rectangle()
                .fill(Theme.border)
                .frame(width: vertical ? 0.5 : w, height: vertical ? h : 0.5)
                .offset(x: vertical ? r - 0.25 : 0, y: vertical ? 0 : r - 0.25)
        }
        .frame(width: w, height: h, alignment: .topLeading)
    }
}

struct StatusBarFade: View {
    /// The thin full-width strip along the top edge.
    var height: CGFloat = 30
    /// The status bar's own height (the safe-area top). Content passing
    /// under the clock / signal / battery cluster loses its color too
    /// (DaRon, Nov 12: "anything that goes underneath the status bar").
    var statusBarHeight: CGFloat = 0
    /// How far in from the right edge the status icons reach.
    var clusterWidth: CGFloat = 140
    /// The same strip along the bottom edge instead (DaRon).
    var bottom = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Rectangle()
                .fill(Color(white: 0.5))
                .mask(LinearGradient(colors: [.black, .clear],
                                     startPoint: bottom ? .bottom : .top, endPoint: bottom ? .top : .bottom))
                .frame(height: height)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: bottom ? .bottom : .top)
        .ignoresSafeArea(edges: bottom ? .bottom : .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Last: blend with the page beneath (keeps brightness, drops color).
        .blendMode(.saturation)
    }
}


extension View {
    /// A soft fade at the top once content scrolls under the bar, instead
    /// of the hard-edged band.
    @ViewBuilder
    func softTopEdge() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    /// Infinity-display top edge (Nov 12): content softly blurs and fades
    /// as it scrolls off the top of the screen — iOS's own soft scroll
    /// edge effect (a progressive blur with no tint, so no grey band).
    @ViewBuilder
    func infinityTopEdge() -> some View {
        // The system scroll-edge blur is OFF: on the Duo it draws as a
        // hard-edged pill around the status icons that cuts text off
        // ("tricep|s", DaRon). The app's own StatusBarOmbre fades the top.
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }
}


extension View {
    /// Real Liquid Glass for the floating buttons and the rest pill
    /// (iOS 26+), so they follow the system's Liquid Glass setting,
    /// Reduce Transparency and contrast on their own. Older iOS falls
    /// back to the frosted fill + border.
    @ViewBuilder
    func liquidGlass<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background { GlassFill(shape: shape) }
                .controlBorder(shape)
        }
    }
}


/// A strong backdrop blur with the system material's tint layers removed,
/// so it blurs what's underneath without lightening the true-black page
/// into a grey band (the tint was what made the earlier band).
struct UntintedBlur: UIViewRepresentable {
    func makeUIView(context: Context) -> UntintedBlurView { UntintedBlurView() }
    func updateUIView(_ view: UntintedBlurView, context: Context) { view.stripTint() }
}

/// A system blur with every tint, dim and saturation layer removed, kept
/// that way: the system re-adds them on layout and on light/dark changes
/// (on the phone the strip came back grey 30 instead of black), so the
/// strip is re-applied each time, not once.
final class UntintedBlurView: UIVisualEffectView {
    init() {
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        stripTint()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        stripTint()
        DispatchQueue.main.async { [weak self] in self?.stripTint() }
    }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        stripTint()
    }

    func stripTint() {
        for sub in subviews {
            let name = String(describing: type(of: sub))
            if name.contains("Backdrop") {
                // Keep only the blur itself.
                if let filters = sub.layer.filters {
                    let blur = filters.filter { String(describing: $0).lowercased().contains("blur") }
                    if !blur.isEmpty, blur.count != filters.count { sub.layer.filters = blur }
                }
                sub.backgroundColor = .clear
            } else {
                // Tint / overlay views.
                sub.backgroundColor = .clear
                sub.alpha = 0
            }
        }
    }
}

/// The hard blur under the status bar (DaRon: "black and white area needs
/// to be a hard blur"): fully blurred at the top edge, easing out by the
/// bottom of the strip. Sits under StatusBarFade (the black-and-white).
struct StatusBarBlur: View {
    var height: CGFloat = 30
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if !reduceTransparency {
                UntintedBlur()
                    .mask(LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.5),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                    .frame(height: height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The top bar (DaRon, Nov 12: "ombré from transparent to black"): solid
/// page color at the very top edge, fading to transparent at the bottom of
/// the status bar. No blur, no band — content just fades out under it.
struct StatusBarOmbre: View {
    var height: CGFloat
    /// Along the bottom edge instead (DaRon).
    var bottom = false

    var body: some View {
        // Eased (smooth-step) so there's no visible edge where it starts
        // or ends (DaRon: "too harsh at the beginning").
        LinearGradient(stops: [
            .init(color: Theme.background.opacity(0.9), location: 0),
            .init(color: Theme.background.opacity(0.72), location: 0.2),
            .init(color: Theme.background.opacity(0.48), location: 0.4),
            .init(color: Theme.background.opacity(0.26), location: 0.6),
            .init(color: Theme.background.opacity(0.1), location: 0.8),
            .init(color: Theme.background.opacity(0), location: 1),
        ], startPoint: bottom ? .bottom : .top, endPoint: bottom ? .top : .bottom)
        .frame(height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: bottom ? .bottom : .top)
        .ignoresSafeArea(edges: bottom ? .bottom : .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


/// Your photo (Settings → Profile) in a circle, or a person glyph.
struct ProfileAvatar: View {
    @ObservedObject private var identity = ProfileIdentity.shared
    var size: CGFloat
    var body: some View {
        Group {
            if let photo = identity.photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}


/// Press feedback for the side bar: a quick springy squeeze.
struct PressSqueeze: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(AppAnimation.press, value: configuration.isPressed)
    }
}


extension View {
    /// Accent button finish: real Liquid Glass tinted with the accent
    /// (the + buttons and the side bar highlight match, DaRon). The accent
    /// is the glass's own tint; glass laid over a solid accent fill tinted
    /// the whole screen blue.
    @ViewBuilder func accentGlass<S: Shape>(_ shape: S, tint: Color = .accentColor) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.background(tint, in: shape)
        }
    }
}

// MARK: - Swipe back without the bar's back button

/// The side bar hides the top-left back button, which also turned off
/// the edge swipe to go back; keep the swipe working (red team).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}


// MARK: - The Duo's system side bar

/// A main page's navigation bar. Hidden as before (the pages draw their own
/// big titles), except where iOS runs bars down the side of the Duo: there
/// the page's actions become real toolbar items, so they get the system's
/// own side bar buttons.
/// A container around both open pages carries the side bar's buttons
/// itself: the page inside keeps no bar of its own.
private struct SideBarItemsHoistedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var sideBarItemsHoisted: Bool {
        get { self[SideBarItemsHoistedKey.self] }
        set { self[SideBarItemsHoistedKey.self] = newValue }
    }
}

/// Puts the side bar's buttons on a stack around the open pair (see
/// ContentView.unfoldPage). Off: the page is left exactly as it was.
struct FixedSideBarStack: ViewModifier {
    let page: ContentView.Page
    let on: Bool
    @Environment(\.railEdge) private var edge

    func body(content: Content) -> some View {
        if on {
            NavigationStack {
                content
                    .environment(\.sideBarItemsHoisted, true)
                    // A hairline keeps both pages clear of the bar.
                    .padding(edge == .leading ? .leading : .trailing, 1)
                    .sideBarItems(page)
                    .modifier(NoBarTitle())
            }
        } else {
            content
        }
    }
}

struct SideBarItems: ViewModifier {
    let page: ContentView.Page
    @Environment(\.systemSideBar) private var sideBarOn
    @Environment(\.sideBarItemsHoisted) private var hoisted
    /// The page carries the bar's buttons itself, unless a container around
    /// it does (then the page's own bar stays hidden and unpadded).
    private var on: Bool { sideBarOn && !hoisted }
    @Environment(\.railEdge) private var edge
    @Environment(\.sideBarInset) private var inset
    @Environment(\.duoWide) private var wide
    @EnvironmentObject private var store: WorkoutStore
    @ObservedObject private var duo = DuoSettings.shared

    private var barEdge: Edge.Set { edge == .leading ? .leading : .trailing }

    func body(content: Content) -> some View {
        content
            // Clear of the side bar (iOS floats it over the page). Inside
            // the page, not around it: iOS only runs the toolbar down the
            // side when the page itself reaches that edge.
            .padding(barEdge, on && inset && page == .today ? ContentView.railWidth : 0)
            // The list pages get no inset here: iOS already keeps a list's
            // rows clear of its side bar (ours on top left the list a
            // narrow strip).
            .toolbar(on ? .visible : .hidden, for: .navigationBar)
            // Only the buttons: no bar background or hairline across the top.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                // Back for a page that shows what it opens in place (no
                // push, so iOS draws no Back of its own): Calendar's
                // Strength, Body and sessions with the Duo open.
                if on && store.canGoBack.contains(page.rawValue) {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { store.requestBack(page.rawValue) } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
                if on {
                    if page == .today {
                        ToolbarItem(placement: .primaryAction) {
                            if store.todayEditing {
                                Button { store.todayEditing = false } label: {
                                    Label("Done editing", systemImage: "checkmark")
                                }
                            } else {
                                Menu {
                                    Button("Edit", systemImage: "pencil") { store.todayEditing = true }
                                    Button("Add exercise", systemImage: "plus") { store.todayAddExercise = true }
                                    Button("Modify today", systemImage: "slider.horizontal.3") { store.todaySessionMod = true }
                                } label: {
                                    Label("Workout actions", systemImage: "plus")
                                }
                            }
                        }
                    }
                    if page == .notes {
                        ToolbarItem(placement: .primaryAction) {
                            Button { store.composeNoteRequest += 1 } label: {
                                Label("New note", systemImage: "square.and.pencil")
                            }
                        }
                    }
                    if wide && duo.showSwapButton {
                        // Its own button in the side bar (DaRon), not inside
                        // the "more" menu.
                        ToolbarItem(placement: .primaryAction) {
                            Button { store.swapSidesRequest += 1 } label: {
                                Label("Swap sides", systemImage: "arrow.left.arrow.right")
                            }
                        }
                    }
                }
            }
    }
}

/// A list's side margins, the same on every page and sheet: 16pt from
/// the edge of what you can see. Content margins are measured from the
/// list's own edge, which runs under the Duo's side bar, so each side adds
/// that side's safe area (the bar's width beside it, nothing in a sheet).
/// Without it the cards ran under the bar and were cut off flat.
struct PageListMargins: ViewModifier {
    /// Extra room on the trailing side (the open Duo's corner buttons).
    @Environment(\.pageListExtraTrailing) private var extraTrailing
    @State private var insets = EdgeInsets()

    static let margin: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .contentMargins(.leading, Self.margin + insets.leading, for: .scrollContent)
            .contentMargins(.trailing, Self.margin + insets.trailing + extraTrailing, for: .scrollContent)
            .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets = $0 }
    }
}

private struct PageListExtraTrailingKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }

extension EnvironmentValues {
    var pageListExtraTrailing: CGFloat {
        get { self[PageListExtraTrailingKey.self] }
        set { self[PageListExtraTrailingKey.self] = newValue }
    }
}

/// Open Duo pages built from two panes (Profile, Notes): a page-level
/// navigation stack that only carries the side bar's buttons. Only where
/// iOS draws the side bar; elsewhere the page is left exactly as it was.
/// The panes keep their own stacks for pushing pages inside them.
struct PageSideBarStack: ViewModifier {
    let page: ContentView.Page
    @Environment(\.systemSideBar) private var on
    @Environment(\.railEdge) private var edge

    func body(content: Content) -> some View {
        if on {
            NavigationStack {
                content
                    // Like Today's open pages: iOS insets the pages for its
                    // bar only once they stop touching that edge, so a
                    // hairline keeps both panes clear of it, either way
                    // round (the list ran under the bar after a swap).
                    .padding(edge == .leading ? .leading : .trailing, 1)
                    .sideBarItems(page)
                    // The panes' own titles rose into this bar and sat
                    // over the page's big title ("Your Program" on
                    // "Profile"): this bar shows buttons only.
                    .modifier(NoBarTitle())
            }
        } else {
            content
        }
    }
}

/// Keeps a page's title (Back labels, VoiceOver) but doesn't draw it in
/// the bar, for pages whose header card is the title.
struct NoBarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

extension View {
    func pageSideBarStack(_ page: ContentView.Page) -> some View { modifier(PageSideBarStack(page: page)) }
    func pageListMargins() -> some View { modifier(PageListMargins()) }
    func sideBarItems(_ page: ContentView.Page) -> some View { modifier(SideBarItems(page: page)) }
}
