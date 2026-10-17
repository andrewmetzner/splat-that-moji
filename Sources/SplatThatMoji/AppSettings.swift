import AppKit
import KaomojiKit

/// How a chosen kaomoji reaches the app you were typing in (Splatmoji's copy/type/copypaste).
enum InsertMode: String, CaseIterable, Identifiable {
    case paste, type, copy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paste: "Paste"
        case .type: "Type"
        case .copy: "Copy only"
        }
    }

    var detail: String {
        switch self {
        case .paste: "Pastes into the app you were using, then puts your clipboard back. Works almost everywhere."
        case .type: "Types the characters directly without touching the clipboard. Some apps drop unusual characters."
        case .copy: "Just copies to the clipboard; you paste it yourself."
        }
    }

    var needsAccessibility: Bool { self != .copy }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var hotKey: KeyCombo {
        didSet { defaults.set(try? JSONEncoder().encode(hotKey), forKey: "hotKey") }
    }
    @Published var insertMode: InsertMode {
        didSet { defaults.set(insertMode.rawValue, forKey: "insertMode") }
    }
    @Published var restoreClipboard: Bool {
        didSet { defaults.set(restoreClipboard, forKey: "restoreClipboard") }
    }
    @Published var escapeMarkdown: Bool {
        didSet { defaults.set(escapeMarkdown, forKey: "escapeMarkdown") }
    }
    @Published var columns: Int {
        didSet { defaults.set(columns, forKey: "columns") }
    }
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: "fontSize") }
    }
    @Published var historyLength: Int {
        didSet { defaults.set(historyLength, forKey: "historyLength") }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }

    /// True while the shortcut recorder is listening, so the old shortcut doesn't fire.
    @Published var isRecordingHotKey = false

    let isFirstLaunch: Bool

    init() {
        defaults.register(defaults: [
            "insertMode": InsertMode.paste.rawValue,
            "restoreClipboard": true,
            "escapeMarkdown": false,
            "columns": 4,
            "fontSize": 18.0,
            "historyLength": 36,
            "showMenuBarIcon": true,
        ])
        hotKey = defaults.data(forKey: "hotKey").flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .default
        insertMode = InsertMode(rawValue: defaults.string(forKey: "insertMode") ?? "") ?? .paste
        restoreClipboard = defaults.bool(forKey: "restoreClipboard")
        escapeMarkdown = defaults.bool(forKey: "escapeMarkdown")
        columns = min(max(defaults.integer(forKey: "columns"), 2), 8)
        fontSize = min(max(defaults.double(forKey: "fontSize"), 12), 32)
        historyLength = min(max(defaults.integer(forKey: "historyLength"), 5), 200)
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        isFirstLaunch = !defaults.bool(forKey: "hasLaunched")
        defaults.set(true, forKey: "hasLaunched")
    }
}

/// The user's favorites, recently used kaomoji, and how often each has been used.
@MainActor
final class UserLibrary: ObservableObject {
    private let defaults = UserDefaults.standard

    /// Newest first.
    @Published private(set) var favorites: [String]
    /// Most recent first.
    @Published private(set) var recents: [String]
    private(set) var useCounts: [String: Int]
    private var favoriteSet: Set<String>

    init() {
        let favorites = defaults.stringArray(forKey: "favorites") ?? []
        self.favorites = favorites
        favoriteSet = Set(favorites)
        recents = defaults.stringArray(forKey: "recents") ?? []
        useCounts = defaults.dictionary(forKey: "useCounts") as? [String: Int] ?? [:]
    }

    func isFavorite(_ text: String) -> Bool { favoriteSet.contains(text) }

    func toggleFavorite(_ text: String) {
        if favoriteSet.remove(text) != nil {
            favorites.removeAll { $0 == text }
        } else {
            favoriteSet.insert(text)
            favorites.insert(text, at: 0)
        }
        defaults.set(favorites, forKey: "favorites")
    }

    func recordUse(_ text: String, historyLength: Int) {
        recents.removeAll { $0 == text }
        recents.insert(text, at: 0)
        if recents.count > historyLength { recents.removeLast(recents.count - historyLength) }
        useCounts[text, default: 0] += 1
        defaults.set(recents, forKey: "recents")
        defaults.set(useCounts, forKey: "useCounts")
    }

    func clearRecents() {
        recents = []
        useCounts = [:]
        defaults.set(recents, forKey: "recents")
        defaults.set(useCounts, forKey: "useCounts")
    }

    func clearFavorites() {
        favorites = []
        favoriteSet = []
        defaults.set(favorites, forKey: "favorites")
    }

    /// Search score bonuses so favorites and often-used kaomoji float up.
    func boosts(in database: KaomojiDatabase) -> [Int: Int] {
        var boosts = [Int: Int]()
        for (text, count) in useCounts {
            if let i = database.index(of: text) { boosts[i, default: 0] += min(count, 10) * 30 }
        }
        for text in favorites {
            if let i = database.index(of: text) { boosts[i, default: 0] += 200 }
        }
        return boosts
    }
}
