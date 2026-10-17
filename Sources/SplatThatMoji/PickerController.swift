import AppKit
import Carbon.HIToolbox
import KaomojiKit
import SwiftUI

/// A Spotlight-style panel that takes keyboard focus without activating the app, so the app
/// you were typing in stays frontmost and receives the kaomoji.
final class PickerPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        animationBehavior = .utilityWindow
        minSize = NSSize(width: 520, height: 340)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PickerController: NSObject, NSWindowDelegate {
    let model: PickerModel
    private let panel = PickerPanel()
    private let settings: AppSettings
    private let library: UserLibrary
    /// The app that was frontmost when the picker opened: where the kaomoji goes.
    private var targetApp: NSRunningApplication?
    private var keyMonitor: Any?
    var openSettings: () -> Void = {}

    init(store: KaomojiStore, library: UserLibrary, settings: AppSettings) {
        self.settings = settings
        self.library = library
        model = PickerModel(store: store, library: library, settings: settings)
        super.init()

        let actions = PickerActions(
            insert: { [unowned self] kaomoji, mode, escape in insert(kaomoji, mode: mode, escape: escape) },
            toggleFavorite: { [unowned self] kaomoji in library.toggleFavorite(kaomoji.text); model.requestFocus() },
            openSettings: { [unowned self] in close(); openSettings() },
            openAccessibilitySettings: { [unowned self] in close(); Inserter.openAccessibilitySettings() }
        )
        let root = PickerView(model: model, settings: settings, library: library, store: store, actions: actions)
            .ignoresSafeArea()  // the (hidden) title bar would otherwise leave a gap above the search field
        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        panel.delegate = self
        if let size = UserDefaults.standard.string(forKey: "pickerSize").map(NSSizeFromString), size.width > 0 {
            panel.setContentSize(size)
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            targetApp = front
        }
        model.reset()
        positionOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        removeKeyMonitor()
    }

    /// Inserts into whatever app is frontmost right now (used by the menu bar's Recent/Favorites).
    func insertIntoFrontmostApp(_ text: String) {
        targetApp = NSWorkspace.shared.frontmostApplication
        let kaomoji = model.store.database?.index(of: text).map { model.store.database!.entries[$0] } ?? Kaomoji(text: text)
        insert(kaomoji)
    }

    func insert(_ kaomoji: Kaomoji, mode: InsertMode? = nil, escape: Bool? = nil) {
        let mode = mode ?? settings.insertMode
        let text = (escape ?? settings.escapeMarkdown) ? Inserter.markdownEscaped(kaomoji.text) : kaomoji.text
        library.recordUse(kaomoji.text, historyLength: settings.historyLength)

        if mode.needsAccessibility && !Inserter.isTrusted {
            // Still useful without permission: it's on the clipboard, ready for ⌘V.
            Inserter.copy(text)
            model.notice = PickerNotice(
                message: "Copied! To paste automatically, allow Splat That Moji in Privacy & Security → Accessibility.",
                offersAccessibilitySettings: true
            )
            Inserter.requestAccess()
            return
        }

        let target = targetApp
        close()
        guard mode != .copy else {
            Inserter.copy(text)
            return
        }
        Task {
            // Make sure keystrokes land in the original app, not in one of our windows.
            if NSApp.isActive, let target {
                target.activate()
                try? await Task.sleep(for: .milliseconds(180))
            } else {
                try? await Task.sleep(for: .milliseconds(60))
            }
            switch mode {
            case .paste: await Inserter.paste(text, restoreClipboard: settings.restoreClipboard)
            case .type: await Inserter.type(text)
            case .copy: break
            }
        }
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, event.window === self.panel else { return false }
                return self.handleKey(event)
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the key was handled here instead of by the search field.
    private func handleKey(_ event: NSEvent) -> Bool {
        // Let input methods (Japanese, Chinese...) finish composing first.
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }

        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let columns = model.columns
        switch Int(event.keyCode) {
        case kVK_DownArrow where flags.isEmpty: model.move(by: columns)
        case kVK_UpArrow where flags.isEmpty: model.move(by: -columns)
        case kVK_LeftArrow where flags.isEmpty: model.move(by: -1)
        case kVK_RightArrow where flags.isEmpty: model.move(by: 1)
        case kVK_PageDown: model.move(by: columns * 5)
        case kVK_PageUp: model.move(by: -columns * 5)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard let kaomoji = model.selected else { return true }
            if flags.contains(.command) {
                insert(kaomoji, mode: .copy)
            } else if flags.contains(.option) {
                insert(kaomoji, escape: true)
            } else {
                insert(kaomoji)
            }
        case kVK_Escape:
            if model.query.isEmpty { close() } else { model.query = "" }
        case kVK_Tab:
            model.cycleScope(forward: !flags.contains(.shift))
        default:
            guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
            switch key {
            case "d":
                if let kaomoji = model.selected { library.toggleFavorite(kaomoji.text) }
            case ",":
                close()
                openSettings()
            case "w":
                close()
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                let i = Int(key)! - 1
                if model.results.indices.contains(i) { insert(model.results[i]) }
            default:
                return false
            }
        }
        return true
    }

    // MARK: Window

    func windowDidResignKey(_ notification: Notification) {
        close()  // clicked somewhere else
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let size = panel.contentView?.frame.size else { return }
        UserDefaults.standard.set(NSStringFromSize(size), forKey: "pickerSize")
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: max(visible.minY, visible.maxY - size.height - visible.height * 0.16)
        )
        panel.setFrameOrigin(origin)
    }
}
