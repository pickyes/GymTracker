import SwiftUI
import UIKit

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
///   frame interpolation reads as a jump. The old `AppAnimation.fold`
///   (0.45/0.85) settled in ~0.8s, longer than the physical fold, so
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
    func withKeyboardDoneToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
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


// MARK: - Hinge-driven unfold reveal (iPhone Duo, iOS 27.1+)

/// Ties a view to the physical hinge using Apple's `onHingeChange`
/// (`DeviceHinge.angle`, 180° = flat). While the phone is partly open the
/// view sits slightly dimmed and recessed; it reaches full brightness and
/// size exactly as the hinge reaches flat, so the pane revealed by the
/// unfold looks like it was already there, waiting. No layout changes —
/// only opacity/scale, so nothing moves or reflows. Devices without a
/// hinge (or iOS < 27.1) show the view as-is.
struct HingeReveal: ViewModifier {
    @State private var openness: Double = 1   // 0 = closed, 1 = flat
    /// The edge toward the hinge (the pane grows out from it).
    var anchor: UnitPoint = .trailing

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .opacity(0.25 + 0.75 * openness)
                .scaleEffect(0.96 + 0.04 * openness, anchor: anchor)
                .onHingeChange { _, context in
                    guard let hinge = context.hinge else { openness = 1; return }
                    // Map 90°…180° to 0…1: the inner screen is only really
                    // in view once the phone is past half open.
                    let t = (hinge.angle.degrees - 90) / 90
                    let next = min(max(t, 0), 1)
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 1)) {
                        openness = next
                    }
                }
        } else {
            content
        }
    }
}

/// Rises out of the dark as the Duo opens (the swap button, Nov 12):
/// invisible, blurred and a little small while the hinge is folded,
/// fully there as it reaches flat — tied to the real hinge angle, so it
/// emerges with the opening instead of popping in afterward.
struct HingeEmerge: ViewModifier {
    @State private var openness: Double = 1

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .opacity(openness * openness)
                .blur(radius: 10 * (1 - openness))
                .scaleEffect(0.8 + 0.2 * openness)
                .onHingeChange { _, context in
                    guard let hinge = context.hinge else { openness = 1; return }
                    // Starts emerging past half open (120°), clear at flat.
                    let t = (hinge.angle.degrees - 120) / 60
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 1)) {
                        openness = min(max(t, 0), 1)
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    func hingeEmerge() -> some View { modifier(HingeEmerge()) }
    func hingeReveal(anchor: UnitPoint = .trailing) -> some View { modifier(HingeReveal(anchor: anchor)) }
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

    var body: some View {
        TimelineView(.animation(paused: endsAt == nil)) { context in
            let now = context.date
            let remaining = endsAt.map { max(0, $0.timeIntervalSince(now)) } ?? pausedRemaining ?? 0
            let level = total > 0 ? min(1, remaining / total) : 0
            let t = now.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let surfaceY = h * (1 - level)
                // Slosh fades out near full/empty so the ends stay clean.
                let amp = level > 0.02 && level < 0.98 ? min(3.5, h * 0.03) : 0
                let liquid = LiquidWave(surfaceY: surfaceY, amplitude: amp, phase: t * 2.3)
                // Where the surface sits at the pill's center (for the
                // lit top face).
                let centerSurface = surfaceY + amp * CGFloat(sin(.pi + t * 2.3))
                ZStack {
                    // Glass interior: dark, deeper toward the edges.
                    Capsule()
                        .fill(RadialGradient(colors: [.white.opacity(0.06), .black.opacity(0.35)],
                                             center: .center, startRadius: 0, endRadius: w))
                    // Back wave: a darker sheet behind — depth in the slosh.
                    LiquidWave(surfaceY: surfaceY, amplitude: amp * 0.8, phase: t * 1.7 + 1.3)
                        .fill(color.blend(with: .black, by: 0.35).opacity(0.7))
                    // Main liquid: lit from the top, deep at the bottom.
                    liquid
                        .fill(LinearGradient(colors: [color.blend(with: .white, by: 0.2), color, color.blend(with: .black, by: 0.55)],
                                             startPoint: .top, endPoint: .bottom))
                    // Round-tube shading across the width: dark edges, a
                    // bright band left of center — reads as a cylinder.
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .black.opacity(0.05), location: 0.22),
                        .init(color: .white.opacity(0.28), location: 0.36),
                        .init(color: .clear, location: 0.55),
                        .init(color: .black.opacity(0.15), location: 0.78),
                        .init(color: .black.opacity(0.6), location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                    .mask(liquid)
                    // Lava blobs: shaded spheres (lit top-left, dark
                    // bottom-right) rising and drifting inside the liquid.
                    ZStack {
                        ForEach(0..<4, id: \.self) { i in
                            let k = Double(i)
                            let size = w * (0.36 + 0.1 * sin(t * 0.6 + k * 1.9))
                            let rise = (t * (0.07 + 0.025 * k) + k * 0.27).truncatingRemainder(dividingBy: 1)
                            Ellipse()
                                .fill(RadialGradient(colors: [color.blend(with: .white, by: 0.75),
                                                              color.blend(with: .white, by: 0.3),
                                                              color.blend(with: .black, by: 0.4)],
                                                     center: UnitPoint(x: 0.32, y: 0.28),
                                                     startRadius: 0, endRadius: size * 0.75))
                                .frame(width: size, height: size * (1.15 + 0.25 * sin(t * 0.9 + k)))
                                .shadow(color: .black.opacity(0.35), radius: 2, x: 1, y: 2)
                                .position(x: w / 2 + sin(t * 0.7 + k * 2.1) * w * 0.2,
                                          y: h + size / 2 - rise * (h + size))
                        }
                    }
                    .blur(radius: 0.8)
                    .mask(liquid)
                    // The liquid's top face, seen at an angle: a lit oval
                    // riding the wave — gives the surface volume.
                    if level > 0.03 && level < 0.97 {
                        Ellipse()
                            .fill(LinearGradient(colors: [color.blend(with: .white, by: 0.55), color.blend(with: .white, by: 0.15)],
                                                 startPoint: .top, endPoint: .bottom))
                            .overlay(Ellipse().stroke(color.blend(with: .white, by: 0.8).opacity(0.9), lineWidth: 0.8))
                            .frame(width: w * 0.92, height: max(5, w * 0.16))
                            .position(x: w / 2, y: centerSurface)
                    }
                    // Glass: inner shadow at the rim for thickness…
                    Capsule()
                        .strokeBorder(Color.black.opacity(0.55), lineWidth: 4)
                        .blur(radius: 3)
                    // …a sharp specular streak down the left side…
                    Capsule()
                        .fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.15), .white.opacity(0.6)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: max(3, w * 0.09), height: h * 0.72)
                        .position(x: w * 0.24, y: h / 2)
                        .blur(radius: 0.6)
                    // …and a faint reflection on the right.
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: max(2, w * 0.05), height: h * 0.5)
                        .position(x: w * 0.8, y: h * 0.42)
                        .blur(radius: 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The liquid body: everything below a gently waving surface.
struct LiquidWave: Shape {
    var surfaceY: CGFloat
    var amplitude: CGFloat
    var phase: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: y(at: 0, rect)))
        let steps = 24
        for s in 1...steps {
            let x = rect.width * CGFloat(s) / CGFloat(steps)
            p.addLine(to: CGPoint(x: x, y: y(at: x, rect)))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }

    fileprivate func y(at x: CGFloat, _ rect: CGRect) -> CGFloat {
        surfaceY + amplitude * CGFloat(sin(Double(x / max(rect.width, 1)) * .pi * 2 + phase))
    }
}

/// Just the surface line of the liquid (the meniscus highlight).
struct LiquidSurfaceLine: Shape {
    var surfaceY: CGFloat
    var amplitude: CGFloat
    var phase: Double

    func path(in rect: CGRect) -> Path {
        let wave = LiquidWave(surfaceY: surfaceY, amplitude: amplitude, phase: phase)
        var p = Path()
        let steps = 24
        for s in 0...steps {
            let x = rect.width * CGFloat(s) / CGFloat(steps)
            let pt = CGPoint(x: x, y: wave.y(at: x, rect))
            if s == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
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
