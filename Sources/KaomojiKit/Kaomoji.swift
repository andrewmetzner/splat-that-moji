import Foundation

public struct Kaomoji: Hashable, Sendable, Identifiable {
    public let text: String
    /// Search keywords, most descriptive first.
    public let tags: [String]
    /// Browse category ids (see `KaomojiCategory`).
    public let categories: [String]
    /// Rough measure of how common/canonical this kaomoji is (appears in more datasets → higher).
    public let popularity: Int
    /// Came from one of the user's own TSV files.
    public let isCustom: Bool

    public var id: String { text }

    public init(text: String, tags: [String] = [], categories: [String] = [], popularity: Int = 0, isCustom: Bool = false) {
        self.text = text
        self.tags = tags
        self.categories = categories
        self.popularity = popularity
        self.isCustom = isCustom
    }
}

public struct KaomojiCategory: Hashable, Sendable, Identifiable, Decodable {
    public let id: String
    public let name: String
    public let icon: String
    public let count: Int
}

public struct KaomojiSource: Hashable, Sendable, Decodable {
    public let name: String
    public let url: String
    public let commit: String
    public let license: String
    public let unique: Int
}

struct KaomojiMeta: Decodable {
    var count: Int = 0
    var generated: String = ""
    var sources: [KaomojiSource] = []
    var categories: [KaomojiCategory] = []
    var synonyms: [String: [String]] = [:]
}
