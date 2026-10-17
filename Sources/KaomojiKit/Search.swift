import Foundation

/// One whitespace-separated piece of a query.
enum QueryToken: Equatable {
    /// Letters/digits only: matched against tag words (by prefix), synonyms, and fuzzily.
    case word(String)
    /// Anything with symbols in it ("^_^", "ω", "ツ", "(╯"): matched inside the kaomoji itself.
    case symbols(String)

    static func parse(_ query: String) -> [QueryToken] {
        var tokens = [QueryToken]()
        for piece in query.lowercased().split(whereSeparator: \.isWhitespace) {
            let piece = String(piece)
            let unquoted = piece.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
            let parts = unquoted.split(separator: "-").map(String.init)
            if !parts.isEmpty, parts.allSatisfy(isWordLike) {
                tokens += parts.map(QueryToken.word)  // "table-flip", "don't"
                continue
            }
            let trimmed = unquoted.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?\""))
            if !trimmed.isEmpty, isWordLike(trimmed), trimmed.count >= unquoted.count - 1 {
                tokens.append(.word(trimmed))  // "happy!"
            } else {
                tokens.append(.symbols(piece))
            }
        }
        return tokens
    }

    static func isWordLike(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { $0.properties.isAlphabetic || $0.properties.numericType != nil }
    }
}

extension KaomojiDatabase {
    /// Returns entry indices matching every token of `query`, best first.
    ///
    /// - Parameters:
    ///   - within: restrict results to these entries (e.g. a category); `nil` searches all.
    ///   - boosts: extra score per entry index, used for favorites and frequently used kaomoji.
    public func search(_ query: String, within: [Int]? = nil, boosts: [Int: Int] = [:]) -> [Int] {
        let tokens = Array(QueryToken.parse(query).prefix(16))
        guard !tokens.isEmpty else { return within ?? Array(entries.indices) }

        let n = entries.count
        var total = [Int32](repeating: 0, count: n)
        var matchedTokens = [UInt8](repeating: 0, count: n)
        var tokenScore = [UInt8](repeating: 0, count: n)
        var touched = [Int32]()

        for (t, token) in tokens.enumerated() {
            touched.removeAll(keepingCapacity: true)
            score(token, into: &tokenScore, touched: &touched)
            for i32 in touched {
                let i = Int(i32)
                if matchedTokens[i] == t {
                    matchedTokens[i] = UInt8(t + 1)
                    total[i] += Int32(tokenScore[i])
                }
                tokenScore[i] = 0
            }
        }

        let required = UInt8(tokens.count)
        var results = [(index: Int, score: Int)]()
        func consider(_ i: Int) {
            guard matchedTokens[i] == required else { return }
            results.append((i, Int(total[i]) * 60 + entries[i].popularity * 12 + (boosts[i] ?? 0)))
        }
        if let within {
            for i in within where i < n { consider(i) }
        } else {
            for i in 0..<n { consider(i) }
        }
        results.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return results.map(\.index)
    }

    // MARK: Scoring a single token

    private func score(_ token: QueryToken, into scores: inout [UInt8], touched: inout [Int32]) {
        func give(_ entry: Int32, _ value: UInt8) {
            let i = Int(entry)
            if scores[i] == 0 { touched.append(entry) }
            if value > scores[i] { scores[i] = value }
        }

        switch token {
        case .word(let word):
            // Tag words starting with the token; whole-word and primary-tag matches score higher.
            let length = word.utf8.count
            for v in prefixRange(of: word) {
                let candidate = vocabulary[v]
                let candidateLength = candidate.utf8.count
                let exact = candidateLength == length
                let mostOfWord: UInt8 = length * 2 >= candidateLength ? 1 : 0
                for posting in postings[v] {
                    let primary = posting & 1 == 1
                    let value: UInt8 = exact ? (primary ? 10 : 8) : (primary ? 7 : 5) + mostOfWord
                    give(posting >> 1, value)
                }
            }
            // "glad" also finds everything tagged with its canonical form "happy".
            for canonical in synonyms[word] ?? [] {
                guard let v = exactIndex(of: canonical) else { continue }
                for posting in postings[v] { give(posting >> 1, posting & 1 == 1 ? 8 : 6) }
            }
            if !word.unicodeScalars.allSatisfy(\.isASCII) {
                // "ω", "ツ", "Д": letters, but they only ever appear inside the kaomoji.
                substringMatches(word) { give($0, 9) }
            } else if length >= 3 {
                // "uwu", "owo", "orz" are often spelled out inside the kaomoji itself.
                substringMatches(word) { give($0, 4) }
            }
            // Nothing at all? Allow a typo or two.
            if touched.isEmpty, length >= 4 {
                let maxDistance = length >= 8 ? 2 : 1
                let target = Array(word.utf8)
                for (v, candidate) in vocabulary.enumerated() {
                    let bytes = Array(candidate.utf8)
                    guard abs(bytes.count - target.count) <= maxDistance,
                          editDistance(bytes, target, limit: maxDistance) <= maxDistance else { continue }
                    for posting in postings[v] { give(posting >> 1, 3) }
                }
            }

        case .symbols(let symbols):
            substringMatches(symbols) { give($0, 9) }
        }
    }

    /// Range of `vocabulary` whose words start with `prefix`.
    func prefixRange(of prefix: String) -> Range<Int> {
        var low = 0, high = vocabulary.count
        while low < high {
            let mid = (low + high) / 2
            if vocabulary[mid] < prefix { low = mid + 1 } else { high = mid }
        }
        var end = low
        while end < vocabulary.count, vocabulary[end].hasPrefix(prefix) { end += 1 }
        return low..<end
    }

    func exactIndex(of word: String) -> Int? {
        let range = prefixRange(of: word)
        return range.first.flatMap { vocabulary[$0] == word ? $0 : nil }
    }

    /// Calls `found` once for each entry whose (lowercased) text contains `needle`.
    func substringMatches(_ needle: String, _ found: (Int32) -> Void) {
        let needleBytes = Array(needle.lowercased().utf8)
        guard !needleBytes.isEmpty else { return }
        textBlob.withUnsafeBufferPointer { hay in
            needleBytes.withUnsafeBufferPointer { pin in
                guard let hayBase = hay.baseAddress, let pinBase = pin.baseAddress else { return }
                var position = 0
                while position < hay.count,
                      let hit = memmem(hayBase + position, hay.count - position, pinBase, pin.count) {
                    let offset = hayBase.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                    let entry = entryIndex(atBlobOffset: offset)
                    found(Int32(entry))
                    position = Int(textOffsets[entry + 1])  // skip to the next kaomoji
                }
            }
        }
    }

    private func entryIndex(atBlobOffset offset: Int) -> Int {
        var low = 0, high = textOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if Int(textOffsets[mid]) <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

/// Optimal-string-alignment distance (Levenshtein plus adjacent transpositions), giving up
/// early once every path exceeds `limit`.
func editDistance(_ a: [UInt8], _ b: [UInt8], limit: Int) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var previous2 = [Int](repeating: 0, count: b.count + 1)
    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        current[0] = i
        var rowMin = current[0]
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                value = min(value, previous2[j - 2] + 1)
            }
            current[j] = value
            rowMin = min(rowMin, value)
        }
        if rowMin > limit { return rowMin }
        (previous2, previous, current) = (previous, current, previous2)
    }
    return previous[b.count]
}
