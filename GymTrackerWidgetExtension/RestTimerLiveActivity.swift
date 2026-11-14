import ActivityKit
import SwiftUI
import WidgetKit

/// Rest-timer Live Activity: lock screen banner + Dynamic Island
/// (DaRon, 2026-11-09: "when locked i want a live activity to be on the
/// dynamic island and lockscreen").
///
/// Shows the countdown ticking down live, the current exercise name, a
/// paused state, and the "Drink water" reminder — in the expanded
/// Dynamic Island and on the lock screen.
///
/// ACCENT (DaRon, 2026-11-09, 21:45): every accent element in this file
/// comes from `state.accentHex` — the app's effective accent, resolved
/// from the one shared accent source. There is NO hardcoded accent color
/// anywhere in the extension UI: the countdown digits, the timer/drop
/// icons, the paused badge, and the Dynamic Island keyline all read
/// `Color(hex: state.accentHex)`. When the accent becomes
/// user-interchangeable at the paid tier, the app passes the new hex and
/// this UI follows automatically, with no rework.
struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            RestTimerLockScreenView(state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            let accent = Color(hex: context.state.accentHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent)
                        Text(context.state.exerciseName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if context.state.isPaused {
                            Text("Paused")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestTimerCountdownText(state: context.state, isStale: context.isStale, style: .island)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Interactive (DaRon 22:27): set checkboxes + Next,
                        // tappable from the expanded island.
                        RestTimerSetControlsView(state: context.state)
                        HStack(spacing: 6) {
                            Image(systemName: "drop.fill")
                                .font(.caption)
                                .foregroundStyle(accent)
                            Text("Drink water")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(Int(context.state.remainingSeconds.rounded(.up)))s left")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .monospacedDigit()
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(accent)
            } compactTrailing: {
                RestTimerCountdownText(state: context.state, isStale: context.isStale, style: .compact)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
        // No .activityBackgroundTint here: ActivityConfiguration has no
        // such member in this SDK — the lock screen view draws its own
        // true-black background (see RestTimerLockScreenView), which is
        // what gives the OLED look.
    }
}

// MARK: - Lock screen

/// The lock screen banner: accent timer icon + exercise, big accent
/// countdown, "Drink water" row, paused badge.
private struct RestTimerLockScreenView: View {
    let state: RestTimerAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let accent = Color(hex: state.accentHex)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.headline)
                    .foregroundStyle(accent)
                Text("Rest")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("·")
                    .foregroundStyle(.white.opacity(0.6))
                Text(state.exerciseName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if state.isPaused {
                    Text("PAUSED")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accent.opacity(0.18)))
                }
            }
            RestTimerCountdownText(state: state, isStale: isStale, style: .lock)
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.subheadline)
                    .foregroundStyle(accent)
                Text("Drink water")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(state.remainingSeconds.rounded(.up)))s of \(Int(state.totalSeconds.rounded()))s")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .monospacedDigit()
            }
            // Interactive (DaRon 22:27): check set boxes + move to the
            // next exercise without opening the app.
            RestTimerSetControlsView(state: state)
        }
        .padding()
        // OLED: true black behind the lock screen activity, matching the
        // app (the system clips the activity to its rounded container).
        .background(Color.black)
    }
}

// MARK: - Interactive set controls (DaRon 22:27)

/// Set checkboxes + Next button, tappable from the lock screen and the
/// expanded Dynamic Island without opening the app. Each button runs an
/// AppIntent (GymTracker/LiveActivityIntents.swift) that updates the real
/// workout draft and refreshes the activity. Buttons use
/// .buttonStyle(.plain) so the activity's own styling shows through.
/// The checked state is green (done) vs the accent (todo) — the accent
/// itself is never hardcoded; it comes from state.accentHex.
private struct RestTimerSetControlsView: View {
    let state: RestTimerAttributes.ContentState

    var body: some View {
        let accent = Color(hex: state.accentHex)
        HStack(spacing: 10) {
            ForEach(state.sets.indices, id: \.self) { i in
                Button(intent: ToggleSetIntent(exerciseId: state.exerciseId, setIndex: i)) {
                    Image(systemName: state.sets[i] ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(state.sets[i] ? Color.green : accent)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if let next = state.nextExerciseName {
                Button(intent: NextExerciseIntent(exerciseId: state.exerciseId)) {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Countdown text (accent-colored, live-ticking when running)

/// The countdown, always in the accent color. While running it counts
/// down live from `endsAt`; while paused it shows the frozen remaining
/// seconds as static text; once the rest is over it shows 0:00.
private struct RestTimerCountdownText: View {
    let state: RestTimerAttributes.ContentState
    /// The activity's `isStale`: the app sets the stale date to the end
    /// of the rest, so a stale activity is a finished rest.
    let isStale: Bool
    let style: Style

    enum Style {
        case compact
        case island
        case lock
    }

    var body: some View {
        let accent = Color(hex: state.accentHex)
        let now = Date()
        Group {
            if state.isPaused || state.endsAt == nil {
                Text(formatted(state.remainingSeconds))
            } else if let endsAt = state.endsAt, endsAt > now, !isStale {
                Text(timerInterval: now...endsAt, countsDown: true)
            } else {
                // The rest is over. An end time already in the past is
                // normal here (the stale-date re-render, a lock-screen
                // intent pushing the stored end), and `now...endsAt`
                // would then be a reversed range, which traps.
                Text(formatted(0))
            }
        }
        .font(font)
        .foregroundStyle(accent)
        .monospacedDigit()
    }

    private var font: Font {
        switch style {
        case .compact:
            return .system(.callout, design: .rounded).bold()
        case .island:
            return .system(.title2, design: .rounded).bold()
        case .lock:
            return .system(.largeTitle, design: .rounded).bold()
        }
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
