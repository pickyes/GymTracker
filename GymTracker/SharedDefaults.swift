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

}

/// Open-Duo display choices: which side the pages sit on (the swap
/// button) and whether the swap button shows at all.
///
/// Saved to a small file of its own, written straight to disk on every
/// change (DaRon, Nov 12: "it should stay swapped no matter if you close
/// the device, close the app, power off"). UserDefaults kept the change
/// in memory and wrote it out later, so a reinstall/update or power-off
/// could bring the old value back.
final class DuoSettings: ObservableObject {
    static let shared = DuoSettings()

    @Published var swapSides: Bool { didSet { if swapSides != oldValue { save() } } }
    @Published var showSwapButton: Bool { didSet { if showSwapButton != oldValue { save() } } }

    private struct Values: Codable {
        var swapSides = false
        var showSwapButton = true
    }

    private static var fileURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedDefaults.suiteName)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("duo-display.json")
    }

    private init() {
        let values: Values
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(Values.self, from: data) {
            values = saved
        } else {
            // First run of this version: start from whatever the old
            // UserDefaults keys held, then never read them again.
            var v = Values()
            if let old = SharedDefaults.store.object(forKey: "duoSwapSides") as? Bool { v.swapSides = old }
            else if let old = UserDefaults.standard.object(forKey: "duoSwapSides") as? Bool { v.swapSides = old }
            if let old = SharedDefaults.store.object(forKey: "duoShowSwapButton") as? Bool { v.showSwapButton = old }
            values = v
        }
        swapSides = values.swapSides
        showSwapButton = values.showSwapButton
        save()
    }

    private func save() {
        let values = Values(swapSides: swapSides, showSwapButton: showSwapButton)
        guard let data = try? JSONEncoder().encode(values) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomic write: the file is either the old choice or the new one,
        // never half-written, and it is on disk when this returns.
        try? data.write(to: url, options: .atomic)
    }
}
