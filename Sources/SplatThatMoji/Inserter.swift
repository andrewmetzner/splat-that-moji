import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Gets text into the frontmost app: by clipboard + ⌘V, by synthesized typing, or by copying.
@MainActor
enum Inserter {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow accessibility" prompt (macOS only shows it once per app).
    static func requestAccess() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Puts `text` on the clipboard, sends ⌘V, then (optionally) restores what was there before.
    static func paste(_ text: String, restoreClipboard: Bool) async {
        let pasteboard = NSPasteboard.general
        let saved = restoreClipboard ? snapshot(pasteboard) : nil
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if restoreClipboard {
            // Tells clipboard managers this is a temporary entry (nspasteboard.org convention).
            pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        }
        let ourChange = pasteboard.changeCount
        postKey(KeyboardLayout.keyCode(for: "v") ?? CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

        guard let saved else { return }
        // Give the target app time to read the clipboard before swapping it back.
        try? await Task.sleep(for: .milliseconds(600))
        guard pasteboard.changeCount == ourChange else { return }  // something else copied meanwhile
        pasteboard.clearContents()
        if !saved.isEmpty { pasteboard.writeObjects(saved) }
    }

    /// Types `text` one character at a time as synthesized Unicode key events.
    static func type(_ text: String) async {
        let source = CGEventSource(stateID: .combinedSessionState)
        for character in text {
            let units = Array(String(character).utf16)
            for keyDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(for: .milliseconds(4))
        }
    }

    /// Escapes the characters that Markdown (Discord, GitHub, Reddit...) would otherwise eat,
    /// so `¯\_(ツ)_/¯` doesn't lose its arm.
    static func markdownEscaped(_ text: String) -> String {
        var out = ""
        for (i, ch) in text.enumerated() {
            if "\\`*_~|".contains(ch) || (i == 0 && ch == ">") { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }
}
