import Carbon.HIToolbox
import Combine
import KaomojiKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeView: () -> SettingsView

    init(makeView: @escaping () -> SettingsView) {
        self.makeView = makeView
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Splat That Moji Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: makeView())
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: UserLibrary
    @ObservedObject var store: KaomojiStore
    let openPicker: () -> Void

    var body: some View {
        TabView {
            GeneralSettings(settings: settings, openPicker: openPicker)
                .tabItem { Label("General", systemImage: "gearshape") }
            LibrarySettings(settings: settings, library: library, store: store)
                .tabItem { Label("Library", systemImage: "books.vertical") }
        }
        .frame(width: 560, height: 560)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings
    let openPicker: () -> Void
    @State private var isTrusted = Inserter.isTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent("Open the picker with") {
                    HotKeyRecorder(combo: $settings.hotKey, isRecording: $settings.isRecordingHotKey)
                }
                Button("Open Picker Now", action: openPicker)
            } header: {
                Text("Shortcut")
            }

            Section {
                Picker("Insert by", selection: $settings.insertMode) {
                    ForEach(InsertMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.insertMode.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if settings.insertMode == .paste {
                    Toggle("Restore my clipboard after pasting", isOn: $settings.restoreClipboard)
                }
                Toggle("Escape for Markdown (Discord, GitHub, Reddit)", isOn: $settings.escapeMarkdown)
                    .help("Adds backslashes so ¯\\_(ツ)_/¯ keeps its arm. ⌥↩ in the picker does this for one insert.")
                if settings.insertMode.needsAccessibility {
                    accessibilityRow
                }
            } header: {
                Text("Inserting")
            }

            Section {
                Stepper("Columns: \(settings.columns)", value: $settings.columns, in: 2...8)
                LabeledContent("Kaomoji size") {
                    Slider(value: $settings.fontSize, in: 13...30, step: 1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("A").font(.system(size: 11))
                    } maximumValueLabel: {
                        Text("A").font(.system(size: 17))
                    }
                    .frame(width: 220)
                }
                Toggle("Show in menu bar", isOn: $settings.showMenuBarIcon)
                    .help("If hidden, open Splat That Moji again from Finder to get to Settings.")
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Appearance & System")
            }
        }
        .formStyle(.grouped)
        .onReceive(poll) { _ in isTrusted = Inserter.isTrusted }
    }

    @ViewBuilder
    private var accessibilityRow: some View {
        if isTrusted {
            Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            HStack {
                Label("Needs Accessibility access to paste or type for you", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Grant Access…") {
                    Inserter.requestAccess()
                    Inserter.openAccessibilitySettings()
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct LibrarySettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: UserLibrary
    @ObservedObject var store: KaomojiStore
    @State private var confirmClearFavorites = false

    var body: some View {
        Form {
            Section {
                if let db = store.database {
                    LabeledContent("Kaomoji", value: db.entries.count.formatted())
                    LabeledContent("Browse categories", value: db.categories.count.formatted())
                    ForEach(db.sources, id: \.name) { source in
                        LabeledContent {
                            Text("+\(source.unique.formatted()) · \(source.license)")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } label: {
                            if let url = URL(string: source.url), !source.url.isEmpty {
                                Link(source.name, destination: url)
                            } else {
                                Text(source.name)
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            } header: {
                Text("Database")
            } footer: {
                HStack {
                    Text("Inspired by [Splatmoji](https://github.com/cspeterson/splatmoji) by Christopher Peterson.")
                    Spacer()
                    Link("Credits & Licenses", destination: URL(string: "https://github.com/andrewmetzner/splat-that-moji/blob/main/CREDITS.md")!)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Text("Every .tsv file in the custom folder is merged in: one kaomoji per line, a tab, then comma-separated keywords. That's Splatmoji's format, so its data files work as-is.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Custom Folder") { store.openCustomFolder() }
                    Button("Reload") { store.reload() }
                    Spacer()
                    if let count = store.database?.customIndices.count, count > 0 {
                        Text("\(count) custom").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Your Own Kaomoji")
            }

            Section {
                Stepper("Remember \(settings.historyLength) recent kaomoji", value: $settings.historyLength, in: 5...200, step: 5)
                HStack {
                    Button("Clear Recents") { library.clearRecents() }
                        .disabled(library.recents.isEmpty)
                    Button("Clear Favorites…") { confirmClearFavorites = true }
                        .disabled(library.favorites.isEmpty)
                    Spacer()
                    Text("\(library.favorites.count) favorites").foregroundStyle(.secondary)
                }
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Remove all \(library.favorites.count) favorites?", isPresented: $confirmClearFavorites) {
            Button("Clear Favorites", role: .destructive) { library.clearFavorites() }
        }
    }
}

/// Click, then press the new shortcut. Esc cancels.
struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo
    @Binding var isRecording: Bool
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(isRecording ? "Press shortcut…" : combo.displayString) {
                isRecording ? stop() : start()
            }
            .frame(minWidth: 110)
            if combo != .default, !isRecording {
                Button("Reset") { combo = .default }
                    .buttonStyle(.link)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            MainActor.assumeIsolated {
                if Int(keyCode) == kVK_Escape {
                    stop()
                    return
                }
                let isFunctionKey = KeyboardLayout.functionKeys.contains(Int(keyCode))
                guard isFunctionKey || !flags.subtracting(.shift).isEmpty else {
                    NSSound.beep()  // a shortcut needs ⌘, ⌥ or ⌃ (or an F-key)
                    return
                }
                combo = KeyCombo(keyCode: UInt32(keyCode), modifiers: flags.rawValue)
                stop()
            }
            return nil  // swallow every key while recording
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
