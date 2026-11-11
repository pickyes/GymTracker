import ActivityKit
import SwiftUI

/// Live Activity attributes for the rest timer (DaRon, 2026-11-09:
/// "when locked i want a live activity to be on the dynamic island and
/// lockscreen").
///
/// This file is compiled into BOTH targets — the app and the
/// GymTrackerWidgetExtension — so the app and the extension always agree
/// on the activity's shape. Keep it dependency-free: no WorkoutStore, no
/// Theme, no Settings. Everything the extension needs to draw comes
/// through ContentState.
///
/// ACCENT (DaRon, 2026-11-09, 21:45): the Live Activity uses the app's
/// ACCENT color — never a hardcoded blue. The app resolves the effective
/// accent (free users: the vivid blue; Pro users: their chosen accent)
/// and passes it in as `accentHex`; the extension renders exactly that
/// hex. When accent colors become user-interchangeable at the paid tier,
/// the app just passes the new hex on the next activity start/update —
/// the extension needs no change and no rework.
struct RestTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Exercise the rest belongs to ("DB Bench Press").
        var exerciseName: String
        /// When the countdown reaches zero. Nil while paused — the
        /// countdown is frozen at `remainingSeconds`.
        var endsAt: Date?
        /// Seconds left, running or paused. The lock screen / Dynamic
        /// Island show this when paused; while running they count down
        /// live from `endsAt`.
        var remainingSeconds: TimeInterval
        /// Full length of this rest (for the progress display).
        var totalSeconds: TimeInterval
        /// True while the countdown is frozen.
        var isPaused: Bool
        /// The app's effective accent color as "#RRGGBB" — the one shared
        /// accent source (see WorkoutStore.effectiveAccentHex). The
        /// extension renders this and nothing else for accent elements.
        var accentHex: String
        // Interactive controls (DaRon 22:27): the set checkboxes + Next
        // button in the Live Activity carry this state so taps update the
        // real workout without opening the app.
        /// The exercise's stable id (matches DraftSession's template id).
        var exerciseId: String
        /// Done flags, in order, for this exercise's sets.
        var sets: [Bool]
        /// Name of the next exercise in today's plan, or nil when this is
        /// the last one — the Next button hides when nil.
        var nextExerciseName: String?
    }
}

extension Color {
    /// Build a color from "#RRGGBB" (or "RRGGBB"). Falls back to the
    /// app's default vivid-blue accent (#0A84FF) on bad input, so a stale
    /// or malformed state still draws in the right color family.
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var rgb: UInt64 = 0
        let fallback = Color(red: 0.04, green: 0.52, blue: 1.0)
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&rgb) else {
            self = fallback
            return
        }
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }

    /// "#RRGGBB" for this color, resolved in the current trait
    /// collection — the app uses it to hand its effective accent to the
    /// Live Activity. Dynamic system colors resolve to their current
    /// light/dark values.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#0A84FF"
        }
        return String(format: "#%02X%02X%02X",
                      Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}
