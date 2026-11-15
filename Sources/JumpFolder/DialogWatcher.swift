import AppKit
import ApplicationServices
import JumpFolderKit

/// An Open or Save dialog in another app. On macOS 27 the dialog runs in a separate panel
/// service, but Accessibility shows it as one of the app's own windows (or sheets) with the
/// identifier "open-panel" or "save-panel"; its contents come from the service's process.
struct FileDialog {
    enum Kind: String { case open, save }

    let pid: pid_t
    let bundleID: String?
    let appName: String
    let element: AXUIElement
    let kind: Kind

    func isSame(as other: FileDialog?) -> Bool {
        guard let other else { return false }
        return pid == other.pid && CFEqual(element, other.element)
    }
}

/// Accessibility elements may be used from any thread; Swift can't know that.
struct ElementBox: @unchecked Sendable {
    let element: AXUIElement
}

/// What the click tap (on its own thread) needs to know about the dialog in front.
final class DialogSnapshot: @unchecked Sendable {
    struct State {
        var pid: pid_t = 0
        var frame: CGRect = .null
        var clickThrough = false
    }

    private let lock = NSLock()
    private var state = State()

    var current: State { lock.withLock { state } }
    func set(_ new: State) { lock.withLock { state = new } }
}

/// Finds the Open or Save dialog in the frontmost app and follows it: where it is, which
/// folder it shows, and when it closes. Event driven (Accessibility notifications for the
/// frontmost app) with a light poll as a fallback, since notifications from the panel
/// service don't always arrive.
@MainActor
final class DialogWatcher {
    static let shared = DialogWatcher()

    nonisolated static let snapshot = DialogSnapshot()

    private(set) var dialog: FileDialog?
    private(set) var frame: CGRect?
    /// The folder the dialog shows, when it can be told (from its file list, or from the
    /// last folder JumpFolder took it to). Nil in an empty folder JumpFolder didn't choose.
    private(set) var currentFolder: String?
    /// The folder pop-up's text ("Documents"), always known.
    private(set) var folderTitle: String?

    /// Called on the main thread when a dialog appears, moves, changes folder or closes.
    var onChange: (() -> Void)?

    private var timer: Timer?
    private var ticks = 0
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var lastFocused: AXUIElement?
    private var wherePopup: AXUIElement?
    /// The folder JumpFolder last sent the dialog to, trusted while the pop-up shows its name.
    private var navigatedFolder: String?
    private let sampler = DispatchQueue(label: "com.smanke.JumpFolder.folder-sampler", qos: .userInitiated)
    private var sampling = false

    var statusLine: String {
        guard AX.isTrusted else { return "Waiting for access" }
        guard let dialog else { return "No Open or Save dialog in front" }
        let what = dialog.kind == .open ? "Open" : "Save"
        if let folder = folderTitle { return "\(what) dialog in \(dialog.appName): \(folder)" }
        return "\(what) dialog in \(dialog.appName)"
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.frontmostChanged() }
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        frontmostChanged()
    }

    /// After a setting changed: republish what the tap may do.
    func settingsChanged() {
        publish()
        onChange?()
    }

    // MARK: - Finding the dialog

    private func frontmostChanged() {
        lastFocused = nil
        observe(NSWorkspace.shared.frontmostApplication)
        rescan()
    }

    private func tick() {
        ticks += 1
        guard AX.isTrusted else { if dialog != nil { setDialog(nil) }; return }
        if let dialog {
            // Follow it closely while it's up; look it over a few times a second.
            guard let newFrame = AX.frame(dialog.element), NSWorkspace.shared.frontmostApplication?.processIdentifier == dialog.pid else {
                rescan()
                return
            }
            if newFrame != frame {
                frame = newFrame
                publish()
                onChange?()
            }
            if ticks % 6 == 0 { checkFolderTitle() }
            if ticks % 10 == 0 { rescan() }
            if ticks % 60 == 0 { sampleFolder() }
        } else if ticks % 10 == 0 {
            rescan()
        }
    }

    /// Looks for a dialog in the frontmost app: its focused window, or the sheet or window
    /// holding the focused element (a Save sheet on a document window).
    private func rescan() {
        guard AX.isTrusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !AppSettings.shared.isExcluded(app.bundleIdentifier) else {
            setDialog(nil)
            return
        }
        let element = AX.app(app.processIdentifier)
        let make = { (dialog: AXUIElement, kind: FileDialog.Kind) in
            FileDialog(pid: app.processIdentifier, bundleID: app.bundleIdentifier,
                       appName: app.localizedName ?? "the app", element: dialog, kind: kind)
        }
        if let window = AX.element(element, kAXFocusedWindowAttribute) {
            // The focused window itself, or what holds it: the dialog's own "Go to" sheet is
            // listed as a window and can have the focus.
            var candidate: AXUIElement? = window
            for _ in 0..<3 {
                guard let current = candidate else { break }
                if let kind = Self.kind(of: current) { return setDialog(make(current, kind)) }
                candidate = AX.element(current, kAXParentAttribute)
                if let next = candidate, AX.role(next) == kAXApplicationRole { break }
            }
            // A sheet on the focused window (a Save sheet on a document window).
            for child in AX.children(window) where AX.role(child) == kAXSheetRole {
                if let kind = Self.kind(of: child) { return setDialog(make(child, kind)) }
            }
        }
        // Last, any of the app's windows: a dialog that is up but not focused (its sheet is).
        for window in AX.value(element, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            if let kind = Self.kind(of: window) { return setDialog(make(window, kind)) }
        }
        setDialog(nil)
    }

    nonisolated static func kind(of element: AXUIElement) -> FileDialog.Kind? {
        guard let id = AX.identifier(element)?.lowercased() else { return nil }
        if id == "open-panel" || id.contains("openpanel") || id.contains("open-panel") { return .open }
        if id == "save-panel" || id.contains("savepanel") || id.contains("save-panel") { return .save }
        return nil
    }

    private func setDialog(_ new: FileDialog?) {
        if let new, new.isSame(as: dialog) { return }
        if new == nil, dialog == nil { return }
        if let old = dialog {
            // Closing: what it last showed becomes a recent folder.
            if let folder = currentFolder { AppSettings.shared.recordFolder(folder, app: old.bundleID) }
            Diagnostics.note("dialog closed in \(old.appName)")
        }
        dialog = new
        frame = new.flatMap { AX.frame($0.element) }
        currentFolder = nil
        folderTitle = nil
        navigatedFolder = nil
        wherePopup = nil
        if let new {
            Diagnostics.note("\(new.kind.rawValue) dialog in \(new.appName) at \(frame.map { "\($0)" } ?? "?")")
            wherePopup = AX.first(below: new.element, identifier: "where popup", budget: 200)
            checkFolderTitle()
            sampleFolder()
        }
        publish()
        onChange?()
    }

    private func publish() {
        let settings = AppSettings.shared
        Self.snapshot.set(DialogSnapshot.State(pid: dialog?.pid ?? 0, frame: frame ?? .null,
                                          clickThrough: dialog != nil && settings.clickThrough))
    }

    // MARK: - Accessibility notifications

    private func observe(_ app: NSRunningApplication?) {
        let pid = app?.processIdentifier ?? 0
        guard pid != observedPID else { return }
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = pid
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier, AX.isTrusted else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<DialogWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.rescan() }
        }, &created) == .success, let created else { return }
        let element = AX.app(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification, kAXSheetCreatedNotification,
                     kAXFocusedUIElementChangedNotification] {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
    }

    // MARK: - Which folder it shows

    /// The folder pop-up's text. A change means the dialog moved to another folder.
    private func checkFolderTitle() {
        guard let popup = wherePopup, let raw = AX.string(popup, kAXValueAttribute) else { return }
        let title = FolderPath.cleanedTitle(raw)
        guard title != folderTitle else { return }
        folderTitle = title
        if let navigated = navigatedFolder, Self.title(title, matches: navigated) {
            currentFolder = navigated
        } else {
            navigatedFolder = nil
        }
        sampleFolder()
        onChange?()
    }

    /// The pop-up shows a folder's display name, sometimes with " — iCloud" or a disk after it.
    static func title(_ title: String, matches path: String) -> Bool {
        let name = FileManager.default.displayName(atPath: path)
        return title == name || title.hasPrefix(name + " — ") || title == FolderPath.displayName(path)
    }

    /// Reads the folder from the items in the dialog's file list, off the main thread: the
    /// list's rows carry file URLs, and their folder is the one shown.
    private func sampleFolder() {
        guard let dialog, !sampling else { return }
        sampling = true
        let box = ElementBox(element: dialog.element)
        sampler.async { [weak self] in
            let folder = Self.folderFromFileList(box.element)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.sampling = false
                    guard self.dialog.map({ CFEqual($0.element, box.element) }) == true else { return }
                    if let folder, folder != self.currentFolder {
                        self.currentFolder = folder
                        self.onChange?()
                    } else if folder == nil, let navigated = self.navigatedFolder,
                              let title = self.folderTitle, Self.title(title, matches: navigated) {
                        self.currentFolder = navigated
                    }
                }
            }
        }
    }

    /// In column view (a browser) the deepest folder is the one shown; in list view the
    /// top-level rows are, and opened disclosure triangles add deeper ones.
    nonisolated static func folderFromFileList(_ dialog: AXUIElement) -> String? {
        var queue: [(AXUIElement, Int, Bool)] = [(dialog, 0, false)]
        var seen = 0
        var parents: [String] = []
        var inBrowser = false
        while !queue.isEmpty, seen < 900, parents.count < 40 {
            let (element, depth, browser) = queue.removeFirst()
            seen += 1
            let role = AX.role(element)
            if let url = AX.value(element, kAXURLAttribute), let path = resolve(url) {
                parents.append(FolderPath.parent(of: path))
                inBrowser = inBrowser || browser
                continue
            }
            // Skip parts that never hold the file list.
            if role == kAXButtonRole || role == kAXStaticTextRole || role == kAXImageRole || role == kAXPopUpButtonRole { continue }
            if depth < 25 {
                let isBrowser = browser || role == kAXBrowserRole
                queue += AX.children(element).map { ($0, depth + 1, isBrowser) }
            }
        }
        guard !parents.isEmpty else { return nil }
        return inBrowser ? parents.max { $0.count < $1.count } : parents.min { $0.count < $1.count }
    }

    /// File reference URLs ("file:///.file/id=…") resolved to a path.
    nonisolated static func resolve(_ value: AnyObject) -> String? {
        let url: URL? = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
        guard let url, url.isFileURL else { return nil }
        let resolved = ((url as NSURL).filePathURL ?? url)
        let path = resolved.path
        return path.hasPrefix("/.file/") ? nil : path
    }

    /// JumpFolder took the dialog to `path`: trust it until the pop-up shows another folder.
    func didNavigate(to path: String) {
        navigatedFolder = path
        currentFolder = path
        if let dialog { AppSettings.shared.recordFolder(path, app: dialog.bundleID) }
        onChange?()
    }

    // MARK: - Debug

    func dump() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication else { return "no frontmost app" }
        var lines = ["frontmost \(app.localizedName ?? "?") pid \(app.processIdentifier)",
                     "dialog \(dialog.map { "\($0.kind) in \($0.appName)" } ?? "none") frame \(frame.map { "\($0)" } ?? "-")",
                     "title \(folderTitle ?? "-") folder \(currentFolder ?? "-")"]
        let element = AX.app(app.processIdentifier)
        for window in AX.value(element, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            AX.dump(window, maxDepth: 3, into: &lines)
        }
        return lines.joined(separator: "\n")
    }
}
