import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let library = UserLibrary()
    let store = KaomojiStore()
    private var picker: PickerController!
    private var statusBar: StatusBarController!
    private var settingsWindow: SettingsWindowController!
    private var hotKey: HotKey?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.reload()
        picker = PickerController(store: store, library: library, settings: settings)
        settingsWindow = SettingsWindowController { [unowned self] in
            SettingsView(settings: settings, library: library, store: store, openPicker: { [unowned self] in picker.show() })
        }
        picker.openSettings = { [unowned self] in settingsWindow.show() }
        statusBar = StatusBarController(settings: settings, library: library, picker: picker) { [unowned self] in
            settingsWindow.show()
        }

        settings.$showMenuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] visible in statusBar.setVisible(visible) }
            .store(in: &subscriptions)
        settings.$hotKey.combineLatest(settings.$isRecordingHotKey)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] combo, recording in registerHotKey(recording ? nil : combo) }
            .store(in: &subscriptions)

        if settings.isFirstLaunch {
            settingsWindow.show()
        }
    }

    /// Opening the app again (e.g. from Finder while the menu bar icon is hidden) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show()
        return false
    }

    private func registerHotKey(_ combo: KeyCombo?) {
        hotKey?.unregister()
        hotKey = nil
        guard let combo else { return }
        hotKey = HotKey(combo) { [unowned self] in picker.toggle() }
        if hotKey == nil {
            let alert = NSAlert()
            alert.messageText = "\(combo.displayString) is already in use"
            alert.informativeText = "Another app has claimed that shortcut. Pick a different one in Splat That Moji's settings."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn { settingsWindow.show() }
        }
    }
}
