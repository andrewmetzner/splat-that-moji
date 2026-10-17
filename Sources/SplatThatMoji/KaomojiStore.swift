import AppKit
import KaomojiKit

/// Loads the bundled database plus the user's own TSV files, off the main thread.
@MainActor
final class KaomojiStore: ObservableObject {
    @Published private(set) var database: KaomojiDatabase?
    @Published private(set) var loadError: String?

    /// `~/Library/Application Support/Splat That Moji/`: every `.tsv` in here is merged in.
    nonisolated static var customDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Splat That Moji", isDirectory: true)
    }

    func reload() {
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try Self.loadDatabase() } }.value
            switch result {
            case .success(let db):
                database = db
                loadError = nil
            case .failure(let error):
                loadError = error.localizedDescription
            }
        }
    }

    nonisolated static func loadDatabase() throws -> KaomojiDatabase {
        guard let tsv = resourceURL("kaomoji", "tsv") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "kaomoji.tsv is missing from the app bundle."])
        }
        let custom = (try? FileManager.default.contentsOfDirectory(at: customDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "tsv" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        return try KaomojiDatabase.load(databaseURL: tsv, metaURL: resourceURL("kaomoji-meta", "json"), customURLs: custom)
    }

    /// Finds a resource in the app bundle, or in the repo's `Resources/` when run via `swift run`.
    nonisolated static func resourceURL(_ name: String, _ ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    /// Opens the custom kaomoji folder in Finder, creating it with an example file first.
    func openCustomFolder() {
        let dir = Self.customDirectory
        let example = dir.appendingPathComponent("my-kaomoji.tsv")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: example.path) {
            let text = """
            # Your own kaomoji. One per line: <kaomoji> TAB <keyword, keyword, ...>
            # Lines starting with "# " are comments. Any .tsv file in this folder is loaded,
            # so Splatmoji data files work too. Use "Reload" in Settings after editing.
            (ﾉ◕ヮ◕)ﾉ*:･ﾟ✧\tsparkles, magic, my favorite

            """
            try? text.write(to: example, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([example])
    }
}
