import AppKit
import KaomojiKit
import SwiftUI

let arguments = CommandLine.arguments

// `SplatThatMoji --search table flip` prints matches, for terminal use and scripting.
if let i = arguments.firstIndex(of: "--search") {
    let query = arguments[(i + 1)...].joined(separator: " ")
    do {
        let start = Date()
        let db = try KaomojiStore.loadDatabase()
        let loaded = Date()
        let results = db.search(query)
        let ms = { (a: Date, b: Date) in Int(b.timeIntervalSince(a) * 1000) }
        print("\(results.count) matches for “\(query)” (load \(ms(start, loaded)) ms, search \(ms(loaded, Date())) ms)")
        for i in results.prefix(30) {
            let entry = db.entries[i]
            print("\(entry.text)\t\(entry.tags.prefix(5).joined(separator: ", "))")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

// `SplatThatMoji --snapshot out.png [query]` renders the picker offscreen (development aid).
if let i = arguments.firstIndex(of: "--snapshot"), i + 1 < arguments.count {
    let settings = AppSettings()
    let library = UserLibrary()
    let store = KaomojiStore()
    let model = PickerModel(store: store, library: library, settings: settings)
    store.reload()
    let deadline = Date().addingTimeInterval(10)
    while store.database == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    if let scope = ProcessInfo.processInfo.environment["SNAPSHOT_SCOPE"],
       let match = model.scopes.first(where: { $0.id == scope }) {
        model.scope = match
    }
    model.query = arguments.dropFirst(i + 2).joined(separator: " ")
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    model.move(by: 1)

    let noop = PickerActions(insert: { _, _, _ in }, toggleFavorite: { _ in }, openSettings: {}, openAccessibilitySettings: {})
    let view = PickerView(model: model, settings: settings, library: library, store: store, actions: noop)
        .frame(width: 760, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
    let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: ProcessInfo.processInfo.environment["SNAPSHOT_DARK"] == nil ? .aqua : .darkAqua)
    window.contentView = hosting
    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
    hosting.layoutSubtreeIfNeeded()
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arguments[i + 1]))
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
