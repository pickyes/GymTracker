import EventKit
import SwiftUI
import UIKit

// MARK: - Apple Calendar integration (opt-in, on-device only)

/// Syncs the active program's planned workout days to Apple Calendar,
/// using EventKit. Opt-in, off by default, nothing leaves the device:
/// the app only writes its own workout events into the user's own
/// calendar — it never reads the user's other events and never sends
/// anything anywhere.
///
/// How it works:
/// - Access is WRITE-ONLY (the least privilege that does the job):
///   the app can add events and read back the ones it created, nothing
///   else. The permission prompt says exactly that.
/// - Events go in a dedicated "Status" calendar when one can be
///   created, so they never mix into the user's personal calendar.
///   If creating one fails, they fall back to the default calendar.
/// - Events are all-day (the app stores no workout time, so no time is
///   invented): title is the day's plan ("Legs — Status"), notes
///   list the exercises with sets × reps, location is the active gym
///   profile's name when the user has one — otherwise blank.
/// - Sync window is today through 28 days out. When the plan changes
///   (new program, day swapped, day dropped), future events are updated
///   or removed so the calendar never goes stale. Past events are left
///   alone — a completed workout stays as it was logged.
/// - Event identifiers are stored in UserDefaults keyed by date, so
///   each day's event can be found again for update/removal even
///   without full calendar access.
@MainActor
final class CalendarSyncManager: ObservableObject {

    /// Sync window: today through this many days out (4 weeks).
    static let syncWindowDays = 28
    /// The dedicated calendar's title.
    static let calendarTitle = "Status"
    /// Footer line at the end of every event's notes — also the marker
    /// the predicate fallback uses to recognise our own events.
    static let notesFooter = "Planned by Status"

    /// The integration is on (permission granted and syncing).
    @Published private(set) var isEnabled: Bool = false
    /// The current EventKit authorization state.
    @Published private(set) var authorization: EKAuthorizationStatus = .notDetermined
    /// True when the user denied (or the system restricted) calendar
    /// access — the Settings toggle shows where to turn it back on.
    @Published private(set) var accessDenied: Bool = false
    /// Planned workout events currently in the calendar (today onward).
    @Published private(set) var syncedEventCount: Int = 0
    /// Last time a sync ran.
    @Published private(set) var lastSync: Date?

    private let eventStore = EKEventStore()

    private let enabledKey = "gymtracker.calendarSync.enabled.v1"
    private let calendarIDKey = "gymtracker.calendarSync.calendarIdentifier.v1"
    private let eventIDsKey = "gymtracker.calendarSync.eventIdentifiers.v1"

    init() {
        isEnabled = SharedDefaults.store.bool(forKey: enabledKey)
        refreshAuthorization()
        syncedEventCount = upcomingCount(from: loadEventIDs())
    }

    // MARK: - Enable / disable

    /// Turn the integration on or off. Turning on requests write-only
    /// calendar access; if the user denies it, the toggle stays off and
    /// `accessDenied` is set so Settings can point at system Settings.
    /// Turning off stops new events; the events already added stay
    /// until the user chooses to remove them (Settings offers that).
    func setEnabled(_ enabled: Bool, store: WorkoutStore) async {
        if enabled {
            refreshAuthorization()
            if authorization == .notDetermined {
                do {
                    let granted = try await eventStore.requestWriteOnlyAccessToEvents()
                    refreshAuthorization()
                    guard granted else {
                        accessDenied = true
                        return
                    }
                } catch {
                    accessDenied = true
                    return
                }
            }
            guard authorization == .writeOnly || authorization == .fullAccess else {
                accessDenied = true
                return
            }
            isEnabled = true
            SharedDefaults.store.set(true, forKey: enabledKey)
            await sync(store: store)
        } else {
            isEnabled = false
            SharedDefaults.store.set(false, forKey: enabledKey)
        }
    }

    /// Sync now, but only when the integration is on and access is
    /// granted. Called when the app comes to the foreground and when
    /// the active or generated program changes.
    func syncIfEnabled(store: WorkoutStore) async {
        guard isEnabled else { return }
        await sync(store: store)
    }

    /// Remove every event the app added to the calendar (past and
    /// future) and forget their identifiers. Returns how many were
    /// removed. Offered when the user turns the integration off.
    @discardableResult
    func removeAllEvents() async -> Int {
        var removed = 0
        var eventIDs = loadEventIDs()
        for (key, eventID) in eventIDs {
            if let event = eventStore.event(withIdentifier: eventID) {
                do {
                    try eventStore.remove(event, span: .thisEvent)
                    removed += 1
                } catch {
                    // The event is gone or can't be removed — forget it
                    // either way so the map doesn't grow stale entries.
                }
            }
            eventIDs.removeValue(forKey: key)
        }
        saveEventIDs(eventIDs)
        syncedEventCount = 0
        return removed
    }

    /// Open the app's page in system Settings (used when access was
    /// denied, so the user can turn Calendars back on).
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Sync

    func sync(store: WorkoutStore) async {
        guard isEnabled else { return }
        refreshAuthorization()
        guard authorization == .writeOnly || authorization == .fullAccess else { return }
        guard let targetCalendar = resolveCalendar() else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayKey = Self.dateKey(for: today)

        // The desired events: one per planned training day in the window.
        var desired: [String: (date: Date, plan: DayPlan)] = [:]
        for offset in 0..<Self.syncWindowDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today),
                  let plan = store.programDay(for: date) else { continue }
            desired[Self.dateKey(for: date)] = (date, plan)
        }

        var eventIDs = loadEventIDs()
        let location = activeGymName(in: store)

        // 1. Future events whose day is no longer planned (day swapped
        // to rest, program changed) are removed so nothing goes stale.
        // Past events are never touched.
        for (key, eventID) in eventIDs where key >= todayKey && desired[key] == nil {
            if let event = eventStore.event(withIdentifier: eventID) {
                try? eventStore.remove(event, span: .thisEvent)
            }
            eventIDs.removeValue(forKey: key)
        }

        // 2. Create or update one event per planned day.
        for (key, entry) in desired {
            let title = "\(entry.plan.title) — Status"
            let notes = Self.notes(for: entry.plan, store: store)
            if let eventID = eventIDs[key],
               let event = eventStore.event(withIdentifier: eventID) {
                if needsUpdate(event, title: title, notes: notes,
                               location: location, calendar: targetCalendar, date: entry.date) {
                    apply(to: event, title: title, notes: notes,
                          location: location, calendar: targetCalendar, date: entry.date)
                    try? eventStore.save(event, span: .thisEvent)
                }
                eventIDs[key] = event.eventIdentifier
            } else if let existing = findExisting(on: entry.date, title: title, in: targetCalendar) {
                // Identifier lookup missed (e.g. the event was moved) —
                // the predicate search found our event for this day.
                apply(to: existing, title: title, notes: notes,
                      location: location, calendar: targetCalendar, date: entry.date)
                try? eventStore.save(existing, span: .thisEvent)
                eventIDs[key] = existing.eventIdentifier
            } else {
                let event = EKEvent(eventStore: eventStore)
                apply(to: event, title: title, notes: notes,
                      location: location, calendar: targetCalendar, date: entry.date)
                do {
                    try eventStore.save(event, span: .thisEvent)
                    eventIDs[key] = event.eventIdentifier
                } catch {
                    // Save failed (calendar deleted, store busy) — the
                    // next sync retries; nothing is recorded as synced.
                }
            }
        }

        // 3. Drop stored identifiers for past days whose event is gone
        // (deleted by the user in Calendar). Past events that still
        // exist keep their identifier so "remove all" can find them.
        for (key, eventID) in eventIDs where key < todayKey {
            if eventStore.event(withIdentifier: eventID) == nil {
                eventIDs.removeValue(forKey: key)
            }
        }

        saveEventIDs(eventIDs)
        syncedEventCount = upcomingCount(from: eventIDs)
        lastSync = Date()
    }

    // MARK: - Calendar resolution

    /// The calendar events go in: the dedicated "Status" calendar
    /// when it exists (or can be created), else the default calendar.
    private func resolveCalendar() -> EKCalendar? {
        if let id = SharedDefaults.store.string(forKey: calendarIDKey),
           let existing = eventStore.calendar(withIdentifier: id) {
            return existing
        }
        if let byTitle = eventStore.calendars(for: .event).first(where: { $0.title == Self.calendarTitle }) {
            SharedDefaults.store.set(byTitle.calendarIdentifier, forKey: calendarIDKey)
            return byTitle
        }
        if let created = createDedicatedCalendar() {
            SharedDefaults.store.set(created.calendarIdentifier, forKey: calendarIDKey)
            return created
        }
        return eventStore.defaultCalendarForNewEvents
    }

    private func createDedicatedCalendar() -> EKCalendar? {
        guard let source = eventStore.defaultCalendarForNewEvents?.source
            ?? eventStore.sources.first(where: { $0.sourceType == .calDAV })
            ?? eventStore.sources.first(where: { $0.sourceType == .local })
            ?? eventStore.sources.first else { return nil }
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = Self.calendarTitle
        calendar.source = source
        calendar.cgColor = CGColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        do {
            try eventStore.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            // Write-only access may refuse calendar creation — the
            // caller falls back to the default calendar.
            return nil
        }
    }

    // MARK: - Event content

    /// The notes for a planned day: one line per exercise with sets ×
    /// reps (and the planned weight when there is one), the finisher,
    /// and the footer line that marks the event as ours.
    static func notes(for plan: DayPlan, store: WorkoutStore) -> String {
        var lines: [String] = plan.exercises.map { exercise in
            var line = "• \(exercise.name) — \(exercise.sets) × \(exercise.repRange)"
            if let weightLb = exercise.defaultWeightLb {
                line += " (\(store.displayWeightLabel(weightLb, isPair: exercise.isPair, for: exercise)))"
            }
            return line
        }
        if !plan.finisher.isEmpty {
            lines.append("Finisher: \(plan.finisher.joined(separator: "; "))")
        }
        lines.append(notesFooter)
        return lines.joined(separator: "\n")
    }

    /// The active gym profile's name, when the user has one — otherwise
    /// nil, so the event location stays blank. Never invented.
    private func activeGymName(in store: WorkoutStore) -> String? {
        guard let id = store.activeGymProfileID else { return nil }
        return store.gymProfiles.first(where: { $0.id == id })?.name
    }

    /// Whether an existing event differs from what the plan says now.
    private func needsUpdate(_ event: EKEvent, title: String, notes: String,
                             location: String?, calendar: EKCalendar, date: Date) -> Bool {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: date)
        return event.title != title
            || event.notes != notes
            || event.location != location
            || event.calendar.calendarIdentifier != calendar.calendarIdentifier
            || !event.isAllDay
            || event.startDate != date
            || event.endDate != end
    }

    /// Fill in an event from the plan. All-day: the app stores no
    /// workout time, so none is invented.
    private func apply(to event: EKEvent, title: String, notes: String,
                       location: String?, calendar: EKCalendar, date: Date) {
        event.title = title
        event.notes = notes
        event.location = location
        event.isAllDay = true
        event.startDate = date
        event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: date)
        event.calendar = calendar
    }

    /// Predicate fallback: find our event for a day when the stored
    /// identifier no longer resolves. Under write-only access the
    /// predicate only returns events the app created, so a title +
    /// footer match is ours.
    private func findExisting(on date: Date, title: String, in calendar: EKCalendar) -> EKEvent? {
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: date) else { return nil }
        let predicate = eventStore.predicateForEvents(withStart: date, end: end, calendars: [calendar])
        return eventStore.events(matching: predicate).first {
            $0.title == title && ($0.notes ?? "").contains(Self.notesFooter)
        }
    }

    // MARK: - Stored state

    private func refreshAuthorization() {
        authorization = EKEventStore.authorizationStatus(for: .event)
        accessDenied = authorization == .denied || authorization == .restricted
    }

    private func loadEventIDs() -> [String: String] {
        SharedDefaults.store.dictionary(forKey: eventIDsKey) as? [String: String] ?? [:]
    }

    private func saveEventIDs(_ eventIDs: [String: String]) {
        SharedDefaults.store.set(eventIDs, forKey: eventIDsKey)
    }

    private func upcomingCount(from eventIDs: [String: String]) -> Int {
        let todayKey = Self.dateKey(for: Date())
        return eventIDs.keys.filter { $0 >= todayKey }.count
    }

    /// "yyyy-MM-dd" in the current time zone — the map key for a day.
    static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter.string(from: Calendar.current.startOfDay(for: date))
    }
}
