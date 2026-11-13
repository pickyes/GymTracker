import SwiftUI
import UserNotifications
import PhotosUI

// MARK: - Settings (P1/P2 customization, on-device only)

struct SettingsView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var subscription: SubscriptionState
    @EnvironmentObject var calendarSync: CalendarSyncManager
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var flashlightSignal = FlashlightSignal.shared
    @State private var showPaywall = false
    @State private var showRemoveCalendarEvents = false
    /// D40 (2026-11-10): confirmation text shown after "Schedule
    /// reminders now" is tapped — the button used to give no feedback.
    @State private var remindersScheduledMessage: String?
    /// Show the swap-sides button on the open Duo (Nov 12). Saved with the
    /// swap itself, straight to disk, so it survives updates and power-off.
    @ObservedObject private var duo = DuoSettings.shared
    @ObservedObject private var identity = ProfileIdentity.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingSample: SampleProfile?
    /// Extra sections at the end (Profile puts Privacy & About here).
    var trailingSections: AnyView? = nil
    /// Sections at the top (Profile puts its header card here).
    var leadingSections: AnyView? = nil

    var body: some View {
        Form {
            if let leadingSections { leadingSections }
            Section {
                ForEach(SampleProfile.allCases) { profile in
                    Button("Load \(profile.label)") { pendingSample = profile }
                }
                if store.hasSampleBackup {
                    Button("Restore my real data") { store.restoreRealHistory() }
                }
            } header: {
                Text("Test data")
            } footer: {
                Text("Fills the app with a simulated training history to try it with lots of data. Your real workouts are kept safe and come back with Restore.")
            }
            .confirmationDialog("Replace the history with \(pendingSample?.label ?? "")?",
                                isPresented: Binding(get: { pendingSample != nil }, set: { if !$0 { pendingSample = nil } }),
                                titleVisibility: .visible) {
                Button("Load sample data") {
                    if let p = pendingSample { store.loadSampleHistory(p) }
                    pendingSample = nil
                }
                Button("Cancel", role: .cancel) { pendingSample = nil }
            }
            Section("Rest timer") {
                HStack {
                    Text("Default rest")
                    Spacer()
                    // Bounded stepper (DaRon 2026-11-10 08:54: the native
                    // stepper's + side ran off the right edge, with a
                    // heavy black divider and flat muddy gray). Same
                    // 60 s floor, same 15 s step, same binding — layout
                    // only, so the value still saves exactly as before.
                    RowStepper(value: restDefaultBinding, range: 60...300, step: 15) { "\(Int($0))s" }
                }
                Toggle("Sound when rest ends", isOn: soundBinding)
                Toggle("Haptic when rest ends", isOn: hapticBinding)
                Toggle("Flashlight flashes STATUS in Morse when rest ends", isOn: flashlightBinding)
                if flashlightSignal.accessDenied {
                    Text("Flashlight access is off. Turn it on in Settings → Privacy & Security → Camera → Status, then turn this back on.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Open Settings") { flashlightSignal.openSystemSettings() }
                } else {
                    Text("When a rest ends, the flashlight flashes STATUS in Morse code once. It flashes the light repeatedly — avoid it if flashing lights bother you. Only works while the app is open.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text("Per-exercise rest is set on the exercise itself (Today → Options).")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("Units") {
                Picker("Weight unit", selection: unitBinding) {
                    ForEach(WeightUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                Text("Weights are stored in lb and shown in your unit. Per-exercise overrides are set on the exercise (Today → Options).")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("Comfort") {
                Toggle("Haptics", isOn: hapticsBinding)
                Toggle("Keep screen awake during workouts", isOn: keepAwakeBinding)
            }

            Section {
                Toggle("Swap button", isOn: $duo.showSwapButton)
                Toggle("Status bar on the side", isOn: $duo.sideStatusBar)
                if duo.sideStatusBar {
                    Toggle("Side bar strip", isOn: $duo.sideStrip)
                    if duo.sideStrip {
                        Toggle("Accent tint on side bar", isOn: $duo.sideTint)
                    }
                }
            } header: {
                Text("Open display")
            } footer: {
                Text("Swap button: switches which side each page is on when the phone is open. Turning it off keeps the sides the way you left them. Status bar on the side: the time and icons run down the edge. Side bar strip: a dark grey bar behind them that the pages stop at; off, the pages run underneath.")
            }

            Section("Appearance") {
                // Theme is free for everyone (DaRon, 2026-11-09) — Dark
                // is true-black OLED. Accent colors stay Pro.
                Picker("Theme", selection: themeBinding) {
                    ForEach(ColorSchemeSetting.allCases, id: \.self) { scheme in
                        Text(scheme.label).tag(scheme)
                    }
                }
                if subscription.isPro {
                    Picker("Accent color", selection: accentBinding) {
                        ForEach(AccentColorName.offeredCases, id: \.self) { color in
                            Text(color.label).tag(color)
                        }
                    }
                } else {
                    Button("Accent colors — Pro") { showPaywall = true }
                }
                Text("Dark is true-black OLED — the screen's pixels turn off. Light and Auto follow the system.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Section("App icon") {
                AppIconPickerView()
            }

            Section("Reminders") {
                HStack {
                    Text("Workout reminder")
                    Spacer()
                    DatePicker("", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                Toggle("Missed-day nudge (stops after 3 days)", isOn: missedNudgeBinding)
                Text("Local notifications only, on this phone. Rest days stay quiet.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Button("Schedule reminders now") {
                    ReminderScheduler.scheduleAll(store: store)
                    remindersScheduledMessage = "Reminders scheduled — you'll be reminded at \(reminderTimeText) on workout days."
                }
                if let remindersScheduledMessage {
                    Text(remindersScheduledMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Section("Apple Calendar") {
                Toggle("Apple Calendar", isOn: calendarBinding)
                if calendarSync.accessDenied {
                    Text("Calendar access is off. Turn it on in Settings → Privacy & Security → Calendars → Status, then turn this back on.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Open Settings") { calendarSync.openSystemSettings() }
                } else if calendarSync.isEnabled {
                    Text("Your planned workout days show in Apple Calendar, on this phone only. Nothing is sent anywhere.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    if calendarSync.syncedEventCount > 0 {
                        Text("\(calendarSync.syncedEventCount) planned workout\(calendarSync.syncedEventCount == 1 ? "" : "s") in your calendar.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    Text("Adds your planned workout days to Apple Calendar, on this phone only. Nothing is sent anywhere.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .confirmationDialog("Remove calendar events?", isPresented: $showRemoveCalendarEvents) {
                Button("Remove events", role: .destructive) {
                    Task { await calendarSync.removeAllEvents() }
                }
                Button("Keep them", role: .cancel) { }
            } message: {
                Text("Status added workout events to your calendar. Remove them, or leave them there?")
            }

            Section("Plate calculator (barbell)") {
                HStack {
                    Text("Bar weight")
                    Spacer()
                    Picker("Bar weight", selection: barWeightBinding) {
                        Text("45 lb").tag(45.0)
                        Text("20 kg").tag(20.0)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                Text("Plate inventory: \(store.settings.plateInventoryLb.map { roundedWeightText($0) }.joined(separator: ", ")) lb")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            // Bottom breathing room (shared LayoutClearance rule,
            // Debug Pass 2): the Form had no bottom spacer, so the last
            // section sat at the safe-area bottom — under the floating
            // menu button (and the rest-timer panel while a rest runs)
            // at scroll-bottom.
            // Privacy & About (from Profile) above the bottom spacer.
            if let trailingSections { trailingSections }
            Section {
                Color.clear
                    .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .oledList()
        .navigationTitle("Settings")
        .onChange(of: scenePhase) { _, phase in
            // Back from system Settings after enabling the camera: clear
            // the "access is off" message without needing a relaunch.
            if phase == .active { flashlightSignal.refreshAuthorization() }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                programName: store.activeProgram?.name ?? "Your plan",
                onClose: { showPaywall = false },
                onPurchased: { showPaywall = false }
            )
        }
    }

    private var restDefaultBinding: Binding<Double> {
        Binding(
            get: { store.settings.restSecondsDefault },
            set: { var s = store.settings; s.restSecondsDefault = $0; store.updateSettings(s) }
        )
    }

    private var soundBinding: Binding<Bool> {
        Binding(
            get: { store.settings.restSoundEnabled },
            set: { var s = store.settings; s.restSoundEnabled = $0; store.updateSettings(s) }
        )
    }

    private var hapticBinding: Binding<Bool> {
        Binding(
            get: { store.settings.restHapticEnabled },
            set: { var s = store.settings; s.restHapticEnabled = $0; store.updateSettings(s) }
        )
    }

    /// Flashlight Morse toggle. Turning it on asks for camera access
    /// (the torch needs it) — the setting only flips on if access is
    /// granted; on denial it stays off and the message above points at
    /// system Settings. Turning it off cancels any flash in flight.
    private var flashlightBinding: Binding<Bool> {
        Binding(
            get: { store.settings.restFlashlightEnabled },
            set: { newValue in
                Task { @MainActor in await flashlightSignal.setEnabled(newValue, store: store) }
            }
        )
    }

    private var unitBinding: Binding<WeightUnit> {
        Binding(
            get: { store.settings.weightUnit },
            set: { var s = store.settings; s.weightUnit = $0; store.updateSettings(s) }
        )
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { store.settings.hapticsEnabled },
            set: { var s = store.settings; s.hapticsEnabled = $0; store.updateSettings(s) }
        )
    }

    private var keepAwakeBinding: Binding<Bool> {
        Binding(
            get: { store.settings.keepScreenAwake },
            set: { var s = store.settings; s.keepScreenAwake = $0; store.updateSettings(s) }
        )
    }

    private var themeBinding: Binding<ColorSchemeSetting> {
        Binding(
            get: { store.settings.colorScheme },
            set: { var s = store.settings; s.colorScheme = $0; store.updateSettings(s) }
        )
    }

    private var accentBinding: Binding<AccentColorName> {
        Binding(
            get: { store.settings.accentColor },
            set: { var s = store.settings; s.accentColor = $0; store.updateSettings(s) }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = store.settings.reminderTimeHour
                components.minute = store.settings.reminderTimeMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                var s = store.settings
                s.reminderTimeHour = Calendar.current.component(.hour, from: date)
                s.reminderTimeMinute = Calendar.current.component(.minute, from: date)
                store.updateSettings(s)
            }
        )
    }

    /// The reminder time as shown in the picker ("5:30 PM") — used by
    /// the D40 confirmation line under "Schedule reminders now".
    private var reminderTimeText: String {
        reminderTimeBinding.wrappedValue.formatted(.dateTime.hour().minute())
    }

    private var missedNudgeBinding: Binding<Bool> {
        Binding(
            get: { store.settings.missedDayNudgeEnabled },
            set: { var s = store.settings; s.missedDayNudgeEnabled = $0; store.updateSettings(s) }
        )
    }

    /// The Apple Calendar toggle. Turning on requests write-only
    /// calendar access (async); the toggle only flips on when access
    /// is granted, so a denial snaps it back off. Turning off stops
    /// new events and asks whether to remove the ones already added.
    private var calendarBinding: Binding<Bool> {
        Binding(
            get: { calendarSync.isEnabled },
            set: { newValue in
                if !newValue { showRemoveCalendarEvents = true }
                Task { await calendarSync.setEnabled(newValue, store: store) }
            }
        )
    }

    private var barWeightBinding: Binding<Double> {
        Binding(
            get: { store.settings.barWeightLb },
            set: { var s = store.settings; s.barWeightLb = $0; store.updateSettings(s) }
        )
    }
}

// MARK: - App icon picker (alternate icons bundled in the app)

struct AppIconPickerView: View {
    @State private var currentIcon: String? = UIApplication.shared.alternateIconName
    /// The last switch failure, shown in the picker so a failure is
    /// never silent (DaRon 2026-11-10 08:55: tapping Dark/Teal did
    /// nothing — the error was swallowed).
    @State private var iconError: String? = nil

    var body: some View {
        // Proper rows, not bunched up: 12pt between rows, a 56pt preview
        // of each icon's real artwork next to its name, and the checkmark
        // at the far edge — native iOS settings style.
        VStack(alignment: .leading, spacing: 12) {
            ForEach(AppIconChoice.allCases, id: \.self) { choice in
                Button {
                    setIcon(choice)
                } label: {
                    HStack(spacing: 12) {
                        // Real artwork preview: the 1024px icon PNGs,
                        // shipped as imagesets (AppIconPreview-*) —
                        // .appiconset contents can't load via Image().
                        Image(choice.previewImageName)
                            .resizable()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border, lineWidth: 1))
                        Text(choice.label)
                            .foregroundStyle(Theme.text)
                        Spacer()
                        if currentIcon == choice.iconName {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let iconError {
                Text(iconError)
                    .font(.caption)
                    .foregroundStyle(Theme.vividRed)
            }
            Text("Changing the icon is instant and stays on this device.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .onAppear { currentIcon = UIApplication.shared.alternateIconName }
    }

    private func setIcon(_ choice: AppIconChoice) {
        iconError = nil
        UIApplication.shared.setAlternateIconName(choice.iconName) { error in
            if let error {
                // Never silent: a missing icon set in the built app (the
                // most likely cause — the alternate sets have to be in
                // the bundle) now says so instead of looking like a dead tap.
                iconError = "Couldn't change the icon: \(error.localizedDescription)"
            } else {
                currentIcon = choice.iconName
            }
        }
    }
}

enum AppIconChoice: String, CaseIterable {
    case primary
    case dark
    case teal

    var label: String {
        switch self {
        case .primary: return "Default (blue dumbbell)"
        case .dark: return "Dark"
        case .teal: return "Teal"
        }
    }

    /// The alternate icon name in the asset catalog (nil = the primary icon).
    /// Must match ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: "AppIcon-Dark"
    /// and "AppIcon-Teal" (build setting; actool writes the plist entries).
    var iconName: String? {
        switch self {
        case .primary: return nil
        case .dark: return "AppIcon-Dark"
        case .teal: return "AppIcon-Teal"
        }
    }

    /// Preview artwork: an imageset built from the icon's own 1024px
    /// PNG (appiconsets can't load via Image()).
    var previewImageName: String {
        switch self {
        case .primary: return "AppIconPreview-Default"
        case .dark: return "AppIconPreview-Dark"
        case .teal: return "AppIconPreview-Teal"
        }
    }
}

// MARK: - Gym Profiles (Fitbod pattern: one profile per location)

struct GymProfilesView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var subscription: SubscriptionState
    @State private var showEditor = false
    @State private var editingProfile: GymProfile?
    @State private var showPaywall = false

    var body: some View {
        List {
            Section {
                ForEach(store.gymProfiles) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .font(.headline)
                            Text(profile.equipment.map { $0.label }.sorted().joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        if store.activeGymProfileID == profile.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.activeGymProfileID = profile.id
                        store.persistCustomization()
                    }
                    .swipeActions {
                        Button("Edit") { editingProfile = profile }
                        Button(role: .destructive) {
                            store.gymProfiles.removeAll { $0.id == profile.id }
                            if store.activeGymProfileID == profile.id {
                                store.activeGymProfileID = nil
                            }
                            store.persistCustomization()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                if store.gymProfiles.isEmpty {
                    Text("No gym profiles yet. Add one per location — home, gym, travel — each with its own equipment.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Section {
                Button("Add gym profile") {
                    if subscription.isPro || store.gymProfiles.count < 1 {
                        editingProfile = GymProfile(name: "", equipment: Set(Equipment.allCases))
                        showEditor = true
                    } else {
                        showPaywall = true
                    }
                }
                if store.activeGymProfileID != nil {
                    Button("Use my quiz equipment instead") {
                        store.activeGymProfileID = nil
                        store.persistCustomization()
                    }
                }
            }
            Section {
                Text("The active gym profile's equipment shapes the programs the generator builds. Free includes one profile; Pro is unlimited.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            // Bottom breathing room (shared LayoutClearance rule,
            // Debug Pass 2): no bottom spacer, so the last row sat
            // under the floating menu button at scroll-bottom.
            Color.clear
                .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .oledList()
        .navigationTitle("Gym Profiles")
        .sheet(item: $editingProfile) { profile in
            GymProfileEditorView(profile: profile) { updated in
                if let index = store.gymProfiles.firstIndex(where: { $0.id == updated.id }) {
                    store.gymProfiles[index] = updated
                } else {
                    store.gymProfiles.append(updated)
                }
                store.persistCustomization()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                programName: store.activeProgram?.name ?? "Your plan",
                onClose: { showPaywall = false },
                onPurchased: { showPaywall = false }
            )
        }
    }
}

/// Equipment checklist with Fitbod-style tabs: Most used / All / Selected.
struct GymProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: GymProfile
    var onSave: (GymProfile) -> Void
    @State private var tab = 0
    @State private var search = ""

    private let mostUsed: [Equipment] = [.dumbbell, .barbell, .bench, .cable, .bodyweight]

    private var filtered: [Equipment] {
        let base: [Equipment]
        switch tab {
        case 0: base = mostUsed
        case 2: base = Array(profile.equipment)
        default: base = Equipment.allCases
        }
        guard !search.isEmpty else { return base }
        return base.filter { $0.label.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Home, Gym, Travel…", text: $profile.name)
                }
                Section("Equipment") {
                    Picker("Equipment", selection: $tab) {
                        Text("Most used").tag(0)
                        Text("All").tag(1)
                        Text("Selected").tag(2)
                    }
                    .pickerStyle(.segmented)
                    ForEach(filtered, id: \.self) { equipment in
                        Toggle(isOn: Binding(
                            get: { profile.equipment.contains(equipment) },
                            set: { isOn in
                                if isOn { profile.equipment.insert(equipment) }
                                else { profile.equipment.remove(equipment) }
                            }
                        )) {
                            HStack(spacing: 10) {
                                EquipmentIcon(equipment: equipment)
                                Text(equipment.label)
                            }
                        }
                    }
                }
                Section {
                    Button("Save") {
                        onSave(profile)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || profile.equipment.isEmpty)
                }
            }
            .searchable(text: $search, prompt: "Search equipment")
            .oledList()
            .navigationTitle("Gym profile")
            // Keyboard Done (Debug Pass 2): the Name
            // field had no Done — the keyboard had no way out. Done
            // dismisses; the form's Save button saves.
            // NOTE (D39, 2026-11-10): the .dismissKeyboardOnTapOutside()
            // that used to sit here is REMOVED — the parent .onTapGesture
            // ate the equipment Toggle rows' taps (same class as D20/D24).
            // Keyboard dismissal stays covered by the native Done
            // toolbar + .scrollDismissesKeyboard(.interactively).
            .withKeyboardDoneToolbar(system: true)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Custom exercises

struct CustomExercisesView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var subscription: SubscriptionState
    @State private var showEditor = false
    @State private var editingExercise: CustomExercise?
    @State private var showPaywall = false
    /// Sections shown above the custom exercises (Profile puts Working
    /// Weights here, so it's one Exercises page).
    var leadingSections: AnyView? = nil

    var body: some View {
        List {
            if let leadingSections { leadingSections }
            Section("Custom exercises") {
                ForEach(store.customExercises) { exercise in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.headline)
                            Text("\(exercise.muscle.label) · \(exercise.type.label)")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Button("Edit") { editingExercise = exercise }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteCustomExercise(id: exercise.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                if store.customExercises.isEmpty {
                    Text("No custom exercises yet. Create your own — name, muscle, equipment, type — and it appears in the library and in routine building.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Section {
                Button("Add custom exercise") {
                    if store.canAddCustomExercise(isPro: subscription.isPro) {
                        editingExercise = CustomExercise(name: "", muscle: .chest, equipment: [.dumbbell])
                        showEditor = true
                    } else {
                        showPaywall = true
                    }
                }
                Text("Free: up to \(WorkoutStore.freeCustomExerciseCap) custom exercises. Pro: unlimited.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            // Bottom breathing room (shared LayoutClearance rule,
            // Debug Pass 2): no bottom spacer, so the last row sat
            // under the floating menu button at scroll-bottom.
            Color.clear
                .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .oledList()
        .navigationTitle(leadingSections == nil ? "Custom exercises" : "Exercises")
        .sheet(item: $editingExercise) { exercise in
            CustomExerciseEditorView(exercise: exercise) { updated in
                if let index = store.customExercises.firstIndex(where: { $0.id == updated.id }) {
                    store.customExercises[index] = updated
                } else {
                    store.addCustomExercise(updated)
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                programName: store.activeProgram?.name ?? "Your plan",
                onClose: { showPaywall = false },
                onPurchased: { showPaywall = false }
            )
        }
    }
}

struct CustomExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var exercise: CustomExercise
    var onSave: (CustomExercise) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $exercise.name)
                    Picker("Muscle", selection: $exercise.muscle) {
                        ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                            Text(muscle.label).tag(muscle)
                        }
                    }
                    Picker("Type", selection: $exercise.type) {
                        ForEach(CustomExerciseType.allCases, id: \.self) { type in
                            Text(type.label).tag(type)
                        }
                    }
                }
                Section("Equipment") {
                    ForEach(Equipment.allCases, id: \.self) { equipment in
                        Toggle(equipment.label, isOn: Binding(
                            get: { exercise.equipment.contains(equipment) },
                            set: { isOn in
                                if isOn { exercise.equipment.insert(equipment) }
                                else { exercise.equipment.remove(equipment) }
                            }
                        ))
                    }
                }
                Section("Defaults") {
                    HStack {
                        Text("Sets")
                        Spacer()
                        // Bounded stepper — same fix as the rest steppers:
                        // the native stepper's gray pill could run off the
                        // row's right edge. Same 1...6 range, same binding.
                        RowStepper(value: $exercise.defaultSets, range: 1...6, step: 1) { "\($0)" }
                    }
                    TextField("Rep range (e.g. 8–12)", text: $exercise.repRange)
                    Toggle("Dumbbell pair (per hand)", isOn: $exercise.isPair)
                    TextField("Cues (optional)", text: Binding(
                        get: { exercise.cues ?? "" },
                        set: { exercise.cues = $0.isEmpty ? nil : $0 }
                    ))
                }
                Section {
                    Button("Save") {
                        onSave(exercise)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(exercise.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || exercise.equipment.isEmpty)
                }
            }
            .oledList()
            .navigationTitle("Custom exercise")
            // Keyboard Done (Debug Pass 2): the Name /
            // Rep range / Cues fields had no Done — the keyboard had
            // no way out. Done dismisses; the form's Save button saves.
            // NOTE (D20, 2026-11-10): the .dismissKeyboardOnTapOutside()
            // that used to sit here is REMOVED — the parent .onTapGesture
            // ate the Muscle/Type Picker rows' and equipment Toggle rows'
            // taps. Keyboard dismissal stays covered by the native Done
            // toolbar + .scrollDismissesKeyboard(.interactively).
            .withKeyboardDoneToolbar(system: true)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Programs (multiple programs, Pro for extras)

struct ProgramsView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var subscription: SubscriptionState
    @State private var showPaywall = false
    @State private var renaming: UserProgram?
    @State private var newName = ""
    @State private var editingProgram: UserProgram? = nil

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ProgramLibraryView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Browse the program library")
                                .font(.headline)
                            Text("432 ready-made programs — filter by goal, level, days, and equipment")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                    }
                }
                NavigationLink {
                    CustomProgramBuilderView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create your own program")
                                .font(.headline)
                            Text("Name it, pick your days and split, add exercises — saved alongside your other programs")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                    }
                }
            }
            Section {
                ForEach(store.allPrograms) { program in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.name)
                                .font(.headline)
                            Text("\(program.days.count) days · \(programKindLabel(program))")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        if store.activeProgram?.id == program.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.setActiveProgram(program) }
                    .swipeActions {
                        if !program.isPreset {
                            Button("Duplicate") {
                                if subscription.isPro || store.extraPrograms.isEmpty {
                                    _ = store.duplicateProgram(program)
                                } else {
                                    showPaywall = true
                                }
                            }
                            Button("Rename") {
                                renaming = program
                                newName = program.name
                            }
                            if store.extraPrograms.contains(where: { $0.id == program.id }) {
                                Button("Edit") {
                                    editingProgram = program
                                }
                            }
                        }
                        if store.extraPrograms.contains(where: { $0.id == program.id }) {
                            Button(role: .destructive) {
                                store.deleteExtraProgram(id: program.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .pendingProgramSwitchAlert(store: store)
            // Restore DaRon's preset (Debug Pass 2): only on his
            // unlocked device, and only while the preset is NOT the
            // active program — never offered to users who never
            // unlocked it. The preset also appears in the list above
            // once unlocked; this row is the explicit way back.
            if store.isDaronPresetUnlocked && !store.isPresetActive {
                Section {
                    Button("Restore DaRon's 5-Day Split") {
                        store.restoreDaronPreset()
                    }
                    Text("Switches Today back to DaRon's 5-Day Split.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            // D43 (2026-11-10): the page ended at the Free footer with
            // more than half the screen empty below it. Fill it with
            // real data only — the active program's day breakdown and
            // a library preview by goal — no invented content, no
            // change to the rows or copy above, and the 96pt bottom
            // clearance spacer below stays untouched.
            if let activeProgram = store.activeProgram, !activeProgram.days.isEmpty {
                Section("This week — \(activeProgram.name)") {
                    ForEach(activeProgram.days) { day in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(day.title)
                                    .font(.headline)
                                Text(day.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Text("\(day.exercises.count) exercises · ~\(day.estimatedMinutes) min")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Text(weekSummary(for: activeProgram))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Section("Library at a glance") {
                HStack {
                    Text("Your favorites")
                    Spacer()
                    Text("\(store.favoriteProgramIDs.count) program\(store.favoriteProgramIDs.count == 1 ? "" : "s")")
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(CatalogGoal.allCases, id: \.self) { goal in
                    HStack {
                        Text(goal.label)
                        Spacer()
                        Text("\(ProgramLibrary.programs(goal: goal).count) programs")
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            Section {
                Text("Free: your generated program + 1 extra. Pro: unlimited programs.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            // Bottom breathing room (shared LayoutClearance rule,
            // Debug Pass 2): no bottom spacer, so the last row sat
            // under the floating menu button at scroll-bottom.
            Color.clear
                .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .oledList()
        .navigationTitle("Programs")
        .alert("Rename program", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $newName)
            Button("Save") {
                if let program = renaming {
                    store.renameProgram(program, to: newName)
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                programName: store.activeProgram?.name ?? "Your plan",
                onClose: { showPaywall = false },
                onPurchased: { showPaywall = false }
            )
        }
        .sheet(item: $editingProgram) { program in
            NavigationStack {
                CustomProgramBuilderView(editing: program)
            }
        }
    }

    /// Preset / Generated / Custom — extras (builder-built programs,
    /// catalog picks, duplicates) read "Custom", so the list never
    /// calls a hand-built or hand-picked program "Generated".
    private func programKindLabel(_ program: UserProgram) -> String {
        if program.isPreset { return "Preset" }
        if store.extraPrograms.contains(where: { $0.id == program.id }) { return "Custom" }
        return "Generated"
    }

    /// D43: weekly totals for the active program's day breakdown —
    /// days, exercises, and planned sets, all from the program itself.
    private func weekSummary(for program: UserProgram) -> String {
        let exercises = program.days.flatMap { $0.exercises }
        let sets = exercises.reduce(0) { $0 + $1.sets }
        return "\(program.days.count) days · \(exercises.count) exercises · \(sets) sets this week"
    }
}

// MARK: - Build your own program

/// Build a program by hand: name it, pick days/week + split, add
/// exercises per day from the library (the same filter/sort/favorite
/// controls as the exercise picker), set sets/reps per exercise, and
/// save it as a real program Today can run.
///
/// Same rules as the catalog programs: every added exercise is built
/// through ProgramGenerator.template (the single source for sets,
/// reps, and starting weights), progression runs through the store's
/// 2-for-2 gate for any template, and the volume summary below uses
/// the same push/pull/legs/core grouping as plannedWeeklyTargets.
/// The stored program is the ORIGINAL — injury swaps apply at run
/// time through adaptedActiveProgram, exactly like catalog programs,
/// so removing an injury mark restores the original exercises.
///
/// Saving goes through the same confirmation gate as any program
/// switch: when DaRon's preset is active, setActiveProgram only stages
/// pendingProgramSwitch and the Programs screen's alert decides it —
/// never a silent overwrite. Free tier: one extra program (the
/// paywall's "2 programs": generated + one extra); Pro: unlimited.
/// Editing the program you already have never consumes a new slot.
struct CustomProgramBuilderView: View {
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var subscription: SubscriptionState
    @Environment(\.dismiss) private var dismiss
    var editing: UserProgram? = nil

    @State private var name: String = ""
    @State private var daysPerWeek: Int = 3
    @State private var split: CatalogSplit = .fullBody
    @State private var dayExercises: [[ExerciseTemplate]] = [[], [], []]
    @State private var addingToDay: Int? = nil
    @State private var showPaywall = false
    @State private var didSetup = false

    /// Rep ranges the builder offers, with the top rep each one resets
    /// to after a progression bump (same pairing the generator uses).
    private static let repRanges: [(String, Int)] = [
        ("4–6", 6), ("6–12", 12), ("8–12", 12), ("10–15", 15), ("12–15", 15),
    ]

    /// Weekday keys mirror the generator's own patterns, so Today
    /// schedules the days on the right weekdays.
    private static let weekdayKeys: [Int: [(key: String, weekday: String)]] = [
        1: [("Mon", "Monday")],
        2: [("Mon", "Monday"), ("Thu", "Thursday")],
        3: [("Mon", "Monday"), ("Wed", "Wednesday"), ("Fri", "Friday")],
        4: [("Mon", "Monday"), ("Tue", "Tuesday"), ("Thu", "Thursday"), ("Fri", "Friday")],
        5: [("Mon", "Monday"), ("Tue", "Tuesday"), ("Wed", "Wednesday"), ("Thu", "Thursday"), ("Fri", "Friday")],
        6: [("Mon", "Monday"), ("Tue", "Tuesday"), ("Wed", "Wednesday"), ("Thu", "Thursday"), ("Fri", "Friday"), ("Sat", "Saturday")],
        7: [("Mon", "Monday"), ("Tue", "Tuesday"), ("Wed", "Wednesday"), ("Thu", "Thursday"), ("Fri", "Friday"), ("Sat", "Saturday"), ("Sun", "Sunday")],
    ]

    var body: some View {
        Form {
            Section("Details") {
                TextField("Program name", text: $name)
                HStack {
                    Text("Days / week")
                    Spacer()
                    RowStepper(value: $daysPerWeek, range: 1...7, step: 1) { "\($0)" }
                }
                Text("Lowering the days removes the last days' exercises.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                // D42 (2026-11-10, fix batch 2): the Split control used
                // to be a Picker inside a Menu (MenuPill) in this Form.
                // After picking Push/Pull/Legs the whole builder went
                // touch-dead (17 failed inputs incl. Cancel, back,
                // FAB — app alive, clock ticking): the Menu's dismissal
                // leaves a transparent window-level overlay intercepting
                // touches when the Form regenerates its day sections
                // underneath it, and no code path here can complete or
                // dismiss that overlay. The native Form pattern — a
                // navigation-link Picker — has no Menu/popover at all:
                // tap Split, pick from the pushed list, it pops back.
                // Same $split binding, same options, same day titles.
                Picker("Split", selection: $split) {
                    ForEach(CatalogSplit.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("Weekly volume") {
                Text("Push \(volume.push) · Pull \(volume.pull) · Legs \(volume.legs) · Core \(volume.core) sets (\(volume.total) total)")
                    .font(.subheadline)
                if volume.total > 0 {
                    if volume.push == 0 {
                        Text("No pushing work yet — add a press or push-up for balance.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if volume.pull == 0 {
                        Text("No pulling work yet — add a row or pulldown for balance.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if volume.legs == 0 {
                        Text("No leg work yet — add a squat, leg press, or hinge for balance.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else {
                    Text("Add exercises below to see your weekly volume.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if !adaptedSwaps.isEmpty {
                Section("Swapped for your injuries") {
                    ForEach(Array(adaptedSwaps.enumerated()), id: \.offset) { _, swap in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.triangle.swap")
                                .foregroundStyle(Color.accentColor)
                            Text(swap.displayText)
                                .font(.subheadline)
                        }
                    }
                    Text("The original exercises are saved — removing an injury mark restores them.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            ForEach(dayExercises.indices, id: \.self) { day in
                Section("\(dayTitle(at: day)) · \(weekday(at: day))") {
                    ForEach(dayExercises[day].indices, id: \.self) { index in
                        exerciseRow(day: day, index: index)
                    }
                    Button {
                        addingToDay = day
                    } label: {
                        Label("Add exercise", systemImage: "plus")
                    }
                    if dayExercises[day].isEmpty {
                        Text("Add at least one exercise to this day.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            if atFreeLimit {
                Section {
                    Text("Free includes 2 programs — your generated program and one extra. You already have an extra program, so this one needs Pro.")
                        .font(.subheadline)
                    Button("View Pro") { showPaywall = true }
                }
            }
        }
        .oledList()
        .navigationTitle(editing == nil ? "Create program" : "Edit program")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave || atFreeLimit)
            }
        }
        .withKeyboardDoneToolbar(system: true)
        .scrollDismissesKeyboard(.interactively)
        // NOTE (D24, 2026-11-10): the .dismissKeyboardOnTapOutside()
        // that used to sit here is REMOVED — the parent .onTapGesture
        // ate the "+ Add exercise" Button's taps (same class as D20).
        // Keyboard dismissal stays covered by the native Done toolbar
        // + .scrollDismissesKeyboard(.interactively).
        .onAppear { setupIfNeeded() }
        .onChange(of: daysPerWeek) { _, _ in resizeDays() }
        .sheet(isPresented: Binding(
            get: { addingToDay != nil },
            set: { if !$0 { addingToDay = nil } }
        )) {
            AddExerciseSheet { template in
                if let day = addingToDay { dayExercises[day].append(template) }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                programName: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Your plan" : name,
                onClose: { showPaywall = false },
                onPurchased: { showPaywall = false }
            )
        }
    }

    // MARK: - Draft

    /// The program as it will be saved: weekday keys + split-day
    /// titles mirroring the generator, subtitles in the generator's
    /// "Weekday · muscles" shape, finisher empty (the builder has no
    /// finisher step — Today runs fine without one).
    private var draftProgram: UserProgram {
        let keys = Self.weekdayKeys[daysPerWeek] ?? [("Mon", "Monday")]
        let days = dayExercises.enumerated().map { index, exercises in
            DayPlan(key: keys.indices.contains(index) ? keys[index].key : "Mon",
                    title: dayTitle(at: index),
                    subtitle: daySubtitle(at: index),
                    exercises: exercises, finisher: [])
        }
        return UserProgram(id: editing?.id ?? UUID().uuidString,
                           name: name.trimmingCharacters(in: .whitespaces),
                           days: days, swaps: [], isPreset: false)
    }

    private func dayTitle(at index: Int) -> String {
        switch split {
        case .fullBody:
            // Modulo, like the other splits: the letter list has 7
            // entries and daysPerWeek is 1...7, so this never wraps in
            // practice — but an out-of-range index must never trap
            // (D41's stale crash was in this same area).
            return daysPerWeek == 1 ? "Full Body" : "Full Body \(["A", "B", "C", "D", "E", "F", "G"][index % 7])"
        case .upperLower:
            return index % 2 == 0 ? "Upper" : "Lower"
        case .pushPullLegs:
            return ["Push", "Pull", "Legs"][index % 3]
        case .pushPullLegsUpperLower:
            return ["Push", "Pull", "Legs", "Upper", "Lower"][index % 5]
        case .broSplit:
            return ["Chest", "Back", "Legs", "Shoulders", "Arms"][index % 5]
        }
    }

    private func weekday(at index: Int) -> String {
        // D42 hardening (D41 family): the old optional chain
        // `weekdayKeys[daysPerWeek]?[index]` was nil-safe for a
        // missing daysPerWeek key but NOT index-safe — an out-of-range
        // index still traps. Guard the index the same way draftProgram
        // already does, so the draft can never desync into a crash.
        guard let keys = Self.weekdayKeys[daysPerWeek], keys.indices.contains(index) else { return "Monday" }
        return keys[index].weekday
    }

    private func daySubtitle(at index: Int) -> String {
        let weekday = weekday(at: index)
        let muscles = dayExercises[index].compactMap {
            ExerciseLibrary.byId($0.id, plus: store.customExercises)?.muscle.label
        }
        let unique = Array(Set(muscles)).sorted()
        return unique.isEmpty ? weekday : "\(weekday) · \(unique.joined(separator: ", "))"
    }

    /// Planned weekly sets by target group, using the same grouping as
    /// plannedWeeklyTargets (push/pull/legs/core) — the builder's
    /// volume check, live as exercises are added.
    private var volume: (push: Int, pull: Int, legs: Int, core: Int, total: Int) {
        var counts: [MuscleGroup: Int] = [:]
        for day in dayExercises {
            for template in day {
                guard let muscle = ExerciseLibrary.byId(template.id, plus: store.customExercises)?.muscle else { continue }
                counts[muscle, default: 0] += template.sets
            }
        }
        var push = 0, pull = 0, legs = 0, core = 0
        for (muscle, count) in counts {
            switch muscle.weeklyTargetGroup {
            case .push: push += count
            case .pull: pull += count
            case .legs: legs += count
            case .core: core += count
            }
        }
        return (push, pull, legs, core, push + pull + legs + core)
    }

    /// The draft with the user's marked injuries applied — the same
    /// adaptation Today runs. Shown above so a swap is never a surprise;
    /// the ORIGINAL is what gets saved.
    private var adaptedSwaps: [ProgramSwap] {
        guard let profile = store.profile, !profile.limits.isEmpty else { return [] }
        return InjuryAdaptation.adapt(program: draftProgram, profile: profile,
                                      customExercises: store.customExercises,
                                      equipment: store.effectiveEquipment).swaps
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && dayExercises.count == daysPerWeek
        && dayExercises.allSatisfy { !$0.isEmpty }
    }

    /// Free tier: one extra program (the paywall's 2 programs). Editing
    /// the program you already have never consumes a new slot.
    private var atFreeLimit: Bool {
        editing == nil && !store.canAddExtraProgram(isPro: subscription.isPro)
    }

    private func save() {
        guard canSave, !atFreeLimit else { return }
        let program = draftProgram
        if editing != nil {
            store.updateExtraProgram(program)
        } else {
            store.addExtraProgram(program)
        }
        // Same confirmation gate as any program switch (see the header
        // comment): when the preset is active this only stages the
        // switch — the Programs screen's alert decides it.
        store.setActiveProgram(program)
        dismiss()
    }

    private func setupIfNeeded() {
        guard !didSetup else { return }
        didSetup = true
        if let editing {
            name = editing.name
            daysPerWeek = editing.days.count
            split = Self.inferredSplit(from: editing)
            dayExercises = editing.days.map { $0.exercises }
        } else {
            dayExercises = Array(repeating: [], count: daysPerWeek)
        }
    }

    private func resizeDays() {
        if dayExercises.count < daysPerWeek {
            dayExercises.append(contentsOf: Array(repeating: [], count: daysPerWeek - dayExercises.count))
        } else if dayExercises.count > daysPerWeek {
            dayExercises.removeLast(dayExercises.count - daysPerWeek)
        }
    }

    /// Best-guess split from a stored program's day titles (UserProgram
    /// doesn't record its split). Only used to prefill the picker when
    /// editing; the exercises are what matter, and the titles are
    /// re-derived from the picked split on save.
    private static func inferredSplit(from program: UserProgram) -> CatalogSplit {
        let titles = program.days.map { $0.title }
        if titles.allSatisfy({ $0.hasPrefix("Full Body") }) { return .fullBody }
        if titles.allSatisfy({ $0 == "Upper" || $0 == "Lower" }) { return .upperLower }
        if titles.allSatisfy({ ["Push", "Pull", "Legs"].contains($0) }) { return .pushPullLegs }
        if titles.allSatisfy({ ["Chest", "Back", "Legs", "Shoulders", "Arms"].contains($0) }) { return .broSplit }
        if titles.allSatisfy({ ["Push", "Pull", "Legs", "Upper", "Lower"].contains($0) }) { return .pushPullLegsUpperLower }
        return .fullBody
    }

    // MARK: - Exercise rows

    private func setsBinding(day: Int, index: Int) -> Binding<Int> {
        Binding(
            get: { dayExercises[day][index].sets },
            set: { dayExercises[day][index].sets = $0 }
        )
    }

    private func repBinding(day: Int, index: Int) -> Binding<String> {
        Binding(
            get: { dayExercises[day][index].repRange },
            set: { newValue in
                dayExercises[day][index].repRange = newValue
                if let top = Self.repRanges.first(where: { $0.0 == newValue })?.1 {
                    dayExercises[day][index].topReps = top
                }
            }
        )
    }

    /// One added exercise: name + remove, then sets and reps on their
    /// own lines — two controls side by side would crowd the narrowest
    /// pose, so they stack instead (no control may clip at any edge).
    private func exerciseRow(day: Int, index: Int) -> some View {
        let template = dayExercises[day][index]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(template.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Button {
                    dayExercises[day].remove(at: index)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.vividRed)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(template.name)")
            }
            HStack {
                Text("Sets")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                RowStepper(value: setsBinding(day: day, index: index), range: 1...6, step: 1) { "\($0)" }
                Spacer()
            }
            HStack {
                Text("Reps")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                MenuPill(label: template.repRange) {
                    Picker("Reps", selection: repBinding(day: day, index: index)) {
                        ForEach(Self.repRanges, id: \.0) { label, _ in
                            Text(label).tag(label)
                        }
                        if !Self.repRanges.contains(where: { $0.0 == template.repRange }) {
                            Text(template.repRange).tag(template.repRange)
                        }
                    }
                }
                Spacer()
            }
        }
    }
}

// MARK: - Pending program-switch confirmation (preset gate)

/// The "Replace DaRon's 5-Day Split?" confirmation, shared by every
/// program-switch tap path (ProgramsView rows and the catalog detail
/// "Use this program" button). The store defers the switch in
/// `pendingProgramSwitch` when the preset is active; this alert is the
/// only thing that confirms or cancels it, so a tap can never look
/// like it did nothing. Dismissing without choosing cancels the
/// pending switch (the binding's setter) — no stale request is left
/// behind, and the preset stays active.
extension View {
    func pendingProgramSwitchAlert(store: WorkoutStore) -> some View {
        alert("Replace DaRon's 5-Day Split?", isPresented: Binding(
            get: { store.pendingProgramSwitch != nil },
            set: { if !$0 { store.cancelPendingProgramSwitch() } }
        )) {
            Button("Switch to \(store.pendingProgramSwitch?.name ?? "the new program")") {
                store.confirmPendingProgramSwitch()
            }
            Button("Keep my current program", role: .cancel) {
                store.cancelPendingProgramSwitch()
            }
        } message: {
            Text("Your Today screen will show the new program instead of DaRon's 5-Day Split. You can switch back from Programs.")
        }
    }
}

// MARK: - Program library browser (300+ ready-made programs)

/// Browse the 432-program catalog. Four dropdown filters (goal, level,
/// days/week, equipment — native Menu style, the same pattern as the
/// exercise picker) narrow the list; tap a program to see its days and
/// pick it as your program. DaRon's preset is NOT in this catalog — his
/// personal split is never offered to other users.
struct ProgramLibraryView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    @State private var goalFilter: CatalogGoal? = nil
    @State private var levelFilter: CatalogLevel? = nil
    @State private var daysFilter: Int? = nil
    @State private var equipmentFilter: EquipmentAccess? = nil
    @State private var sortOption: ProgramSort = .name
    @State private var favoritesOnly = false

    /// Sort order for the library. "Newest" has no creation date on
    /// catalog programs, so it is defined as reverse catalog order
    /// (last-emitted = newest).
    enum ProgramSort: String, CaseIterable {
        case name, days, duration, level, newest

        var label: String {
            switch self {
            case .name: return "Name A–Z"
            case .days: return "Days/week"
            case .duration: return "Duration"
            case .level: return "Level"
            case .newest: return "Newest"
            }
        }
    }

    private var filtered: [CatalogProgram] {
        var list = ProgramLibrary.all
        if favoritesOnly { list = list.filter { store.isFavoriteProgram($0.id) } }
        if let goalFilter { list = list.filter { $0.goal == goalFilter } }
        if let levelFilter { list = list.filter { $0.level == levelFilter } }
        if let daysFilter { list = list.filter { $0.daysPerWeek == daysFilter } }
        if let equipmentFilter { list = list.filter { $0.equipment == equipmentFilter } }
        return list
    }

    /// The filtered list in the picked order (stable: ties keep
    /// catalog order, so a sort never scrambles equal rows).
    private var sorted: [CatalogProgram] {
        switch sortOption {
        case .name:
            return filtered.sorted { $0.program.name.localizedCaseInsensitiveCompare($1.program.name) == .orderedAscending }
        case .days:
            return filtered.sorted { $0.daysPerWeek < $1.daysPerWeek }
        case .duration:
            return filtered.sorted { $0.durationWeeks < $1.durationWeeks }
        case .level:
            return filtered.sorted {
                (CatalogLevel.allCases.firstIndex(of: $0.level) ?? 0) < (CatalogLevel.allCases.firstIndex(of: $1.level) ?? 0)
            }
        case .newest:
            return Array(filtered.reversed())
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    filterMenu(title: "Goal", allLabel: "All goals",
                               options: CatalogGoal.allCases.map { ($0.label, $0) },
                               selection: $goalFilter)
                    filterMenu(title: "Level", allLabel: "All levels",
                               options: CatalogLevel.allCases.map { ($0.label, $0) },
                               selection: $levelFilter)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                HStack(spacing: 12) {
                    filterMenu(title: "Days / week", allLabel: "Any days",
                               options: [1, 2, 3, 4, 5, 6, 7].map { ("\($0) day\($0 == 1 ? "" : "s")", $0) },
                               selection: $daysFilter)
                    filterMenu(title: "Equipment", allLabel: "All equipment",
                               options: EquipmentAccess.allCases.map { ($0.label, $0) },
                               selection: $equipmentFilter)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                // Sort + favorites-only: the same single-pill row as the
                // filters above — no card behind the pills.
                HStack(spacing: 12) {
                    sortMenu
                    favoritesToggle
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            }
            Section {
                Text("\(sorted.count) program\(sorted.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                ForEach(sorted) { catalog in
                    NavigationLink {
                        CatalogProgramDetailView(catalog: catalog)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(catalog.program.name)
                                    .font(.headline)
                                Text("\(catalog.goal.label) · \(catalog.level.label) · \(daysPerWeekText(catalog.daysPerWeek))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                                Text("\(catalog.equipment.label) · \(catalog.split.label) · \(catalog.durationWeeks) weeks")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            favoriteButton(for: catalog)
                        }
                    }
                }
            }
            if sorted.isEmpty {
                // D31 (2026-11-10): the bare text sat top-pinned in an
                // otherwise empty List. Centred icon + text block,
                // mirroring Notes (D17) — the minHeight grows the row
                // itself so the block sits mid-screen.
                VStack(spacing: 12) {
                    Image(systemName: favoritesOnly ? "heart" : "magnifyingglass")
                        .scaledFont(size: 44)
                        .foregroundStyle(Theme.tertiaryText)
                    if favoritesOnly {
                        Text("No favorites yet. Tap the heart on a program to save it here.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("No programs match those filters. Try loosening one.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 440)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            // Bottom breathing room (shared LayoutClearance rule,
            // Debug Pass 2): no bottom spacer, so the last program row
            // sat under the floating menu button at scroll-bottom.
            Color.clear
                .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .oledList()
        .navigationTitle("Program library")
    }

    /// One dropdown filter: a caption + the shared single clean pill
    /// (native Menu with a Picker inside, so the open menu shows a
    /// checkmark on the current pick). 44pt+ tap target, shows the
    /// current pick, shrinks instead of truncating. The pill is ONE
    /// capsule — the old card-in-a-card double pill is gone, and the
    /// row behind it is clear, so no halo wraps it.
    private func filterMenu<T: Hashable>(title: String, allLabel: String, options: [(String, T)], selection: Binding<T?>) -> some View {
        let currentLabel = selection.wrappedValue.flatMap { value in
            options.first { $0.1 == value }?.0
        } ?? allLabel
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            MenuPill(label: currentLabel, isActive: selection.wrappedValue != nil) {
                Picker(title, selection: selection) {
                    Text(allLabel).tag(nil as T?)
                    ForEach(options, id: \.1) { label, value in
                        Text(label).tag(value as T?)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Sort control: the same single clean pill as the filters.
    private var sortMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sort")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            MenuPill(label: sortOption.label) {
                Picker("Sort", selection: $sortOption) {
                    ForEach(ProgramSort.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Favorites-only switch: the same single clean pill shape, with a
    /// heart — on, the list shows only favorited programs.
    private var favoritesToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Button {
                favoritesOnly.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                        .font(.caption)
                    Text("Favorites")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(favoritesOnly ? Color.accentColor : Theme.text)
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(favoritesOnly ? Color.accentColor.opacity(0.15) : Theme.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(favoritesOnly ? Color.accentColor.opacity(0.4) : Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    /// Heart on every program row: taps favorite it (persists on-device
    /// across relaunches via the store). The button wins over the
    /// NavigationLink, so tapping the heart never opens the detail.
    private func favoriteButton(for catalog: CatalogProgram) -> some View {
        Button {
            store.toggleFavoriteProgram(catalog.id)
        } label: {
            Image(systemName: store.isFavoriteProgram(catalog.id) ? "heart.fill" : "heart")
                .scaledFont(size: 20)
                .foregroundStyle(store.isFavoriteProgram(catalog.id) ? Color.accentColor : Theme.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.isFavoriteProgram(catalog.id)
                            ? "Remove \(catalog.program.name) from favorites"
                            : "Favorite \(catalog.program.name)")
    }
}

/// One catalog program, day by day, with a "Use this program" button.
/// Picking it adds it to your programs (free: one extra program; Pro:
/// unlimited) and makes it the active program, so Today shows it.
struct CatalogProgramDetailView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    @EnvironmentObject var subscription: SubscriptionState
    let catalog: CatalogProgram
    @State private var showPaywall = false
    @State private var justPicked = false

    private var program: UserProgram { catalog.program }
    /// The program as shown: the catalog program with the user's marked
    /// injuries applied (swaps + a swaps section below). Picking the
    /// program stores the ORIGINAL — never the adapted copy — so
    /// removing an injury later restores the original exercises.
    private var displayProgram: UserProgram {
        guard let profile = store.profile else { return catalog.program }
        return InjuryAdaptation.adapt(program: catalog.program, profile: profile,
                                      customExercises: store.customExercises,
                                      equipment: store.effectiveEquipment)
    }
    private var isActive: Bool { store.activeProgram?.id == program.id }
    private var isExtra: Bool { store.extraPrograms.contains { $0.id == program.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(program.name)
                        .font(.largeTitle)
                        .bold()
                    Text(catalog.focus)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    HStack(spacing: 6) {
                        metaPill(catalog.goal.label)
                        metaPill(catalog.level.label)
                        metaPill(daysPerWeekText(catalog.daysPerWeek))
                        metaPill("\(catalog.durationWeeks) weeks")
                    }
                    HStack(spacing: 6) {
                        metaPill(catalog.equipment.label)
                        metaPill(catalog.split.label)
                    }
                }
                .padding(.top, 8)

                if !displayProgram.swaps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Swapped for your injuries")
                            .font(.headline)
                        ForEach(Array(displayProgram.swaps.enumerated()), id: \.offset) { _, swap in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.triangle.swap")
                                    .foregroundStyle(Color.accentColor)
                                Text(swap.displayText)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .themeCard()
                }

                ForEach(displayProgram.days) { day in
                    dayCard(day)
                }

                Button(action: pickProgram) {
                    Text(isActive ? "This is your program ✓" : "Use this program")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isActive ? Theme.card : Color.accentColor)
                        .foregroundStyle(isActive ? Theme.secondaryText : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isActive)

                // "Done" only once the pick is actually confirmed: when
                // the preset was active, pickProgram() only stages the
                // switch in `pendingProgramSwitch` (the confirmation
                // alert decides it), so the line must stay hidden while
                // a switch is pending — and stay hidden if the user
                // cancels. No confirmed-pick signal exists on the store,
                // so confirmation is derived from pending == nil AND the
                // active program now being this one.
                if justPicked && store.pendingProgramSwitch == nil && isActive {
                    Text("Done — your Today screen now shows this program.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                } else if !subscription.isPro && !isExtra && !isActive {
                    Text("Free includes your generated program + 1 extra. Pro adds unlimited programs.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            // Same 16pt sides/top as before; the bottom is the shared
            // LayoutClearance rule (Debug Pass 2). The old uniform 16pt
            // padding left the "Use this program" button — the primary
            // action on this screen — under the floating menu button
            // (and the rest-timer panel while a rest runs) at
            // scroll-bottom: the same clipped-primary-button shape as
            // DaRon's photo of Today.
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
        }
        .navigationTitle("Program")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView(
                programName: program.name,
                onClose: { showPaywall = false },
                onPurchased: { showPaywall = false }
            )
        }
        .pendingProgramSwitchAlert(store: store)
    }

    private func metaPill(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private func dayCard(_ day: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.title)
                    .font(.headline)
                Spacer()
                Text("~\(day.estimatedMinutes) min")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text(day.subtitle)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            ForEach(day.exercises) { exercise in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(exercise.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer()
                        Text("\(exercise.sets) × \(exercise.repRange)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let note = displayProgram.swaps.first(where: { $0.to == exercise.name })?.shortExplanation {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            if !day.finisher.isEmpty {
                Text("Finisher: " + day.finisher.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding()
        .themeCard()
    }

    private func pickProgram() {
        guard !isActive else { return }
        if !isExtra {
            // Free tier: one extra program; Pro: unlimited (same rule as
            // duplicating a program on the Programs screen).
            if !subscription.isPro && !store.extraPrograms.isEmpty {
                showPaywall = true
                return
            }
            store.addExtraProgram(program)
        }
        store.setActiveProgram(program)
        justPicked = true
    }
}

// MARK: - Reminder scheduler (local notifications only, on-device)

enum ReminderScheduler {
    private static let reminderIDPrefix = "gymtracker.reminder."
    private static let nudgeID = "gymtracker.missed-day-nudge"
    private static let missedCountKey = "gymtracker.missedDays.v1"

    /// Schedule a reminder on each training day this week at the chosen time,
    /// plus a missed-day nudge the morning after a training day (stops after
    /// 3 missed days). All local, on-device.
    static func scheduleAll(store: WorkoutStore) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            center.removePendingNotificationRequests(withIdentifiers:
                pendingIDs(for: store) + [nudgeID])
            scheduleTrainingReminders(store: store, center: center)
            scheduleMissedDayNudgeIfNeeded(store: store, center: center)
        }
    }

    private static func pendingIDs(for store: WorkoutStore) -> [String] {
        guard let program = store.activeProgram else { return [] }
        return program.days.map { reminderIDPrefix + $0.key }
    }

    private static func scheduleTrainingReminders(store: WorkoutStore, center: UNUserNotificationCenter) {
        guard let program = store.activeProgram else { return }
        let weekdayMap: [String: Int] = ["Mon": 2, "Tue": 3, "Wed": 4, "Thu": 5, "Fri": 6, "Sat": 7, "Sun": 1]
        for day in program.days {
            guard let weekday = weekdayMap[day.key] else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Today: \(day.title)"
            content.body = "\(day.exercises.count) exercises · about \(day.estimatedMinutes) min. Time to lift."
            content.sound = .default
            var components = DateComponents()
            components.weekday = weekday
            components.hour = store.settings.reminderTimeHour
            components.minute = store.settings.reminderTimeMinute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: reminderIDPrefix + day.key, content: content, trigger: trigger)
            center.add(request)
        }
    }

    private static func scheduleMissedDayNudgeIfNeeded(store: WorkoutStore, center: UNUserNotificationCenter) {
        guard store.settings.missedDayNudgeEnabled else { return }
        let missed = SharedDefaults.store.integer(forKey: missedCountKey)
        guard missed < 3 else { return }
        // If yesterday was a training day and no session was logged, nudge
        // tomorrow morning. Checked at schedule time; a saved session cancels it.
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        guard let key = Program.dayKey(for: yesterday),
              store.activeProgram?.day(forKey: key) != nil else { return }
        let loggedYesterday = store.sessions.contains {
            Calendar.current.isDate($0.date, inSameDayAs: yesterday)
        }
        guard !loggedYesterday else { return }
        SharedDefaults.store.set(missed + 1, forKey: missedCountKey)
        let content = UNMutableNotificationContent()
        content.title = "Missed yesterday's workout?"
        content.body = "No pressure — today is a fresh start. Your next session is ready."
        content.sound = .default
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 9
        components.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: nudgeID, content: content, trigger: trigger)
        center.add(request)
    }

    /// Call when a session is saved: clears the missed-day count and any
    /// pending nudge.
    static func cancelMissedDayNudge() {
        SharedDefaults.store.set(0, forKey: missedCountKey)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [nudgeID])
    }
}
