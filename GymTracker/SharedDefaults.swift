import Foundation

/// Shared App Group defaults for the Status app and its widget
/// extension. Compiled into BOTH targets (same pattern as
/// RestTimerActivityAttributes.swift) so the app and the extension
/// always read and write the same store.
///
/// The App Group suite; falls back to `.standard` when the group is
/// unavailable (simulator without the group, or before the group is
/// registered in the portal) so the app never loses data.
///
/// NOTE: MCP grant/token keys stay in `.standard` by design — they must
/// not be readable by the extension.
enum SharedDefaults {
    static let suiteName = "group.com.daronbarkley.GymTracker"
    static let shared: UserDefaults? = UserDefaults(suiteName: suiteName)
    static var store: UserDefaults { shared ?? .standard }

    /// Moves the open-Duo swap setting from .standard (where builds before
    /// Nov 12 kept it) into the shared store, once.
    static func carryOverSwapSetting() {
        let key = "duoSwapSides"
        guard let shared, shared.object(forKey: key) == nil,
              let old = UserDefaults.standard.object(forKey: key) else { return }
        shared.set(old, forKey: key)
        shared.synchronize()
    }
}
