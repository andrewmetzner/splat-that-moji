import AppKit
import Combine
import KaomojiKit

enum PickerScope: Hashable, Identifiable {
    case all, recents, favorites, custom
    case category(KaomojiCategory)

    var id: String {
        switch self {
        case .all: "all"
        case .recents: "recents"
        case .favorites: "favorites"
        case .custom: "custom"
        case .category(let c): "cat:" + c.id
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .recents: "Recent"
        case .favorites: "Favorites"
        case .custom: "Mine"
        case .category(let c): c.name
        }
    }

    var symbol: String? {
        switch self {
        case .all: "square.grid.2x2"
        case .recents: "clock"
        case .favorites: "star"
        case .custom: "person"
        case .category: nil
        }
    }
}

struct PickerNotice: Equatable {
    var message: String
    var offersAccessibilitySettings = false
}

@MainActor
final class PickerModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { refresh() } }
    }
    @Published var scope: PickerScope = .all {
        didSet { if scope != oldValue { refresh() } }
    }
    @Published private(set) var results: [Kaomoji] = []
    /// Bumped whenever `results` is replaced, so the grid can scroll back to the top.
    @Published private(set) var resultsVersion = 0
    @Published var selection = 0
    /// How many results the grid renders; grows as you scroll or arrow down.
    @Published private(set) var visibleLimit = PickerModel.pageSize
    @Published var notice: PickerNotice?
    /// Bumped to put keyboard focus back in the search field.
    @Published private(set) var focusRequest = 0

    static let pageSize = 240

    let store: KaomojiStore
    let library: UserLibrary
    let settings: AppSettings
    private var searchTask: Task<Void, Never>?
    private var subscriptions = Set<AnyCancellable>()

    init(store: KaomojiStore, library: UserLibrary, settings: AppSettings) {
        self.store = store
        self.library = library
        self.settings = settings
        store.$database.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
    }

    var scopes: [PickerScope] {
        var scopes: [PickerScope] = [.all, .recents, .favorites]
        guard let db = store.database else { return scopes }
        if !db.customIndices.isEmpty { scopes.append(.custom) }
        scopes += db.categories.map(PickerScope.category)
        return scopes
    }

    var selected: Kaomoji? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    var columns: Int { settings.columns }

    /// Called each time the panel opens.
    func reset() {
        notice = nil
        query = ""
        scope = .all
        refresh()
        focusRequest += 1
    }

    func refresh() {
        searchTask?.cancel()
        guard let db = store.database else {
            replaceResults([])
            return
        }
        let base = baseIndices(in: db)
        let query = query.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            replaceResults(browseList(in: db, base: base))
            return
        }
        let boosts = library.boosts(in: db)
        searchTask = Task {
            let indices = await Task.detached(priority: .userInitiated) {
                db.search(query, within: base, boosts: boosts)
            }.value
            guard !Task.isCancelled else { return }
            replaceResults(indices.map { db.entries[$0] })
        }
    }

    // MARK: Selection

    func move(by delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
        loadMore(near: selection)
    }

    func loadMore(near index: Int) {
        if index >= visibleLimit - columns * 4, visibleLimit < results.count {
            visibleLimit = min(results.count, visibleLimit + Self.pageSize)
        }
    }

    func cycleScope(forward: Bool) {
        let all = scopes
        guard let i = all.firstIndex(of: scope) else { return }
        scope = all[(i + (forward ? 1 : all.count - 1)) % all.count]
    }

    func requestFocus() { focusRequest += 1 }

    // MARK: Building lists

    private func replaceResults(_ new: [Kaomoji]) {
        results = new
        selection = 0
        visibleLimit = min(max(new.count, 1), Self.pageSize)
        resultsVersion += 1
    }

    private func baseIndices(in db: KaomojiDatabase) -> [Int]? {
        switch scope {
        case .all: nil
        case .recents: library.recents.compactMap(db.index(of:))
        case .favorites: library.favorites.compactMap(db.index(of:))
        case .custom: db.customIndices
        case .category(let c): db.members(ofCategory: c.id)
        }
    }

    /// What to show before anything is typed: like Splatmoji, recent picks come first.
    private func browseList(in db: KaomojiDatabase, base: [Int]?) -> [Kaomoji] {
        func lookup(_ text: String) -> Kaomoji {
            db.index(of: text).map { db.entries[$0] } ?? Kaomoji(text: text)
        }
        switch scope {
        case .recents:
            return library.recents.map(lookup)
        case .favorites:
            return library.favorites.map(lookup)
        case .all:
            let pinned = library.recents + library.favorites.filter { !library.recents.contains($0) }
            let pinnedSet = Set(pinned)
            return pinned.map(lookup) + db.entries.lazy.filter { !pinnedSet.contains($0.text) }
        case .custom, .category:
            return (base ?? []).map { db.entries[$0] }
        }
    }
}
