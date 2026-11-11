import SwiftUI
import WidgetKit

/// The widget extension bundle. It hosts only the rest-timer Live
/// Activity — no home-screen widgets yet (DaRon, 2026-11-09: lock screen
/// + Dynamic Island for the rest timer).
@main
struct GymTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestTimerLiveActivity()
    }
}
