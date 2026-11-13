import SwiftUI

/// Notes page — the fourth page in the floating menu (Today / History /
/// Profile / Notes).
///
/// Laid out like Apple's Notes app (Nov 12), built with our own styling
/// and no Apple assets:
/// - Folded: the note list (Pinned, then Today / Yesterday / Previous
///   7 Days / Previous 30 Days / by month). Tap a note and it opens as
///   its own page that you type straight into; it saves as you type.
/// - Open Duo: the list on one page, the open note on the other — the
///   first note is already open, waiting. The swap button mirrors them.
///
/// Where notes come from (all on-device, like everything else):
/// - Workout notes: written in the per-exercise note field on Today,
///   saved with the workout (title = the exercise, subtitle = the day).
/// - Free notes: written here with the + button.
///
/// Actions (DaRon 22:42): pin a note to the top, delete it (asks
/// first), and file it in a category.
struct NotesView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @Environment(\.duoWide) private var wide
    @Environment(\.duoSwapped) private var swapped
    @EnvironmentObject var store: WorkoutStore
    @State private var searchText = ""
    @State private var categoryFilter: CategoryFilter = .all
    @State private var notePendingDelete: UserNote?
    /// Folded: the pushed note.
    @State private var path: [UUID] = []
    /// Open Duo: the note shown beside the list.
    @State private var selectedID: UUID?
    /// True once a note was opened by hand (not the first note shown
    /// automatically). Folding only carries a hand-opened note over.
    @State private var userPicked = false

    /// Category filter for the list. All shows everything.
    private enum CategoryFilter: Hashable {
        case all
        case uncategorized
        case named(String)
    }

    /// Notes matching the search + category filter, most recently
    /// edited first.
    private var filteredNotes: [UserNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var notes = store.userNotes
        switch categoryFilter {
        case .all:
            break
        case .uncategorized:
            notes = notes.filter { $0.category == nil }
        case .named(let name):
            notes = notes.filter { $0.category == name }
        }
        if !query.isEmpty {
            notes = notes.filter { note in
                note.title.localizedCaseInsensitiveContains(query)
                    || note.body.localizedCaseInsensitiveContains(query)
                    || (note.workoutTitle?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Pinned first, then date groups, like Apple Notes.
    private var sections: [(title: String, notes: [UserNote])] {
        let notes = filteredNotes
        var result: [(String, [UserNote])] = []
        let pinned = notes.filter(\.isPinned)
        if !pinned.isEmpty { result.append(("Pinned", pinned)) }
        var groups: [(String, [UserNote])] = []
        for note in notes where !note.isPinned {
            let key = Self.groupTitle(for: note.updatedAt)
            if let i = groups.firstIndex(where: { $0.0 == key }) {
                groups[i].1.append(note)
            } else {
                groups.append((key, [note]))
            }
        }
        return result + groups
    }

    /// The first note in list order (what the open Duo shows first).
    private var firstNoteID: UUID? { sections.first?.notes.first?.id }

    /// The category a new note starts in: the one being filtered on.
    private var initialCategoryForNewNote: String? {
        if case .named(let name) = categoryFilter { return name }
        return nil
    }

    var body: some View {
        Group {
            if wide {
                // The list keeps the front screen's exact width and side
                // (right, like Today), so opening the Duo is seamless —
                // the note waits on the other page. Swap mirrors it.
                DuoPagePair(wide: true, swapped: swapped) {
                    detailPane
                        // The line between the pages, on the hinge side.
                        .overlay(alignment: swapped ? .leading : .trailing) { Divider() }
                } main: {
                    listPane
                        .background(Theme.card.opacity(0.35))
                }
            } else {
                NavigationStack(path: $path) {
                    listPane
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: UUID.self) { id in
                            NoteDetailView(noteID: id)
                        }
                }
            }
        }
        .background(Theme.background)
        .disableVerticalBar()
        .onAppear(perform: syncSelection)
        .onChange(of: wide) { _, isWide in
            // Unfolding with a note open keeps that note open beside
            // the list; folding with one selected pushes it.
            if isWide {
                if let open = path.last { selectedID = open; userPicked = true }
                path = []
                syncSelection()
            } else if userPicked, let selectedID, store.userNotes.contains(where: { $0.id == selectedID }),
                      !(store.userNotes.first(where: { $0.id == selectedID })?.isBlank ?? true) {
                path = [selectedID]
            }
        }
        .onChange(of: store.userNotes.map(\.id)) { _, _ in syncSelection() }
        // The corner compose button (ContentView).
        .onChange(of: store.composeNoteRequest) { _, _ in compose() }
        .alert("Delete this note?", isPresented: Binding(
            get: { notePendingDelete != nil },
            set: { if !$0 { notePendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let note = notePendingDelete {
                    store.deleteUserNote(id: note.id)
                }
                notePendingDelete = nil
            }
            Button("Cancel", role: .cancel) { notePendingDelete = nil }
        } message: {
            Text("This can't be undone.")
        }
    }

    /// Open Duo: keep a note open beside the list (the first one when
    /// nothing is chosen, or when the chosen one was deleted).
    private func syncSelection() {
        guard wide else { return }
        if let selectedID, store.userNotes.contains(where: { $0.id == selectedID }) { return }
        selectedID = firstNoteID
    }

    private func open(_ id: UUID) {
        userPicked = true
        if wide { selectedID = id } else { path = [id] }
    }

    private func compose() {
        let id = store.createBlankNote(category: initialCategoryForNewNote)
        open(id)
    }

    // MARK: List

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "+" sits beside the title AND count line (bottom-aligned),
            // so it stays clear of the status bar on the open Duo.
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    PageTitle(text: "Notes")
                    Text("\(store.userNotes.count) note\(store.userNotes.count == 1 ? "" : "s") · on this device only")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            // In the clock's row, like Today (Nov 12).
            .padding(.top, 30)

            // Compose lives beside the menu button in the corner now.
            searchField
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip("All", isSelected: categoryFilter == .all) { categoryFilter = .all }
                    ForEach(store.noteCategories, id: \.self) { name in
                        categoryChip(name, isSelected: categoryFilter == .named(name)) {
                            categoryFilter = .named(name)
                        }
                    }
                    categoryChip("Uncategorized", isSelected: categoryFilter == .uncategorized) {
                        categoryFilter = .uncategorized
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 12)

            if store.userNotes.isEmpty {
                emptyStateView
            } else if filteredNotes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(searchText.isEmpty ? "No notes in this category" : "No notes match \"\(searchText)\"")
                        .font(.headline)
                    Text("Try a different word or category.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                Spacer()
            } else {
                List {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            ForEach(section.notes) { note in
                                noteButton(note)
                            }
                        } header: {
                            Text(section.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.text)
                                .textCase(nil)
                        }
                    }
                    // Bottom breathing room: the last row scrolls clear
                    // of the floating menu button (and the rest timer).
                    Color.clear
                        .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
                        .listRowBackground(Color.clear)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .infinityTopEdge()
            }
        }
        .withKeyboardDoneToolbar()
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(edges: .top)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField("Search", text: $searchText)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }

    /// One filter chip: selected = filled accent, unselected = card.
    private func categoryChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Theme.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Theme.card, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(label) notes")
    }

    /// One row: tap to open. Swipe right to pin/unpin, swipe left to
    /// delete (asks first); long-press for the same actions.
    private func noteButton(_ note: UserNote) -> some View {
        let isSelected = wide && note.id == selectedID
        return Button { open(note.id) } label: {
            noteRow(note)
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.35) : Theme.card)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { store.setNotePinned(note, pinned: !note.isPinned) } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            .tint(Color.accentColor)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { notePendingDelete = note } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button { store.setNotePinned(note, pinned: !note.isPinned) } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) { notePendingDelete = note } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Apple Notes row: bold title, then time/date + preview on one
    /// line, then the category (and the workout it came from).
    private func noteRow(_ note: UserNote) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.displayTitle)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(Self.rowDate(note.updatedAt))
                    .font(.subheadline)
                    .foregroundStyle(Theme.text.opacity(0.85))
                Text(note.previewLine.isEmpty ? "No additional text" : note.previewLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            if note.category != nil || note.workoutTitle != nil {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                    Text([note.category, note.workoutTitle].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: Detail (open Duo)

    @ViewBuilder
    private var detailPane: some View {
        if let selectedID, store.userNotes.contains(where: { $0.id == selectedID }) {
            NavigationStack {
                NoteDetailView(noteID: selectedID)
            }
            // A new view per note, so switching notes saves and closes
            // the previous one (and drops it if it was left blank).
            .id(selectedID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No note open", systemImage: "note.text",
                                   description: Text("Tap the blue compose button to write one."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyStateView: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "note.text")
                    .scaledFont(size: 44)
                    .foregroundStyle(Theme.tertiaryText)
                Text("No notes yet")
                    .font(.headline)
                Text("Notes you write on a workout show up here when you save the workout. Tap compose to write a free note anytime.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 440)
    }

    // MARK: Dates

    /// Apple Notes groups: Today, Yesterday, Previous 7 Days, Previous
    /// 30 Days, then month (and year when it isn't this year).
    static func groupTitle(for date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        if days < 7 { return "Previous 7 Days" }
        if days < 30 { return "Previous 30 Days" }
        let sameYear = cal.component(.year, from: date) == cal.component(.year, from: now)
        return date.formatted(sameYear ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
    }

    /// Row date: time today, weekday this week, otherwise the date.
    static func rowDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.month(.defaultDigits).day().year(.twoDigits))
    }
}

private extension UserNote {
    var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Note page (open a note and type in it)

/// One note as its own page, like Apple Notes: the date at the top, the
/// title, then the body — all editable in place, saved as you type.
/// Pin, category and delete live in the top-right menu. A note left
/// blank is removed when you leave it.
private struct NoteDetailView: View {
    let noteID: UUID
    @EnvironmentObject var store: WorkoutStore
    /// Open Duo: no nav bar — the note starts at the top of its page with
    /// its actions inline on the left (clear of the clock, Nov 12).
    @Environment(\.duoWide) private var wide
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var loaded = false
    @State private var showDeleteConfirm = false
    @State private var addingCategory = false
    @State private var newCategoryName = ""
    @FocusState private var focus: Field?
    /// Pending autosave: typing saves after a short pause, not on every
    /// keystroke (each save re-sorts and writes every note).
    @State private var saveTask: Task<Void, Never>?

    private enum Field { case title, body }

    private var note: UserNote? { store.userNotes.first { $0.id == noteID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let note {
                HStack(spacing: 10) {
                    if wide { actionsMenu.font(.title2) }
                    Text(note.updatedAt.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: wide ? nil : .infinity)
                    if wide { Spacer(minLength: 0) }
                }
                if let workout = note.workoutTitle {
                    Text("From \(workout)")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                }
            }
            TextField("Title", text: $title, axis: .vertical)
                .font(.title.weight(.bold))
                .focused($focus, equals: .title)
                .submitLabel(.next)
                .onSubmit { focus = .body }
            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty {
                    Text("Write a note…")
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $bodyText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .body)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        // Top-aligned: the date and title always sit right under the
        // bar (centered, they slid up under it when the pane's stack
        // measured taller than the screen).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(wide ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { if !wide { actionsMenu } }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
        .onAppear {
            guard !loaded, let note else { return }
            loaded = true
            title = note.title
            bodyText = note.body
            // A brand-new note starts with the cursor in the title.
            if note.title.isEmpty && note.body.isEmpty {
                // After the push/selection settles, or focus is dropped.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = .title }
            }
        }
        .onChange(of: title) { _, _ in scheduleSave() }
        .onChange(of: bodyText) { _, _ in scheduleSave() }
        .onDisappear {
            saveTask?.cancel()
            save()
            // Leaving a blank note removes it (nothing was written).
            if let note, note.isBlank { store.deleteUserNote(id: note.id) }
        }
        .alert("Delete this note?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                store.deleteUserNote(id: noteID)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This can't be undone.")
        }
        .alert("New category", isPresented: $addingCategory) {
            TextField("Name", text: $newCategoryName)
            Button("Add") {
                let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    store.addNoteCategory(name)
                    store.setNoteCategory(id: noteID, category: name)
                }
                newCategoryName = ""
            }
            Button("Cancel", role: .cancel) { newCategoryName = "" }
        }
    }

    private func save() {
        guard loaded else { return }
        store.editUserNote(id: noteID, title: title, body: bodyText)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private var actionsMenu: some View {
        Menu {
            if let note {
                Button { store.setNotePinned(note, pinned: !note.isPinned) } label: {
                    Label(note.isPinned ? "Unpin Note" : "Pin Note", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                Menu {
                    Picker("Category", selection: Binding(
                        get: { note.category },
                        set: { store.setNoteCategory(id: noteID, category: $0) }
                    )) {
                        Text("None").tag(String?.none)
                        ForEach(store.noteCategories, id: \.self) { name in
                            Text(name).tag(Optional(name))
                        }
                    }
                    Button("New Category…") { addingCategory = true }
                } label: {
                    Label(note.category.map { "Category: \($0)" } ?? "Category", systemImage: "folder")
                }
                Divider()
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Delete Note", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Note actions")
    }
}
