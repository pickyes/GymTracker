import SwiftUI

/// Notes page — the fourth page in the floating menu (Today / History /
/// Profile / Notes).
///
/// Feels like a notes app, built from scratch with our own styling: a
/// list of notes (title + preview line + date), tap a note to open it
/// and edit it, a compose button for a new note, search across notes.
/// No Apple assets, no copied icons or artwork — the layout language
/// (title, preview, date) is the familiar notes pattern, the
/// implementation and styling are ours.
///
/// Where notes come from (all on-device, like everything else):
/// - Workout notes: written in the per-exercise note field on Today,
///   saved with the workout (title = the exercise, subtitle = the day).
/// - Free notes: written here with the + button.
///
/// Actions (DaRon 22:42): pin a note to the top, edit it, delete it
/// (asks first), and file it in a category.
struct NotesView: View {
    @Environment(\.fabBottomOffset) private var fabBottomOffset
    @EnvironmentObject var store: WorkoutStore
    @State private var searchText = ""
    @State private var editorTarget: EditorTarget?
    @State private var categoryFilter: CategoryFilter = .all
    @State private var notePendingDelete: UserNote?

    /// A note open in the editor: an existing note, or nil for a new one.
    private struct EditorTarget: Identifiable {
        var id = UUID()
        var note: UserNote?
        var initialCategory: String?
    }

    /// Category filter for the list. Nil (All) shows everything.
    private enum CategoryFilter: Hashable {
        case all
        case uncategorized
        case named(String)
    }

    /// Notes matching the search + category filter, pinned first, then
    /// most recently edited. Pinned notes stay on top.
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
        return notes.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private var pinnedNotes: [UserNote] { filteredNotes.filter { $0.isPinned } }
    private var otherNotes: [UserNote] { filteredNotes.filter { !$0.isPinned } }

    /// The category a new note starts in: the one being filtered on,
    /// if any — otherwise none.
    private var initialCategoryForNewNote: String? {
        if case .named(let name) = categoryFilter { return name }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title lines up with the content below it (same 16pt
            // leading), not flush to the edge — like every page.
            // "+" sits beside the title AND count line (bottom-aligned),
            // so it stays clear of the status bar on the open Duo, where
            // a title-row button ran into the Wi-Fi/time cluster.
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    PageTitle(text: "Notes")
                    Text("\(store.userNotes.count) note\(store.userNotes.count == 1 ? "" : "s") · on this device only")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                // Compose: same vivid "+" as the workout actions.
                Button { editorTarget = EditorTarget(note: nil, initialCategory: initialCategoryForNewNote) } label: {
                    Image(systemName: "plus")
                        .scaledFont(size: 26, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: Circle())
                        .shadow(color: Color.accentColor.opacity(0.5), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New note")
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.top, 2)


            // Search across notes (title + body + workout).
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.secondaryText)
                TextField("Search notes", text: $searchText)
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
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Category filter chips: All, each category, Uncategorized.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip("All", isSelected: categoryFilter == .all) {
                        categoryFilter = .all
                    }
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
                    if !pinnedNotes.isEmpty {
                        Section {
                            ForEach(pinnedNotes) { note in
                                noteButton(note)
                            }
                        } header: {
                            Text("Pinned")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    ForEach(otherNotes) { note in
                        noteButton(note)
                    }
                    // Bottom breathing room (shared LayoutClearance
                    // rule, Debug Pass 2): the list had no bottom
                    // spacer at all, so the last note row sat at the
                    // safe-area bottom — under the floating menu button
                    // (and the rest-timer panel while a rest runs) at
                    // scroll-bottom.
                    Color.clear
                        .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        // Keyboard Done + tap-outside (Debug Pass 2): the "Search
        // notes" field had no Done — the keyboard had no way out.
        // Done dismisses; the search filters live as you type, so
        // there is nothing to save.
        .withKeyboardDoneToolbar()
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTapOutside()
        .disableVerticalBar()
        .sheet(item: $editorTarget) { target in
            NoteEditorView(
                note: target.note,
                initialCategory: target.initialCategory,
                onSave: { title, body, category, isPinned in
                    if let existing = target.note {
                        store.updateUserNote(existing, title: title, body: body, category: category, isPinned: isPinned)
                    } else {
                        store.addUserNote(title: title, body: body, category: category)
                    }
                    editorTarget = nil
                },
                onDelete: target.note == nil ? nil : {
                    if let existing = target.note {
                        store.deleteUserNote(id: existing.id)
                    }
                    editorTarget = nil
                },
                isPinned: target.note?.isPinned ?? false,
                onCancel: { editorTarget = nil }
            )
        }
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

    /// One row as a button: tap to open the editor. Swipe left to
    /// delete (asks first), swipe right to pin/unpin; long-press menu
    /// offers pin, edit, and delete.
    private func noteButton(_ note: UserNote) -> some View {
        Button { editorTarget = EditorTarget(note: note, initialCategory: note.category) } label: {
            noteRow(note)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
            Button { editorTarget = EditorTarget(note: note, initialCategory: note.category) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) { notePendingDelete = note } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// One row: bold title (with a pin mark when pinned), then
    /// timestamp + preview on one line, then the category pill and the
    /// workout it came from (if any).
    private func noteRow(_ note: UserNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Pinned")
                }
                Text(note.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(noteTimestamp(note.updatedAt))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                if !note.previewLine.isEmpty {
                    Text(note.previewLine)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            if note.category != nil || note.workoutTitle != nil {
                HStack(spacing: 8) {
                    if let category = note.category {
                        Text(category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    if let workout = note.workoutTitle {
                        Text(workout)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var emptyStateView: some View {
        // D17 (2026-11-10): the old top padding + trailing Spacer
        // collapsed (the parent VStack has no height to stretch into),
        // so the content sat top-pinned with ~35% dead black below.
        // A measured minHeight centres it mid-screen instead — icon +
        // copy verbatim, no copy change.
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "note.text")
                    .scaledFont(size: 44)
                    .foregroundStyle(Theme.tertiaryText)
                Text("No notes yet")
                    .font(.headline)
                Text("Notes you write on a workout show up here when you save the workout. Tap + to write a free note anytime.")
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

    /// Full timestamp, date + time ("Nov 9, 9:51 PM") — the moment the
    /// note was typed (or last edited), not a bare "Today". (DaRon
    /// 21:51: notes must be timestamped correctly.)
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter
    }()

    private func noteTimestamp(_ date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }
}

// MARK: - Note editor (open a note, edit it, new note)

/// Full note editor in a sheet: title field on top, body below, Done
/// saves, Cancel throws the edits away. A blank note (no title, no
/// body) is never saved. Existing notes also get Pin and Delete buttons.
private struct NoteEditorView: View {
    @EnvironmentObject var store: WorkoutStore

    var note: UserNote?
    var initialCategory: String?
    var onSave: (String, String, String?, Bool) -> Void
    var onDelete: (() -> Void)?
    @State private var isPinned: Bool
    var onCancel: () -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var category: String?
    @State private var newCategoryName = ""
    @State private var addingCategory = false
    @State private var showDeleteConfirm = false

    init(note: UserNote?, initialCategory: String? = nil, onSave: @escaping (String, String, String?, Bool) -> Void, onDelete: (() -> Void)? = nil, isPinned: Bool = false, onCancel: @escaping () -> Void) {
        self.note = note
        self.initialCategory = initialCategory
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _isPinned = State(initialValue: isPinned)
        _title = State(initialValue: note?.title ?? "")
        _bodyText = State(initialValue: note?.body ?? "")
        _category = State(initialValue: note?.category ?? initialCategory)
    }

    private var isBlank: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .autocorrectionDisabled(false)
                Divider()
                // Category: pick one, or add a new one.
                HStack(spacing: 8) {
                    Text("Category")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Menu {
                        Button("None") { category = nil }
                        ForEach(store.noteCategories, id: \.self) { name in
                            Button(name) { category = name }
                        }
                        Button("New category…") { addingCategory = true }
                    } label: {
                        HStack(spacing: 4) {
                            Text(category ?? "None")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
                if addingCategory {
                    HStack(spacing: 8) {
                        TextField("New category name", text: $newCategoryName)
                            .autocorrectionDisabled()
                        Button("Add") {
                            let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            store.addNoteCategory(name)
                            category = name
                            newCategoryName = ""
                            addingCategory = false
                        }
                        .fontWeight(.semibold)
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Cancel") {
                            addingCategory = false
                            newCategoryName = ""
                        }
                        .foregroundStyle(Theme.secondaryText)
                    }
                }
                ZStack(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("Write a note…")
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $bodyText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let workout = note?.workoutTitle {
                    Text("From \(workout)")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding()
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(title, bodyText, category, isPinned) }
                        .fontWeight(.semibold)
                        .disabled(isBlank)
                }
                // Keyboard Done (Debug Pass 2): the Title / body /
                // new-category fields had no way out of the keyboard.
                // This Done only dismisses — the nav-bar Done above
                // saves (and stays disabled while the note is blank).
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissKeyboard() }
                }
                if onDelete != nil {
                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            // Pin lives in the editor's own state: it
                            // updates the label immediately and rides
                            // along with Done, so a pin can no longer be
                            // silently reverted by the save.
                            Button { isPinned.toggle() } label: {
                                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
                            }
                            Spacer()
                            Button(role: .destructive) { showDeleteConfirm = true } label: {
                                Label("Delete note", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .alert("Delete this note?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { onDelete?() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}
