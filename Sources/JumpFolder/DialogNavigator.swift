import AppKit
import Carbon.HIToolbox
import JumpFolderKit

/// Takes the dialog in front to a folder the way a person would: ⌘⇧G opens the dialog's
/// "Go to" sheet, the path is typed into it, and Return goes there. Setting the field's text
/// through Accessibility alone shows the path but leaves the dialog's own copy unchanged,
/// so the path is typed as key events.
@MainActor
enum DialogNavigator {
    /// Marks JumpFolder's own key events, so the click tap lets them through untouched.
    static let eventTag: Int64 = 0x4A46_4C44

    private static var busy = false

    /// Goes to `path` in the dialog in front. Calls back with whether it got there.
    static func go(to path: String, done: (@MainActor (Bool) -> Void)? = nil) {
        let path = FolderPath.normalized(path)
        var isFolder: ObjCBool = false
        guard !busy, let dialog = DialogWatcher.shared.dialog, !path.isEmpty,
              FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else {
            if !busy { NSSound.beep() }
            done?(false)
            return
        }
        busy = true
        Diagnostics.note("go to \(path) in \(dialog.appName)")
        Task { @MainActor in
            let ok = await run(path, in: dialog)
            busy = false
            if ok { DialogWatcher.shared.didNavigate(to: path) } else { NSSound.beep() }
            Diagnostics.note(ok ? "went to \(path)" : "couldn't go to \(path)")
            done?(ok)
        }
    }

    private static func run(_ path: String, in dialog: FileDialog) async -> Bool {
        guard isFront(dialog) else { return false }
        // A "Go to" sheet left open from before is reused.
        var field = goToField(in: dialog)
        if field == nil {
            postKey(kVK_ANSI_G, flags: [.maskCommand, .maskShift])
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(50))
                field = goToField(in: dialog)
                if field != nil { break }
            }
        }
        guard let field, isFront(dialog) else { return false }
        AX.set(field, kAXFocusedAttribute, kCFBooleanTrue)
        // Replace whatever the field holds, then type the path.
        postKey(kVK_ANSI_A, flags: .maskCommand)
        try? await Task.sleep(for: .milliseconds(40))
        type(path)
        // Let the sheet catch up with the typing (it checks the path as you type).
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(40))
            if (AX.string(field, kAXValueAttribute) ?? "") == path { break }
        }
        guard isFront(dialog) else { return false }
        postKey(kVK_Return, flags: [])
        // The sheet closes once the dialog is there.
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(50))
            if goToField(in: dialog) == nil { return true }
        }
        // Still open: the path wasn't accepted. Close the sheet rather than leave it up.
        postKey(kVK_Escape, flags: [])
        return false
    }

    private static func isFront(_ dialog: FileDialog) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == dialog.pid
    }

    private static func goToField(in dialog: FileDialog) -> AXUIElement? {
        // The sheet is a child of the dialog (or, for a dialog that is itself a sheet, may be
        // listed with the app's windows); its field is a few levels down.
        let windows = AX.value(AX.app(dialog.pid), kAXWindowsAttribute) as? [AXUIElement] ?? []
        for candidate in AX.children(dialog.element) + windows where AX.identifier(candidate) == "GoToWindow" {
            return AX.first(below: candidate, identifier: "PathTextField", budget: 60)
        }
        return nil
    }

    private static let source: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.userData = eventTag
        return source
    }()

    private static func postKey(_ code: Int, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: eventTag)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Types text as Unicode key events, a few characters per event.
    private static func type(_ text: String) {
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(index + 16, units.count)])
            index += chunk.count
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.setIntegerValueField(.eventSourceUserData, value: eventTag)
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
