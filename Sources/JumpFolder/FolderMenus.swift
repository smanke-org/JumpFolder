import AppKit
import JumpFolderKit

/// The folder lists shown beside a dialog, in the menu bar menu and by the shortcuts.
/// Picking a folder takes the dialog in front there; with no dialog open, it opens the
/// folder in Finder.
@MainActor
enum FolderMenus {
    private final class Target: NSObject {
        @MainActor @objc func pick(_ item: NSMenuItem) {
            guard let path = item.representedObject as? String else { return }
            FolderMenus.open(path)
        }
        @MainActor @objc func clearRecents() { AppSettings.shared.history.clear() }
        @MainActor @objc func addFavorite(_ item: NSMenuItem) {
            guard let path = item.representedObject as? String else { return }
            Favorites.add(path, to: &AppSettings.shared.favorites)
        }
        @MainActor @objc func editFavorites() { SettingsWindow.shared.show(tab: "Folders") }
    }

    private static let target = Target()

    static func open(_ path: String) {
        if DialogWatcher.shared.dialog != nil {
            DialogNavigator.go(to: path)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    static func exists(_ path: String) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && isFolder.boolValue
    }

    static func folderItem(_ path: String, title: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title ?? FileManager.default.displayName(atPath: path),
                              action: #selector(Target.pick(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = path
        item.toolTip = FolderPath.abbreviated(path)
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        item.showIcon(icon)
        return item
    }

    private static func note(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Recent folders: the app's own first, then every app's.
    static func recentsMenu(for app: FileDialog?) -> NSMenu {
        let menu = NSMenu(title: "Recent Folders")
        menu.autoenablesItems = false
        let history = AppSettings.shared.history
        let own = history.ownRecent(for: app?.bundleID, count: 10, exists: exists)
        let all = history.paths.filter { !own.contains($0) && exists($0) }
        let titles = distinctTitles(own + all)
        if let app, !own.isEmpty {
            menu.addItem(note("In \(app.appName)"))
            for path in own { menu.addItem(folderItem(path, title: titles[path])) }
            if !all.isEmpty {
                menu.addItem(.separator())
                menu.addItem(note("All Apps"))
            }
        }
        if own.isEmpty, all.isEmpty {
            menu.addItem(note("No recent folders yet"))
        }
        for path in all { menu.addItem(folderItem(path, title: titles[path])) }
        menu.addItem(.separator())
        let clear = menu.addItem(withTitle: "Clear Recent Folders", action: #selector(Target.clearRecents), keyEquivalent: "")
        clear.target = target
        clear.isEnabled = !history.entries.isEmpty
        return menu
    }

    /// Folder names, with the enclosing folder's name added where two share a name
    /// ("JumpFolder — Sources").
    static func distinctTitles(_ paths: [String]) -> [String: String] {
        let names = paths.map { FileManager.default.displayName(atPath: $0) }
        var counts: [String: Int] = [:]
        names.forEach { counts[$0, default: 0] += 1 }
        var titles: [String: String] = [:]
        for (path, name) in zip(paths, names) {
            let parent = FileManager.default.displayName(atPath: (path as NSString).deletingLastPathComponent)
            titles[path] = counts[name, default: 0] > 1 ? "\(name) — \(parent)" : name
        }
        return titles
    }

    /// Everything the bottom bar draws its folders from, for its More button.
    static func sourceMenu(_ source: BarSource) -> NSMenu {
        let app = DialogWatcher.shared.dialog
        switch source {
        case .favorites: return favoritesMenu(currentFolder: DialogWatcher.shared.currentFolder)
        case .recent: return recentsMenu(for: app)
        case .mostUsed:
            let menu = NSMenu(title: "Most Used Folders")
            menu.autoenablesItems = false
            let paths = AppSettings.shared.history.mostUsed(for: app?.bundleID, count: 15, exists: exists)
            if let app { menu.addItem(note("Most Used in \(app.appName)")) }
            if paths.isEmpty { menu.addItem(note("No folders yet")) }
            for path in paths { menu.addItem(folderItem(path)) }
            return menu
        }
    }

    static func favoritesMenu(currentFolder: String?) -> NSMenu {
        let menu = NSMenu(title: "Favorite Folders")
        menu.autoenablesItems = false
        let favorites = AppSettings.shared.favorites
        if favorites.isEmpty { menu.addItem(note("No favorites yet")) }
        for favorite in favorites {
            let item = folderItem(favorite.path, title: favorite.displayName)
            item.isEnabled = exists(favorite.path)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        if let folder = currentFolder, !favorites.contains(where: { $0.path == folder }) {
            let add = menu.addItem(withTitle: "Add “\(FileManager.default.displayName(atPath: folder))” to Favorites",
                                   action: #selector(Target.addFavorite(_:)), keyEquivalent: "")
            add.target = target
            add.representedObject = folder
            add.showIcon("star.badge.plus")
        }
        let edit = menu.addItem(withTitle: "Edit Favorites…", action: #selector(Target.editFavorites), keyEquivalent: "")
        edit.target = target
        return menu
    }

    /// Finder's open windows, front to back. Asks Finder first, so it calls back.
    static func finderWindowsMenu(_ done: @escaping @MainActor (NSMenu) -> Void) {
        FinderWindows.list { windows, error in
            let menu = NSMenu(title: "Finder Windows")
            menu.autoenablesItems = false
            var seen = Set<String>()
            for window in windows where !window.path.isEmpty && seen.insert(window.path).inserted {
                menu.addItem(folderItem(window.path, title: window.name))
            }
            if menu.items.isEmpty {
                menu.addItem(note(error ?? "No Finder windows open"))
            }
            done(menu)
        }
    }

    /// Shows the dialog's folder in Finder.
    static func reveal(_ path: String?) {
        guard let path, exists(path) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
}
