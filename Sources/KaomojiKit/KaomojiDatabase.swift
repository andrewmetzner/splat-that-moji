import Foundation

/// An immutable, searchable set of kaomoji.
///
/// The bundled database is a TSV file whose first two columns match Splatmoji's format
/// (`<kaomoji> TAB <keyword, keyword, ...>`), optionally followed by browse category ids and
/// a popularity score. User files in the same format are merged in on load.
public final class KaomojiDatabase: Sendable {
    public let entries: [Kaomoji]
    public let categories: [KaomojiCategory]
    public let sources: [KaomojiSource]
    public let generated: String
    /// Indices of entries that came from the user's own files.
    public let customIndices: [Int]

    let synonyms: [String: [String]]
    let indexByText: [String: Int32]
    let categoryMembers: [String: [Int32]]

    /// Every distinct tag word, sorted, with the entries that use it. Each posting is
    /// `entryIndex << 1 | isPrimary`, where primary means the word is in one of the entry's
    /// first three (most descriptive) tags.
    let vocabulary: [String]
    let postings: [[Int32]]

    /// Lowercased UTF-8 of every kaomoji, newline-separated, for fast substring search.
    let textBlob: [UInt8]
    let textOffsets: [Int32]

    // MARK: Loading

    public static func load(databaseURL: URL, metaURL: URL? = nil, customURLs: [URL] = []) throws -> KaomojiDatabase {
        var meta = KaomojiMeta()
        if let metaURL {
            meta = try JSONDecoder().decode(KaomojiMeta.self, from: Data(contentsOf: metaURL))
        }
        var builder = Builder()
        // Custom files first: they sort ahead of the bundled set and their tags win.
        for url in customURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            builder.addTSV(data, custom: true)
        }
        builder.addTSV(try Data(contentsOf: databaseURL), custom: false)
        return KaomojiDatabase(
            entries: builder.entries, categories: meta.categories, sources: meta.sources,
            synonyms: meta.synonyms, generated: meta.generated
        )
    }

    public init(
        entries: [Kaomoji], categories: [KaomojiCategory] = [], sources: [KaomojiSource] = [],
        synonyms: [String: [String]] = [:], generated: String = ""
    ) {
        self.entries = entries
        self.categories = categories
        self.sources = sources
        self.synonyms = synonyms
        self.generated = generated

        var indexByText = [String: Int32](minimumCapacity: entries.count)
        var categoryMembers = [String: [Int32]]()
        var customIndices = [Int]()
        var postingsByWord = [String: [Int32]](minimumCapacity: 60_000)
        var blob = [UInt8]()
        blob.reserveCapacity(entries.count * 24)
        var offsets = [Int32]()
        offsets.reserveCapacity(entries.count + 1)

        var seen = [String]()
        for (i, entry) in entries.enumerated() {
            let index = Int32(i)
            indexByText[entry.text] = index
            if entry.isCustom { customIndices.append(i) }
            for category in entry.categories {
                categoryMembers[category, default: []].append(index)
            }

            seen.removeAll(keepingCapacity: true)
            for (tagIndex, tag) in entry.tags.enumerated() {
                for word in Self.words(in: tag) where !seen.contains(word) {
                    seen.append(word)
                    postingsByWord[word, default: []].append(index << 1 | (tagIndex < 3 ? 1 : 0))
                }
            }

            offsets.append(Int32(blob.count))
            blob.append(contentsOf: entry.text.lowercased().utf8)
            blob.append(0x0A)
        }
        offsets.append(Int32(blob.count))

        let vocabulary = postingsByWord.keys.sorted()
        self.vocabulary = vocabulary
        self.postings = vocabulary.map { postingsByWord[$0]! }
        self.indexByText = indexByText
        self.categoryMembers = categoryMembers
        self.customIndices = customIndices
        self.textBlob = blob
        self.textOffsets = offsets
    }

    // MARK: Lookup

    public func index(of text: String) -> Int? {
        indexByText[text].map(Int.init)
    }

    public func members(ofCategory id: String) -> [Int] {
        (categoryMembers[id] ?? []).map(Int.init)
    }

    /// Splits a tag into lowercase search words, dropping apostrophes ("can't" → "cant").
    static func words(in tag: String) -> [String] {
        var words = [String]()
        var current = String.UnicodeScalarView()
        for scalar in tag.lowercased().unicodeScalars {
            if scalar == "'" || scalar == "\u{2019}" { continue }
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                current.append(scalar)
            } else if !current.isEmpty {
                words.append(String(current))
                current.removeAll()
            }
        }
        if !current.isEmpty { words.append(String(current)) }
        return words
    }
}

// MARK: - TSV parsing

private struct Builder {
    var entries: [Kaomoji] = []
    var indexByText: [String: Int] = [:]

    mutating func addTSV(_ data: Data, custom: Bool) {
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var lineStart = 0
            for i in 0...bytes.count where i == bytes.count || bytes[i] == 0x0A {
                var end = i
                if end > lineStart, bytes[end - 1] == 0x0D { end -= 1 }
                if end > lineStart {
                    addLine(UnsafeBufferPointer(rebasing: bytes[lineStart..<end]), custom: custom)
                }
                lineStart = i + 1
            }
        }
    }

    private mutating func addLine(_ line: UnsafeBufferPointer<UInt8>, custom: Bool) {
        // "# " starts a comment in user files (a kaomoji can start with a bare "#").
        if custom, line.count >= 2, line[0] == 0x23, line[1] == 0x20 { return }

        let fields = String(decoding: line, as: UTF8.self)
            .split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)

        let text = fields[0].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let tags = fields.count > 1 ? Self.list(fields[1]) : []
        let categories = fields.count > 2 ? Self.list(fields[2]) : []
        let popularity = fields.count > 3 ? Int(fields[3].trimmingCharacters(in: .whitespaces)) ?? 0 : 0
        add(Kaomoji(text: text, tags: tags, categories: categories,
                    popularity: custom ? max(popularity, 25) : popularity, isCustom: custom))
    }

    private static func list(_ field: Substring) -> [String] {
        field.split(separator: ",").compactMap {
            let item = $0.trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
    }

    private mutating func add(_ entry: Kaomoji) {
        guard let i = indexByText[entry.text] else {
            indexByText[entry.text] = entries.count
            entries.append(entry)
            return
        }
        let old = entries[i]
        var tags = old.tags
        for tag in entry.tags where !tags.contains(tag) { tags.append(tag) }
        var categories = old.categories
        for c in entry.categories where !categories.contains(c) { categories.append(c) }
        entries[i] = Kaomoji(
            text: old.text, tags: tags, categories: categories,
            popularity: max(old.popularity, entry.popularity), isCustom: old.isCustom || entry.isCustom
        )
    }
}
