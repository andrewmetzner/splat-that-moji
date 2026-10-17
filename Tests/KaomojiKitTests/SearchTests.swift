import Foundation
import Testing
@testable import KaomojiKit

private let resources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources")

private let bundled: KaomojiDatabase = {
    try! KaomojiDatabase.load(
        databaseURL: resources.appendingPathComponent("kaomoji.tsv"),
        metaURL: resources.appendingPathComponent("kaomoji-meta.json")
    )
}()

private func top(_ query: String, _ n: Int = 10, in db: KaomojiDatabase = bundled) -> [String] {
    db.search(query).prefix(n).map { db.entries[$0].text }
}

@Suite struct BundledDatabase {
    @Test func loadsEverything() {
        #expect(bundled.entries.count > 90_000)
        #expect(bundled.categories.count > 30)
        #expect(bundled.sources.count == 5)
        #expect(Set(bundled.entries.map(\.text)).count == bundled.entries.count)
    }

    @Test func classicsRankFirst() {
        #expect(top("shrug", 5).contains("¯\\_(ツ)_/¯"))
        #expect(top("lenny", 5).contains("( ͡° ͜ʖ ͡°)"))
        #expect(top("table flip", 5).allSatisfy { $0.contains("┻") || $0.contains("┬") })
        #expect(top("disapproval", 5).contains("ಠ_ಠ"))
    }

    @Test func everyTokenMustMatch() {
        for i in bundled.search("cat happy").prefix(50) {
            let tags = bundled.entries[i].tags.joined(separator: " ")
            #expect(tags.contains("cat") || tags.contains("kitty") || tags.contains("nya"))
        }
    }

    @Test func symbolsSearchInsideTheKaomoji() {
        let results = bundled.search("ツ")
        #expect(results.count > 50)
        // Compare code points: Swift's Character-level contains() misses "ツ" + combining mark.
        #expect(results.allSatisfy { bundled.entries[$0].text.range(of: "ツ", options: .literal) != nil })
        #expect(top("^_^", 20).allSatisfy { $0.range(of: "^_^", options: .literal) != nil })
        #expect(bundled.search("ω").count > 1_000)
    }

    @Test func synonymsAndTypos() {
        #expect(!bundled.search("glad").isEmpty)
        #expect(bundled.search("kitten").count > 1_000)  // kitten → cat
        #expect(!bundled.search("hapyy").isEmpty)        // typo
        #expect(bundled.search("qqqqzzzz").isEmpty)
    }

    @Test func prefixesWork() {
        #expect(bundled.search("emba").count > 100)  // embarrassed
        #expect(bundled.search("table-flip") == bundled.search("table flip"))
    }

    @Test func scopeAndBoosts() {
        let cats = bundled.members(ofCategory: "cat")
        #expect(cats.count > 1_000)
        let scoped = bundled.search("happy", within: cats)
        #expect(Set(scoped).isSubset(of: Set(cats)))

        let plain = bundled.search("cry")
        let pick = plain[200]
        #expect(bundled.search("cry", boosts: [pick: 100_000]).first == pick)
    }
}

@Suite struct CustomFiles {
    @Test func customEntriesMergeAndLead() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let custom = dir.appendingPathComponent("mine.tsv")
        try """
        # my faces
        (ﾉ´ヮ`)ﾉ*: ･ﾟ\tsparkle toss, glitter bomb
        ¯\\_(ツ)_/¯\tmeh custom
        #hashface\tstarts with a hash
        """.write(to: custom, atomically: true, encoding: .utf8)

        let db = try KaomojiDatabase.load(
            databaseURL: resources.appendingPathComponent("kaomoji.tsv"), customURLs: [custom]
        )
        let newOnes = bundled.index(of: "(ﾉ´ヮ`)ﾉ*: ･ﾟ") == nil ? 2 : 1
        #expect(db.entries.count == bundled.entries.count + newOnes)
        #expect(db.customIndices.count == 3)
        #expect(db.entries[0].text == "(ﾉ´ヮ`)ﾉ*: ･ﾟ")
        #expect(top("glitter bomb", 1, in: db) == ["(ﾉ´ヮ`)ﾉ*: ･ﾟ"])

        let shrug = try #require(db.index(of: "¯\\_(ツ)_/¯"))
        #expect(db.entries[shrug].tags.first == "meh custom")
        #expect(db.entries[shrug].tags.contains("shrug"))
        #expect(db.index(of: "#hashface") != nil)
    }
}

@Suite struct Tokenizing {
    @Test func splitsWordsAndSymbols() {
        #expect(QueryToken.parse("Happy  CAT") == [.word("happy"), .word("cat")])
        #expect(QueryToken.parse("don't") == [.word("dont")])
        #expect(QueryToken.parse("happy!") == [.word("happy")])
        #expect(QueryToken.parse("T_T") == [.symbols("t_t")])
        #expect(QueryToken.parse("(╯°□°)") == [.symbols("(╯°□°)")])
    }

    @Test func wordsInTags() {
        #expect(KaomojiDatabase.words(in: "Can't wait, table-flip") == ["cant", "wait", "table", "flip"])
    }

    @Test func editDistanceCountsTranspositions() {
        #expect(editDistance(Array("happy".utf8), Array("hapyp".utf8), limit: 2) == 1)
        #expect(editDistance(Array("kitten".utf8), Array("sitting".utf8), limit: 5) == 3)
    }
}
