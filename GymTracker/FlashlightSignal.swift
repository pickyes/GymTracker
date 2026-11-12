import AVFoundation
import Combine
import UIKit

// MARK: - Flashlight Morse "STATUS" (opt-in, off by default)
//
// DaRon (2026-11-10): when the rest timer goes off, the phone's
// flashlight may flash the word STATUS in Morse code, ONCE — like a
// boat flashing SOS. This is ADDITIVE only: it never replaces the
// rest timer's sound / haptic / Live Activity alerts.
//
// The flash is the REAR camera's LED: torch mode on
// `AVCaptureDevice.default(for: .video)` — the back camera, the same
// physical LED as the camera flash (DaRon, 2026-11-10: "the camera
// flashes btw"). Never the screen, never the front camera.
//
// Honest limits (do not weaken these):
// - iOS cannot toggle the torch from the background. The flash fires
//   ONLY while the app is in the foreground (applicationState == .active
//   is checked before every on/off toggle). Backgrounded, the normal
//   alerts still fire — just without the flash.
// - The torch needs camera authorization (AVCaptureDevice). Turning the
//   toggle on requests it; if denied, the toggle stays off and Settings
//   points at system Settings.
// - No torch (simulator, iPad, no-torch device) is a silent no-op,
//   never a crash.
//
// Timing (standard Morse, 1 unit = 100 ms — 50% faster than the
// original 150 ms, DaRon Nov 12; the whole word now takes ~4.3 s):
// - dot = 1 unit on (100 ms), dash = 3 units on (300 ms)
// - gap between elements inside one letter = 1 unit off (100 ms)
// - gap between letters = 3 units off (300 ms)
// - gap between words = 7 units off (700 ms; STATUS is one word, so
//   it never fires here — the table supports it for reuse)
// - STATUS = S ... / T - / A .- / T - / U ..- / S ...
//   = 21 on-units + 22 off-units = 43 units = 43 x 100 ms = 4,300 ms.

// MARK: - Pure Morse timeline (no torch, no UIKit — testable anywhere)

/// One torch segment: on or off for `durationMs` milliseconds.
struct MorseElement: Equatable {
    let on: Bool
    let durationMs: Int
}

enum MorseSignal {
    /// One Morse unit, in milliseconds. Dot = 1 unit, dash = 3 units.
    static let unitMs = 100

    /// The word the rest timer flashes. Fixed — the toggle is "flash
    /// STATUS", not a free-text Morse sender.
    static let statusWord = "STATUS"

    /// Standard International Morse code (A–Z, 0–9). "." = dot, "-" = dash.
    static let morseTable: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
        "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
        "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
        "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
        "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
        "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--",
        "4": "....-", "5": ".....", "6": "-....", "7": "--...",
        "8": "---..", "9": "----.",
    ]

    /// The on/off timeline for `word`: the exact torch segments, in
    /// order, with no trailing off-segment after the last element.
    /// Unknown characters are skipped; letters are uppercased.
    static func timeline(for word: String, unitMs: Int = Self.unitMs) -> [MorseElement] {
        let words = word.uppercased().split(separator: " ").map { Array($0) }
        var segments: [MorseElement] = []
        for (wordIndex, letters) in words.enumerated() {
            if wordIndex > 0, segments.last?.on == true {
                segments.append(MorseElement(on: false, durationMs: 7 * unitMs))
            }
            for (letterIndex, letter) in letters.enumerated() {
                guard let code = morseTable[letter] else { continue }
                if letterIndex > 0, segments.last?.on == true {
                    segments.append(MorseElement(on: false, durationMs: 3 * unitMs))
                }
                for (elementIndex, symbol) in code.enumerated() {
                    if elementIndex > 0 {
                        segments.append(MorseElement(on: false, durationMs: 1 * unitMs))
                    }
                    segments.append(MorseElement(on: true, durationMs: (symbol == "-" ? 3 : 1) * unitMs))
                }
            }
        }
        return segments
    }

    /// Total Morse units in `word` (on + off), for the timing check.
    /// STATUS = 43 units.
    static func totalUnits(for word: String, unitMs: Int = Self.unitMs) -> Int {
        timeline(for: word, unitMs: unitMs).reduce(0) { $0 + $1.durationMs / unitMs }
    }

    /// Total wall-clock duration of `word`, in milliseconds.
    /// STATUS = 4,300 ms at 100 ms/unit.
    static func totalDurationMs(for word: String, unitMs: Int = Self.unitMs) -> Int {
        timeline(for: word, unitMs: unitMs).reduce(0) { $0 + $1.durationMs }
    }

    /// One-line log of the timeline, for the simulator check (no torch
    /// on the simulator — this is what the coordinator prints instead):
    /// "ON 100ms, OFF 100ms, ON 100ms, ...".
    static func timelineDescription(for word: String, unitMs: Int = Self.unitMs) -> String {
        timeline(for: word, unitMs: unitMs)
            .map { "\($0.on ? "ON" : "OFF") \($0.durationMs)ms" }
            .joined(separator: ", ")
    }

    /// "STATUS: 43 units, 4300 ms (ON 2100 ms / OFF 2200 ms)".
    static func summary(for word: String, unitMs: Int = Self.unitMs) -> String {
        let segments = timeline(for: word, unitMs: unitMs)
        let onMs = segments.filter(\.on).reduce(0) { $0 + $1.durationMs }
        let offMs = segments.filter { !$0.on }.reduce(0) { $0 + $1.durationMs }
        return "\(word): \(totalUnits(for: word, unitMs: unitMs)) units, " +
            "\(totalDurationMs(for: word, unitMs: unitMs)) ms " +
            "(ON \(onMs) ms / OFF \(offMs) ms)"
    }
}

// MARK: - Torch driver (permission + foreground gate + torch restore)

/// Owns the flashlight signal: camera authorization, the Settings
/// toggle handshake, and the torch itself. A @MainActor singleton —
/// no GymTrackerApp wiring needed; Settings observes it and
/// WorkoutStore calls it. Mirrors CalendarSyncManager's permission
/// pattern (request on enable, `accessDenied` drives the Settings
/// message + Open Settings button).
@MainActor
final class FlashlightSignal: ObservableObject {
    static let shared = FlashlightSignal()

    /// The word flashed when a rest ends.
    static let statusWord = MorseSignal.statusWord

    /// True when the user denied (or the system restricted) camera
    /// access — the Settings toggle shows where to turn it back on,
    /// and the toggle itself stays off.
    @Published private(set) var accessDenied: Bool = false
    /// The current camera authorization state.
    @Published private(set) var authorization: AVAuthorizationStatus = .notDetermined

    private var flashTask: Task<Void, Never>?
    /// Identifies the in-flight flash run. A superseded run's deferred
    /// torch-off must not touch a newer run's torch state.
    private var currentRunID = UUID()
    private var resignObserver: NSObjectProtocol?

    private init() {
        refreshAuthorization()
        // App leaving the foreground mid-flash: stop at once. The
        // cancelled task's defer restores the torch to OFF.
        resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    // No deinit: this is an app-lifetime singleton, so the
    // willResignActive observer lives as long as the app does.
    // (A deinit here would also touch @MainActor state from a
    // nonisolated context.)

    // MARK: - Authorization / toggle handshake

    func refreshAuthorization() {
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        accessDenied = authorization == .denied || authorization == .restricted
    }

    /// Turn the signal on or off. Turning on requests camera access
    /// when undecided; if the user denies it, the setting stays off
    /// and `accessDenied` is set so Settings can point at system
    /// Settings. Turning off cancels any flash in flight.
    func setEnabled(_ enabled: Bool, store: WorkoutStore) async {
        if !enabled {
            cancel()
            var s = store.settings
            s.restFlashlightEnabled = false
            store.updateSettings(s)
            return
        }
        refreshAuthorization()
        if authorization == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            refreshAuthorization()
            guard granted else {
                accessDenied = true
                var s = store.settings
                s.restFlashlightEnabled = false
                store.updateSettings(s)
                return
            }
        }
        guard authorization == .authorized else {
            accessDenied = true
            var s = store.settings
            s.restFlashlightEnabled = false
            store.updateSettings(s)
            return
        }
        accessDenied = false
        var s = store.settings
        s.restFlashlightEnabled = true
        store.updateSettings(s)
    }

    /// Open the app's page in system Settings (used when access was
    /// denied, so the user can turn the Camera back on).
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Flash

    /// Flash `word` in Morse on the torch, ONCE. Cancels any flash
    /// already running, so a new rest timer never leaves a stale
    /// sequence going. No-op when camera access is not authorized,
    /// when there is no torch (simulator, iPad), or when the app is
    /// not in the foreground. The torch is always left OFF — on
    /// completion, on cancellation, and if the app backgrounds
    /// mid-flash (foreground state is re-checked before every toggle).
    func flash(word: String) {
        cancel()
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        guard UIApplication.shared.applicationState == .active else { return }
        let segments = MorseSignal.timeline(for: word)
        let runID = UUID()
        currentRunID = runID
        flashTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                // Only the current run restores the torch — a superseded
                // run must not switch off a newer run's flash.
                if runID == self.currentRunID {
                    self.setTorch(false)
                }
            }
            for segment in segments {
                guard !Task.isCancelled else { return }
                // Foreground gate, checked before EVERY toggle: if the
                // app left the foreground mid-flash, stop and restore
                // the torch to OFF via the defer above.
                guard UIApplication.shared.applicationState == .active else { return }
                guard runID == self.currentRunID else { return }
                // A torch that can't be locked aborts the sequence
                // cleanly — no partial flash, torch left OFF.
                guard self.setTorch(segment.on) else { return }
                try? await Task.sleep(for: .milliseconds(segment.durationMs))
            }
        }
    }

    /// Stop any flash in flight. The cancelled task's defer restores
    /// the torch to OFF — turning it off here as well would race it.
    /// NOTE: do NOT rotate `currentRunID` here. The run ID only changes
    /// when a new flash starts (`flash(word:)`); rotating it on cancel
    /// would make the cancelled run's defer skip its torch-off and
    /// leave the torch ON.
    func cancel() {
        flashTask?.cancel()
        flashTask = nil
    }

    // MARK: - Torch

    /// Set the torch on or off. False when there is no torch or the
    /// device can't be locked — the caller aborts the sequence.
    @discardableResult
    private func setTorch(_ on: Bool) -> Bool {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if on {
                try device.setTorchModeOn(level: 1.0)
            } else {
                device.torchMode = .off
            }
            return true
        } catch {
            return false
        }
    }
}
