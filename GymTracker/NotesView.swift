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
    @State private var notePendingDelete: UserNote?
    /// Folded: the pushed note.
    @State private var path: [UUID] = []
    /// Open Duo: the note shown beside the list.
    @State private var selectedID: UUID?
    /// True once a note was opened by hand (not the first note shown
    /// automatically). Folding only carries a hand-opened note over.
    @State private var userPicked = false
    /// Files-style browsing (DaRon): the folder that's open (a category,
    /// or Pinned); nil = the top level.
    @State private var openFolder: String?
    /// View options (the ⋯ menu), remembered like Files does.
    @AppStorage("gymtracker.notesView.v1", store: SharedDefaults.shared) private var viewStyleRaw = NotesViewStyle.icons.rawValue
    @AppStorage("gymtracker.notesSort.v1", store: SharedDefaults.shared) private var sortRaw = NotesSort.edited.rawValue
    @AppStorage("gymtracker.notesSortAscending.v1", store: SharedDefaults.shared) private var sortAscending = false
    @AppStorage("gymtracker.notesFoldersOnTop.v1", store: SharedDefaults.shared) private var foldersOnTop = true
    @AppStorage("gymtracker.notesIconSize.v1", store: SharedDefaults.shared) private var iconSizeRaw = NotesIconSize.standard.rawValue

    private var viewStyle: NotesViewStyle { NotesViewStyle(rawValue: viewStyleRaw) ?? .icons }
    private var sort: NotesSort { NotesSort(rawValue: sortRaw) ?? .edited }
    private var iconSize: NotesIconSize { NotesIconSize(rawValue: iconSizeRaw) ?? .standard }

    private static let pinnedFolder = "Pinned"

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searching: Bool { !query.isEmpty }

    private func matches(_ note: UserNote) -> Bool {
        note.title.localizedCaseInsensitiveContains(query)
            || note.body.localizedCaseInsensitiveContains(query)
            || (note.workoutTitle?.localizedCaseInsensitiveContains(query) ?? false)
    }

    /// Notes in the chosen order (the ⋯ menu's Sort By).
    private func sorted(_ notes: [UserNote]) -> [UserNote] {
        let up = sortAscending
        return notes.sorted { a, b in
            switch sort {
            case .name:
                let r = a.displayTitle.localizedStandardCompare(b.displayTitle)
                return up ? r == .orderedAscending : r == .orderedDescending
            case .edited:
                return up ? a.updatedAt < b.updatedAt : a.updatedAt > b.updatedAt
            case .created:
                return up ? a.createdAt < b.createdAt : a.createdAt > b.createdAt
            case .category:
                let ca = a.category ?? "~", cb = b.category ?? "~"
                if ca != cb {
                    let r = ca.localizedStandardCompare(cb)
                    return up ? r == .orderedAscending : r == .orderedDescending
                }
                return a.updatedAt > b.updatedAt
            }
        }
    }

    /// The notes in the open folder (or the search results, which cover
    /// every folder, like Files).
    private var notesHere: [UserNote] {
        if searching { return sorted(store.userNotes.filter(matches)) }
        let known = Set(store.noteCategories)
        switch openFolder {
        case nil:
            return sorted(store.userNotes.filter { !$0.isPinned && ($0.category.map { !known.contains($0) } ?? true) })
        case Self.pinnedFolder?:
            return sorted(store.userNotes.filter(\.isPinned))
        case let name?:
            return sorted(store.userNotes.filter { $0.category == name })
        }
    }

    /// The folders at the top level: Pinned (when anything is), then one
    /// per category, empty ones included.
    private var foldersHere: [NotesItem] {
        guard openFolder == nil, !searching else { return [] }
        var result: [NotesItem] = []
        let pinned = store.userNotes.filter(\.isPinned)
        if !pinned.isEmpty {
            result.append(.folder(name: Self.pinnedFolder, count: pinned.count, latest: pinned.map(\.updatedAt).max()))
        }
        for name in store.noteCategories {
            let inside = store.userNotes.filter { $0.category == name }
            result.append(.folder(name: name, count: inside.count, latest: inside.map(\.updatedAt).max()))
        }
        switch sort {
        case .name:
            result.sort {
                let r = $0.name.localizedStandardCompare($1.name)
                return sortAscending ? r == .orderedAscending : r == .orderedDescending
            }
        case .edited:
            result.sort { a, b in
                let da = a.date ?? .distantPast, db = b.date ?? .distantPast
                return sortAscending ? da < db : da > db
            }
        case .created, .category:
            break  // the user's own folder order
        }
        return result
    }

    /// Everything shown, folders first unless Folders on Top is off.
    private var items: [NotesItem] {
        let folders = foldersHere
        let notes = notesHere.map(NotesItem.note)
        if foldersOnTop { return folders + notes }
        let merged = folders + notes
        switch sort {
        case .name:
            return merged.sorted {
                let r = $0.name.localizedStandardCompare($1.name)
                return sortAscending ? r == .orderedAscending : r == .orderedDescending
            }
        default:
            return merged.sorted { a, b in
                let da = a.date ?? .distantPast, db = b.date ?? .distantPast
                return sortAscending ? da < db : da > db
            }
        }
    }

    /// The note the open Duo shows first: the first in the chosen order.
    private var firstNoteID: UUID? { sorted(store.userNotes).first?.id }

    /// A new note starts in the folder that's open.
    private var initialCategoryForNewNote: String? {
        guard let openFolder, openFolder != Self.pinnedFolder else { return nil }
        return openFolder
    }

    /// Each folder's color, like Files' tag colors.
    private func folderColor(_ name: String) -> Color {
        switch name {
        case Self.pinnedFolder: return Theme.vividOrange
        case "Workout": return Color.accentColor
        case "Food": return Theme.vividGreen
        case "General": return Color(.systemGray)
        default:
            let others: [Color] = [.teal, .purple, .pink, .indigo, .mint]
            let i = (store.noteCategories.firstIndex(of: name) ?? 0) % others.count
            return others[i]
        }
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
                        // (A plain Divider in an overlay draws horizontal —
                        // it cut across the middle of the note.)
                        .overlay(alignment: swapped ? .leading : .trailing) {
                            Rectangle().fill(Theme.border).frame(width: 0.5)
                        }
                } main: {
                    // Same black as the note page beside it.
                    listPane
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

    // MARK: List (Files-style, DaRon Nov 12)

    private var countLine: String {
        if searching {
            let n = notesHere.count
            return "\(n) result\(n == 1 ? "" : "s")"
        }
        let f = foldersHere.count, n = notesHere.count
        let notes = "\(n) note\(n == 1 ? "" : "s")"
        return openFolder == nil ? "\(f) folder\(f == 1 ? "" : "s"), \(notes)" : notes
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if openFolder != nil {
                    Button {
                        withAnimation(AppAnimation.snappy) { openFolder = nil }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to Notes")
                }
                PageTitle(text: openFolder ?? "Notes")
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            // In the clock's row, like Today (Nov 12).
            .padding(.top, 30)

            HStack(spacing: 10) {
                searchField
                viewMenu
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            HStack {
                Text(countLine)
                Spacer()
                Text("Sorted by \(sort.label)")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if store.userNotes.isEmpty && openFolder == nil {
                emptyStateView
            } else if items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(searching ? "No notes match \"\(query)\"" : "This folder is empty")
                        .font(.headline)
                    Text(searching ? "Try a different word." : "Tap the compose button to write a note here.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                Spacer()
            } else if viewStyle == .icons {
                iconGrid
            } else {
                itemList
            }
        }
        .withKeyboardDoneToolbar()
        .scrollDismissesKeyboard(.interactively)
        .ignoresSafeArea(edges: .top)
    }

    /// The ⋯ menu: view style, icon size, sort, folders on top.
    private var viewMenu: some View {
        Menu {
            Picker("View", selection: $viewStyleRaw) {
                Label("Icons", systemImage: "square.grid.2x2").tag(NotesViewStyle.icons.rawValue)
                Label("List", systemImage: "list.bullet").tag(NotesViewStyle.list.rawValue)
            }
            .pickerStyle(.inline)
            if viewStyle == .icons {
                Picker("Icon Size", selection: $iconSizeRaw) {
                    ForEach(NotesIconSize.allCases, id: \.self) { size in
                        Text(size.label).tag(size.rawValue)
                    }
                }
                // Right in the menu, like Files' view options.
                .pickerStyle(.palette)
            }
            Section("Sort By") {
                ForEach(NotesSort.allCases, id: \.self) { option in
                    Button {
                        // Picking the current sort again flips its order.
                        if sort == option {
                            sortAscending.toggle()
                        } else {
                            sortRaw = option.rawValue
                            sortAscending = option == .name || option == .category
                        }
                    } label: {
                        if sort == option {
                            Label(option.label, systemImage: sortAscending ? "chevron.up" : "chevron.down")
                        } else {
                            Text(option.label)
                        }
                    }
                }
            }
            Toggle("Folders on Top", isOn: $foldersOnTop)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Theme.card, in: Circle())
                .overlay(Circle().stroke(Theme.border, lineWidth: 1))
        }
        .accessibilityLabel("View options")
    }

    // MARK: Icons

    private var iconGrid: some View {
        let size = iconSize
        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: size.columns),
                      alignment: .center, spacing: 18) {
                ForEach(items) { item in
                    switch item {
                    case .folder(let name, let count, _):
                        folderIcon(name: name, count: count, size: size)
                    case .note(let note):
                        noteIcon(note, size: size)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Color.clear
                .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
        }
        .infinityTopEdge()
        .animation(AppAnimation.snappy, value: iconSizeRaw)
    }

    private func itemsText(_ count: Int) -> String { "\(count) item\(count == 1 ? "" : "s")" }

    private func folderIcon(name: String, count: Int, size: NotesIconSize) -> some View {
        Button {
            withAnimation(AppAnimation.snappy) { openFolder = name }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: name == Self.pinnedFolder ? "pin.square.fill" : "folder.fill")
                    .font(.system(size: size.folder))
                    .foregroundStyle(folderColor(name))
                    .frame(height: size.page.height)
                Text(name)
                    .font(size == .small ? .caption : .subheadline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(itemsText(count))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) folder, \(itemsText(count))")
    }

    private func noteIcon(_ note: UserNote, size: NotesIconSize) -> some View {
        let isSelected = wide && note.id == selectedID
        return Button { open(note.id) } label: {
            VStack(spacing: 4) {
                notePage(note, size: size.page)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                            .padding(-3)
                    )
                Text(note.displayTitle)
                    .font(size == .small ? .caption : .subheadline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(Self.rowDate(note.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { noteActions(note) }
    }

    /// A note's thumbnail: a little page with its title and text, like
    /// a document in Files.
    private func notePage(_ note: UserNote, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(note.displayTitle)
                .font(.system(size: max(4, size.width / 8), weight: .bold))
                .lineLimit(2)
            Text(note.body)
                .font(.system(size: max(3, size.width / 11)))
                .lineLimit(nil)
        }
        .foregroundStyle(Color(white: 0.2))
        .padding(size.width * 0.1)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .accessibilityHidden(true)
    }

    // MARK: List view

    private var itemList: some View {
        List {
            ForEach(items) { item in
                switch item {
                case .folder(let name, let count, _):
                    Button {
                        withAnimation(AppAnimation.snappy) { openFolder = name }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: name == Self.pinnedFolder ? "pin.square.fill" : "folder.fill")
                                .font(.title2)
                                .foregroundStyle(folderColor(name))
                                .frame(width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(.body).foregroundStyle(Theme.text)
                                Text(itemsText(count)).font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                case .note(let note):
                    noteButton(note)
                }
            }
            // Bottom breathing room: the last row scrolls clear of the
            // floating menu button (and the rest timer).
            Color.clear
                .frame(height: LayoutClearance.bottom(restActive: store.isRestActive, fabOffset: fabBottomOffset))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .infinityTopEdge()
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

    /// Pin, move to a folder, delete — the long-press menu.
    @ViewBuilder
    private func noteActions(_ note: UserNote) -> some View {
        Button { store.setNotePinned(note, pinned: !note.isPinned) } label: {
            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
        }
        Menu {
            Button("None") { store.setNoteCategory(id: note.id, category: nil) }
            ForEach(store.noteCategories, id: \.self) { name in
                Button(name) { store.setNoteCategory(id: note.id, category: name) }
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
        Button(role: .destructive) { notePendingDelete = note } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// One row: tap to open. Swipe right to pin/unpin, swipe left to
    /// delete (asks first); long-press for the same actions.
    private func noteButton(_ note: UserNote) -> some View {
        let isSelected = wide && note.id == selectedID
        return Button { open(note.id) } label: {
            noteRow(note)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
        )
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
        .contextMenu { noteActions(note) }
    }

    /// Files list row: a little page, the title, then the date.
    private func noteRow(_ note: UserNote) -> some View {
        HStack(spacing: 12) {
            notePage(note, size: CGSize(width: 24, height: 31))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(Self.rowDate(note.updatedAt))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Files-style browsing types

private enum NotesViewStyle: String { case icons, list }

private enum NotesSort: String, CaseIterable {
    case name, edited, created, category
    var label: String {
        switch self {
        case .name: return "Name"
        case .edited: return "Date Edited"
        case .created: return "Date Created"
        case .category: return "Category"
        }
    }
}

/// Icon sizes (DaRon: three sizes, none large): Standard is the
/// mockup's three across; Medium and Small fit more.
private enum NotesIconSize: String, CaseIterable {
    case small, medium, standard
    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .standard: return "Standard"
        }
    }
    var columns: Int {
        switch self { case .small: return 5; case .medium: return 4; case .standard: return 3 }
    }
    var folder: CGFloat {
        switch self { case .small: return 36; case .medium: return 46; case .standard: return 58 }
    }
    var page: CGSize {
        switch self {
        case .small: return CGSize(width: 34, height: 44)
        case .medium: return CGSize(width: 44, height: 57)
        case .standard: return CGSize(width: 56, height: 72)
        }
    }
}

/// One thing in the browser: a folder (a category, or Pinned) or a note.
private enum NotesItem: Identifiable {
    case folder(name: String, count: Int, latest: Date?)
    case note(UserNote)
    var id: String {
        switch self {
        case .folder(let name, _, _): return "folder-\(name)"
        case .note(let note): return "note-\(note.id)"
        }
    }
    var name: String {
        switch self {
        case .folder(let name, _, _): return name
        case .note(let note): return note.displayTitle
        }
    }
    var date: Date? {
        switch self {
        case .folder(_, _, let latest): return latest
        case .note(let note): return note.updatedAt
        }
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
                    Text(note.updatedAt.formatted(date: .long, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: wide ? nil : .infinity)
                    if wide {
                        Spacer(minLength: 0)
                        actionsMenu.font(.title2)
                    }
                }
                linkedWorkout(for: note)
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
                        .allowsHitTesting(false)
                }
                TextEditor(text: $bodyText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .body)
                    // The editor pads its text 5pt in from its edge; pull
                    // it out so the note lines up with the title.
                    .padding(.horizontal, -5)
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

    /// The workout this note goes with: the one it was written on, or
    /// the workout logged (or planned) the day it was made. Tap to open
    /// that day on the Calendar.
    @ViewBuilder
    private func linkedWorkout(for note: UserNote) -> some View {
        let cal = Calendar.current
        let day = cal.startOfDay(for: note.createdAt)
        let title = note.workoutTitle
            ?? store.sessions.first(where: { cal.isDate($0.date, inSameDayAs: day) })?.dayTitle
            ?? store.programDay(for: day)?.title
        if let title {
            Button {
                store.calendarJumpRequest = day
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell")
                        .foregroundStyle(Color.accentColor)
                    Text("Linked to ")
                        .foregroundStyle(Theme.secondaryText)
                    + Text("\(day.formatted(.dateTime.weekday(.abbreviated))) · \(title)")
                        .foregroundStyle(Theme.text)
                        .fontWeight(.semibold)
                    Spacer(minLength: 8)
                    Text("Open")
                        .foregroundStyle(Theme.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .themeCard(cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Linked to \(title) on \(day.formatted(.dateTime.weekday(.wide).month().day())). Open in Calendar")
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
