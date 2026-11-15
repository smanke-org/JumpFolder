import AppKit
import JumpFolderKit

/// The menu bar menu. Rebuilt each time it opens, so the folder lists are current.
/// The menu holds actions; preferences live in Settings.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        // Enabled state is set by hand below; auto-enabling would override it.
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateIcon()

        // Settings can hide the menu bar icon (the app then lives in the Dock, or nowhere),
        // and ToolHUD can take the menu into its own while it runs.
        statusItem.isVisible = MenuHub.shared.showsOwnIcon
        NotificationCenter.default.addObserver(forName: AppPresence.menuBarDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusItem.isVisible = MenuHub.shared.showsOwnIcon }
        }
        MenuHub.shared.start(menu: { [weak self] in
            let menu = NSMenu()
            menu.autoenablesItems = false
            self?.menuNeedsUpdate(menu)
            return menu
        }, icon: { [weak self] in
            self?.updateIcon()
            return self?.statusItem.button?.image
        })
    }

    /// A folder with an arrow; a warning sign while access is missing, since nothing works without it.
    func updateIcon() {
        let symbol = AX.isTrusted ? "arrow.up.folder" : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "JumpFolder")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        updateIcon()
        let settings = AppSettings.shared

        if !AX.isTrusted {
            menu.addItem(withTitle: "Grant Access…", action: #selector(grantAccess), target: self)
                .showIcon("exclamationmark.triangle").toolTip = "JumpFolder needs access to see Open and Save dialogs."
            menu.addItem(.separator())
        }

        let status = menu.addItem(withTitle: DialogWatcher.shared.statusLine, action: nil, target: nil)
        status.isEnabled = false

        // The same lists as beside a dialog. Picking one with no dialog open shows it in Finder.
        let recents = menu.addItem(withTitle: "Recent Folders", action: nil, target: nil)
        recents.showIcon("clock.arrow.circlepath")
        recents.submenu = FolderMenus.recentsMenu(for: nil)
        let favorites = menu.addItem(withTitle: "Favorite Folders", action: nil, target: nil)
        favorites.showIcon("star")
        favorites.submenu = FolderMenus.favoritesMenu(currentFolder: nil)

        menu.addItem(.separator())
        let click = menu.addItem(withTitle: "Click Finder Windows to Jump", action: #selector(toggleClickThrough), target: self)
        click.state = settings.clickThrough ? .on : .off
        click.toolTip = "While an Open or Save dialog is in front, clicking a Finder window behind it takes the dialog to that folder. Hold Option to bring Finder forward instead."
        let edge = menu.addItem(withTitle: "Show Folder Buttons Beside Dialogs", action: #selector(toggleEdgeControls), target: self)
        edge.state = settings.edgeControls ? .on : .off

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",", target: self).showIcon("gearshape")
        menu.addItem(withTitle: "JumpFolder Help", action: #selector(showHelp), target: self).showIcon("questionmark.circle")
        if let staged = AutoUpdater.shared.staged {
            menu.addItem(withTitle: "Update to \(staged.version) Now", action: #selector(installStagedUpdate), target: self)
                .showIcon("arrow.down.circle")
        } else if let pending = UpdateAvailability.shared.pending {
            menu.addItem(withTitle: "Update to \(pending)…", action: #selector(checkForUpdates), target: self)
                .showIcon("arrow.down.circle").toolTip = "A newer release is available. Installing it needs your confirmation."
        } else {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), target: self)
                .showIcon("arrow.down.circle")
        }
        menu.addItem(withTitle: "About JumpFolder", action: #selector(showAbout), target: self)
        menu.addItem(withTitle: "Our other apps…", action: #selector(showOtherApps), target: self)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit JumpFolder", action: #selector(quit), keyEquivalent: "q", target: self)
        menu.addItem(.separator())
        let version = menu.addItem(withTitle: "JumpFolder \(AppInfo.displayVersion)", action: nil, target: nil)
        version.isEnabled = false
    }

    /// The menu as built when it opens, for the debug hook and snapshot mode.
    func freshMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menuNeedsUpdate(menu)
        return menu
    }

    /// One line per item with its shortcut (a global one from Settings, or the menu's own key),
    /// whether it shows an icon, and whether it's disabled — for the debug hook.
    func dumpMenu() -> String {
        freshMenu().items.map { item in
            guard !item.isSeparatorItem else { return "---" }
            let parts = item.plainTitle.split(separator: "\t", maxSplits: 1).map(String.init)
            var line = parts[0]
            if parts.count > 1 { line += "  " + parts[1] }
            if !item.keyEquivalent.isEmpty { line += "  " + item.keyEquivalentDisplay }
            if item.titleIcon != nil { line += "  [icon]" }
            if !item.isEnabled { line += "  (disabled)" }
            return line
        }.joined(separator: "\n")
    }

    @objc private func grantAccess() { WelcomeWindow.shared.show() }
    @objc private func toggleClickThrough() { AppSettings.shared.clickThrough.toggle() }
    @objc private func toggleEdgeControls() { AppSettings.shared.edgeControls.toggle() }
    @objc private func showSettings() { SettingsWindow.shared.show() }
    @objc private func showHelp() { HelpWindow.shared.show() }
    @objc private func checkForUpdates() { UpdateController.checkForUpdates() }
    @objc private func installStagedUpdate() { AutoUpdater.shared.installNow() }
    @objc private func showAbout() { AppInfo.showAbout() }
    /// The developer's site, which lists every app.
    @objc private func showOtherApps() {
        if let url = URL(string: "https://stevemanke.com/") { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension NSMenuItem {
    /// The menu's own key as macOS shows it: "⌘,", "⌘Q".
    var keyEquivalentDisplay: String {
        let mask = keyEquivalentModifierMask
        var symbols = ""
        if mask.contains(.control) { symbols += "⌃" }
        if mask.contains(.option) { symbols += "⌥" }
        if mask.contains(.shift) || keyEquivalent != keyEquivalent.lowercased() { symbols += "⇧" }
        if mask.contains(.command) { symbols += "⌘" }
        return symbols + keyEquivalent.uppercased()
    }
}

@MainActor
extension NSMenu {
    /// An item aimed at `target`, optionally showing a global shortcut from Settings (shown
    /// only; Carbon fires it, not the menu).
    @discardableResult
    func addItem(withTitle title: String, action: Selector?, keyEquivalent: String = "", target: AnyObject?, shortcut: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        if let id = shortcut, let key = AppSettings.shared.shortcut(id) {
            item.title = title + "\t" + key.display
        }
        addItem(item)
        return item
    }
}
