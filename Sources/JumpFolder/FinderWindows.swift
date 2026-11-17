import AppKit
import JumpFolderKit

/// Finder's open windows and the folder each shows. Accessibility gives Finder windows'
/// frames but not their folders, so this asks Finder through Apple Events (macOS asks the
/// user once to let JumpFolder control Finder).
enum FinderWindows {
    struct Window {
        let path: String
        let name: String
        /// Global top-left coordinates, like Accessibility's.
        let bounds: CGRect
    }

    /// Fields split by ASCII 31, windows by ASCII 30, so names with tabs or line breaks survive.
    private static let source = """
    tell application "Finder"
        set out to ""
        set n to count of Finder windows
        repeat with i from 1 to n
            try
                set w to Finder window i
                if collapsed of w then error number -128
                set b to bounds of w
                set p to ""
                try
                    set p to POSIX path of (target of w as alias)
                end try
                set out to out & p & (character id 31) & (name of w) & (character id 31) & (item 1 of b) & "," & (item 2 of b) & "," & (item 3 of b) & "," & (item 4 of b) & (character id 30)
            end try
        end repeat
        return out
    end tell
    """

    /// Apple Events wait for a reply: keep them off the main thread, one at a time.
    private static let queue = DispatchQueue(label: "com.smanke.JumpFolder.finder", qos: .userInitiated)
    nonisolated(unsafe) private static var compiled: NSAppleScript?

    /// Whether Finder is running at all (asking it would launch it).
    static var finderRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").isEmpty
    }

    /// Finder's windows front to back, or an error message. Calls back on the main thread.
    @MainActor static func list(_ done: @escaping @MainActor ([Window], String?) -> Void) {
        guard finderRunning else { done([], nil); return }
        queue.async {
            let result = listNow()
            DispatchQueue.main.async { MainActor.assumeIsolated { done(result.0, result.1) } }
        }
    }

    /// Blocking; call on `queue` only.
    private static func listNow() -> ([Window], String?) {
        if compiled == nil {
            let script = NSAppleScript(source: source)
            var error: NSDictionary?
            script?.compileAndReturnError(&error)
            compiled = script
        }
        var error: NSDictionary?
        guard let output = compiled?.executeAndReturnError(&error).stringValue else {
            let number = error?[NSAppleScript.errorNumber] as? Int
            let message = number == -1743
                ? "JumpFolder isn't allowed to control Finder. Turn it on in Privacy & Security › Automation."
                : (error?[NSAppleScript.errorMessage] as? String ?? "Finder didn't answer.")
            Diagnostics.note("finder windows failed: \(number ?? 0) \(message)")
            return ([], message)
        }
        let windows = output.split(separator: "\u{1E}").compactMap { record -> Window? in
            let fields = record.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3 else { return nil }
            let numbers = fields[2].split(separator: ",").compactMap { Double($0) }
            guard numbers.count == 4 else { return nil }
            let bounds = CGRect(x: numbers[0], y: numbers[1], width: numbers[2] - numbers[0], height: numbers[3] - numbers[1])
            return Window(path: FolderPath.normalized(fields[0]), name: fields[1], bounds: bounds)
        }
        return (windows, nil)
    }

    /// Asks once, so the Automation question comes up when the user is looking (Welcome).
    static func requestAccess() {
        queue.async { _ = listNow() }
    }
}
