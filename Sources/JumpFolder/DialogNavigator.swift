import AppKit
import Carbon.HIToolbox
import JumpFolderKit

/// Takes the dialog in front to a folder. First without anything popping up: from where the
/// dialog is, a folder or two up, or a place it has a key for (Home, Desktop…), it opens one
/// folder row after another through Accessibility (`FolderRoute`). When that can't work (a
/// hidden folder, a collapsed Save dialog), it falls back to what a person would do: ⌘⇧G
/// opens the dialog's "Go to" sheet, the path is typed into it, and Return goes there.
/// Setting the field's text through Accessibility alone shows the path but leaves the
/// dialog's own copy unchanged, so the path is typed as key events.
@MainActor
enum DialogNavigator {
    /// Marks JumpFolder's own key events, so the click tap lets them through untouched.
    static let eventTag: Int64 = 0x4A46_4C44

    private static var busy = false
    /// Moving a dialog right now.
    static var isBusy: Bool { busy }

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
        if await openRows(to: path, in: dialog) { return true }
        guard isFront(dialog) else {
            Diagnostics.note("dialog went to the back")
            return false
        }
        Diagnostics.note("no row route to \(path); using Go to")
        return await goToSheet(path, in: dialog)
    }

    // MARK: - Row by row

    /// How long one folder may take to list its contents before giving up on rows.
    private static let rowTimeout: Duration = .milliseconds(1500)

    private static func openRows(to path: String, in dialog: FileDialog) async -> Bool {
        let watcher = DialogWatcher.shared
        let current = watcher.currentFolder
        let volume = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeURLKey]).volume?.path) ?? "/"
        // ⌘↑ in a Save dialog's name field moves the caret instead, so no going up there.
        let ups = dialog.kind == .save ? 0 : 2
        let sidebar = SidebarPlaces.read(in: dialog.element)
        let isHidden = { (path: String) in (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isHiddenKey]).isHidden) == true }
        // Dialogs don't list hidden folders (~/Library, /tmp…), so routes through them are dropped.
        guard let plan = FolderRoute.plan(to: path, from: current, home: NSHomeDirectory(), volume: volume, maxUps: ups,
                                          sidebar: sidebar.map(\.path),
                                          real: { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                                          hidden: isHidden) else {
            return false
        }
        Diagnostics.note("route to \(path): \(plan.start) then \(plan.opens.count) folder(s)")
        let box = ElementBox(element: dialog.element)
        guard let popup = AX.first(below: dialog.element, identifier: "where popup", budget: 200) else { return false }
        switch plan.start {
        case .here:
            // Nothing to open means it is already there, as far as JumpFolder knows.
            if plan.opens.isEmpty { return true }
        case .up(let count):
            // One folder at a time: a second ⌘↑ before the first lands can go one too far.
            var folder = URL(fileURLWithPath: current ?? "/").resolvingSymlinksInPath().path
            for _ in 0..<count {
                guard isFront(dialog) else { return false }
                folder = (folder as NSString).deletingLastPathComponent
                postKey(kVK_UpArrow, flags: .maskCommand)
                guard await waitForFolder(folder, popup: popup, for: rowTimeout) else {
                    Diagnostics.note("⌘↑ didn't reach \(folder)")
                    return false
                }
            }
        case .sidebar(let folder):
            guard isFront(dialog), let place = sidebar.first(where: { $0.path == folder }) else { return false }
            AXUIElementPerformAction(place.cell, "AXOpen" as CFString)
            // The pop-up shows the sidebar's name for it ("OneDrive"), not always the folder's.
            guard await waitForFolder(folder, popup: popup, for: rowTimeout, alsoNamed: place.name) else {
                Diagnostics.note("sidebar \(place.name) didn't open")
                return false
            }
            if plan.opens.isEmpty { return true }
        case .place(let place):
            guard isFront(dialog) else { return false }
            let (code, flags) = key(for: place)
            postKey(code, flags: flags)
            if plan.opens.isEmpty {
                return await waitForFolder(path, popup: popup, for: rowTimeout)
            }
        }
        for step in plan.opens {
            // Right after ⌘↑ or a place key the list may still be settling: it can ignore an
            // open, or rebuild its rows so the one found is gone. Find it again and retry.
            var opened = false
            for _ in 0..<3 where !opened {
                guard let row = await findRow(step, in: box) else {
                    Diagnostics.note("no row for \(step)")
                    return false
                }
                guard isFront(dialog) else { return false }
                select(row)
                AXUIElementPerformAction(row, "AXOpen" as CFString)
                opened = await waitForFolder(step, popup: popup, for: .milliseconds(400))
            }
            guard opened else {
                Diagnostics.note("\(step) didn't open")
                return false
            }
        }
        return true
    }

    /// Selects the row holding `field`. After ⌘↑ the dialog keeps the folder it came from
    /// selected, and opening goes by the selection.
    private static func select(_ field: AXUIElement) {
        var element = field
        for _ in 0..<4 {
            guard let parent = AX.element(element, kAXParentAttribute) else { return }
            if AX.role(parent) == kAXRowRole {
                AX.set(parent, kAXSelectedAttribute, kCFBooleanTrue)
                return
            }
            element = parent
        }
    }

    private static func key(for place: FolderRoute.Place) -> (Int, CGEventFlags) {
        switch place {
        case .home: (kVK_ANSI_H, [.maskCommand, .maskShift])
        case .desktop: (kVK_ANSI_D, [.maskCommand, .maskShift])
        case .documents: (kVK_ANSI_O, [.maskCommand, .maskShift])
        case .downloads: (kVK_ANSI_L, [.maskCommand, .maskAlternate])
        case .applications: (kVK_ANSI_A, [.maskCommand, .maskShift])
        case .computer: (kVK_ANSI_C, [.maskCommand, .maskShift])
        }
    }

    /// The row for `path` in the dialog's file list, once the list shows it.
    private static func findRow(_ path: String, in box: ElementBox) async -> AXUIElement? {
        let wanted = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let parent = (wanted as NSString).deletingLastPathComponent
        let deadline = ContinuousClock.now + rowTimeout
        while ContinuousClock.now < deadline {
            let search = await Task.detached { RowSearch(wanted, parent: parent, below: box.element) }.value
            if let row = search.row { return row }
            // The folder is listed but the row isn't: the list only describes the rows on
            // screen, so page through it.
            if search.listsParent, let area = search.scrollArea {
                return await scrollFor(wanted, parent: parent, in: area, box: box)
            }
            try? await Task.sleep(for: .milliseconds(15))
        }
        return nil
    }

    /// Steps the list's scroll bar a page at a time until the row shows up.
    private static func scrollFor(_ wanted: String, parent: String, in area: AXUIElement, box: ElementBox) async -> AXUIElement? {
        guard let bar = AX.element(area, kAXVerticalScrollBarAttribute),
              let height = AX.frame(area)?.height, height > 0 else { return nil }
        var content = CGSize.zero
        if let value = AX.value(area, "AXContentSize"), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(value as! AXValue, .cgSize, &content)
        }
        let hidden = content.height - height
        let step = hidden > 0 ? min(1, 0.85 * height / hidden) : 0.1
        var position = 0.0
        while position <= 1 {
            AX.set(bar, kAXValueAttribute, position as CFNumber)
            try? await Task.sleep(for: .milliseconds(20))
            let search = await Task.detached { RowSearch(wanted, parent: parent, below: box.element) }.value
            if let row = search.row { return row }
            position = position >= 1 ? 2 : min(1, position + step)
        }
        return nil
    }

    /// The pop-up above the list names the folder shown; wait for it to name `path`.
    private static func waitForFolder(_ path: String, popup: AXUIElement, for timeout: Duration,
                                      alsoNamed name: String? = nil) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while true {
            if let raw = AX.string(popup, kAXValueAttribute) {
                let title = FolderPath.cleanedTitle(raw)
                if DialogWatcher.title(title, matches: path) || title == name { return true }
            }
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    // MARK: - Go to sheet

    private static func goToSheet(_ path: String, in dialog: FileDialog) async -> Bool {
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

/// One look through the dialog for a file row, reading each element's role, URL and children
/// in one round trip. File rows are text fields with a file URL.
private struct RowSearch: @unchecked Sendable {
    var row: AXUIElement?
    /// The scroll area holding the file rows.
    var scrollArea: AXUIElement?
    /// Whether rows from `parent` were seen, so that folder is listed.
    var listsParent = false

    init(_ wanted: String, parent: String, below root: AXUIElement) {
        let attributes = [kAXRoleAttribute, kAXURLAttribute, kAXChildrenAttribute] as CFArray
        let skip: Set<String> = [kAXButtonRole, kAXStaticTextRole, kAXImageRole, kAXPopUpButtonRole, kAXMenuButtonRole,
                                 kAXScrollBarRole, kAXColumnRole, kAXValueIndicatorRole, kAXSheetRole]
        var queue: [(AXUIElement, AXUIElement?)] = [(root, nil)]
        var index = 0
        while index < queue.count, index < 4000 {
            let (element, area) = queue[index]
            index += 1
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, attributes, [], &values) == .success,
                  let list = values as? [AnyObject], list.count == 3 else { continue }
            let role = list[0] as? String ?? ""
            if let url = AX.isError(list[1]) ? nil : DialogWatcher.resolve(list[1]) {
                let path = URL(fileURLWithPath: url).resolvingSymlinksInPath().path
                if path == wanted {
                    row = element
                    return
                }
                if (path as NSString).deletingLastPathComponent == parent {
                    listsParent = true
                    scrollArea = area
                }
                continue
            }
            // The dialog itself may be a sheet (a Save sheet); a sheet inside it is "Go to".
            if index > 1, skip.contains(role) { continue }
            let inside = role == kAXScrollAreaRole ? element : area
            if let children = list[2] as? [AXUIElement] { queue += children.map { ($0, inside) } }
        }
    }
}
