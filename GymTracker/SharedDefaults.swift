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
    /// Status bar down the side of the screen (the system's vertical bar),
    /// with the corner buttons in that rail, instead of across the top.
    @Published var sideStatusBar: Bool { didSet { if sideStatusBar != oldValue { save() } } }
    /// With the side status bar: keep its dark grey strip (a real side
    /// bar the pages stop at). Off: pages run under the status bar.
    @Published var sideStrip: Bool { didSet { if sideStrip != oldValue { save() } } }
    /// A light accent-color tint on the side bar.
    @Published var sideTint: Bool { didSet { if sideTint != oldValue { save() } } }
    /// Pages (`ContentView.Page` raw values) showing one page, not a pair,
    /// on the open Duo right now, like the rest-day Today. There is
    /// nothing to swap there, so the swap button stays away. Not saved.
    @Published var singlePages: Set<String> = []

    private struct Values: Codable {
        var swapSides = false
        var showSwapButton = true
        /// Optional: files saved before this setting existed lack it.
        var sideStatusBar: Bool? = nil
        var sideStrip: Bool? = nil
        var sideTint: Bool? = nil
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
        sideStatusBar = values.sideStatusBar ?? false
        sideStrip = values.sideStrip ?? true
        sideTint = values.sideTint ?? true
        save()
    }

    private func save() {
        let values = Values(swapSides: swapSides, showSwapButton: showSwapButton, sideStatusBar: sideStatusBar, sideStrip: sideStrip, sideTint: sideTint)
        guard let data = try? JSONEncoder().encode(values) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomic write: the file is either the old choice or the new one,
        // never half-written, and it is on disk when this returns.
        try? data.write(to: url, options: .atomic)
    }
}

import UIKit

/// The name and photo shown in the side bar (Settings → Profile).
/// Saved in the shared app container: name in a small JSON file, the
/// photo as a JPEG beside it.
final class ProfileIdentity: ObservableObject {
    static let shared = ProfileIdentity()

    @Published var name: String { didSet { if name != oldValue { saveName() } } }
    @Published private(set) var photo: UIImage? { didSet { tabIcon = Self.roundIcon(photo) } }
    /// The photo as a small round icon in its own colours, for the Profile
    /// button in the side bars (DaRon: the profile icon is your picture).
    @Published private(set) var tabIcon: UIImage?

    private static func roundIcon(_ image: UIImage?, side: CGFloat = 28) -> UIImage? {
        guard let image else { return nil }
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            let scale = max(side / image.size.width, side / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }.withRenderingMode(.alwaysOriginal)
    }

    private static var folder: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedDefaults.suiteName)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
    private static var nameURL: URL { folder.appendingPathComponent("profile-name.json") }
    private static var photoURL: URL { folder.appendingPathComponent("profile-photo.jpg") }

    private init() {
        name = (try? JSONDecoder().decode(String.self, from: Data(contentsOf: Self.nameURL))) ?? ""
        photo = (try? Data(contentsOf: Self.photoURL)).flatMap(UIImage.init(data:))
        tabIcon = Self.roundIcon(photo)
    }

    /// Sets (or clears, with nil) the photo; stored as a small square JPEG.
    func setPhoto(_ image: UIImage?) {
        guard let image else {
            photo = nil
            try? FileManager.default.removeItem(at: Self.photoURL)
            return
        }
        let side: CGFloat = 256
        let scale = side / min(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        photo = square
        if let data = square.jpegData(compressionQuality: 0.85) {
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try? data.write(to: Self.photoURL, options: .atomic)
        }
    }

    private func saveName() {
        guard let data = try? JSONEncoder().encode(name) else { return }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? data.write(to: Self.nameURL, options: .atomic)
    }
}
