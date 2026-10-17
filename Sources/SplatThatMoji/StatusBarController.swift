import AppKit

/// The menu bar item: open the picker, quick access to recent and favorite kaomoji, settings.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let settings: AppSettings
    private let library: UserLibrary
    private let picker: PickerController
    private let showSettings: () -> Void

    init(settings: AppSettings, library: UserLibrary, picker: PickerController, showSettings: @escaping () -> Void) {
        self.settings = settings
        self.library = library
        self.picker = picker
        self.showSettings = showSettings
        super.init()
    }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = "(ツ)"
            item.button?.toolTip = "Splat That Moji"
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let open = ActionItem("Open Kaomoji Picker") { [picker] in picker.show() }
        open.keyEquivalent = settings.hotKey.menuKeyEquivalent
        open.keyEquivalentModifierMask = settings.hotKey.flags
        menu.addItem(open)
        menu.addItem(.separator())

        menu.addItem(submenu("Recent", texts: library.recents, empty: "Nothing yet"))
        menu.addItem(submenu("Favorites", texts: library.favorites, empty: "Press ⌘D in the picker"))

        let modes = NSMenu()
        for mode in InsertMode.allCases {
            let item = ActionItem(mode.title) { [settings] in settings.insertMode = mode }
            item.state = settings.insertMode == mode ? .on : .off
            modes.addItem(item)
        }
        let modeItem = NSMenuItem(title: "Insert By", action: nil, keyEquivalent: "")
        modeItem.submenu = modes
        menu.addItem(modeItem)

        menu.addItem(.separator())
        let settingsItem = ActionItem("Settings…", action: showSettings)
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        let quit = ActionItem("Quit Splat That Moji") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func submenu(_ title: String, texts: [String], empty: String) -> NSMenuItem {
        let menu = NSMenu()
        if texts.isEmpty {
            let placeholder = NSMenuItem(title: empty, action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        }
        for text in texts.prefix(20) {
            menu.addItem(ActionItem(text) { [picker] in picker.insertIntoFrontmostApp(text) })
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// An NSMenuItem that runs a closure.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}
