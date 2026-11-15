import Foundation

/// The folders Open and Save dialogs were last in, newest first. Kept per Mac: paths and
/// disks differ between Macs.
public struct FolderHistory: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var path: String
        public var date: Date
        public init(path: String, date: Date) {
            self.path = path
            self.date = date
        }
    }

    public static let defaultLimit = 15
    public static let limitRange = 5...50

    public private(set) var entries: [Entry] = []
    /// Bundle id → the folder that app's dialog was last in.
    public private(set) var lastByApp: [String: String] = [:]

    public init(entries: [Entry] = [], lastByApp: [String: String] = [:]) {
        self.entries = entries
        self.lastByApp = lastByApp
    }

    public var paths: [String] { entries.map(\.path) }

    /// Moves `path` to the top (or adds it there), notes it as `app`'s last folder, and
    /// keeps at most `limit` entries.
    public mutating func record(_ path: String, app: String?, at date: Date = Date(), limit: Int = defaultLimit) {
        let path = FolderPath.normalized(path)
        guard !path.isEmpty else { return }
        entries.removeAll { $0.path == path }
        entries.insert(Entry(path: path, date: date), at: 0)
        trim(to: limit)
        if let app, !app.isEmpty { lastByApp[app] = path }
    }

    public mutating func trim(to limit: Int) {
        let limit = min(max(limit, Self.limitRange.lowerBound), Self.limitRange.upperBound)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    public mutating func remove(_ path: String) {
        entries.removeAll { $0.path == path }
        lastByApp = lastByApp.filter { $0.value != path }
    }

    public mutating func clear() {
        entries = []
        lastByApp = [:]
    }

    /// What the Recent Folders menu lists for `app`: its own last folder first (if it has
    /// one), then the rest, never twice, skipping any `exists` says is gone.
    public func menuPaths(for app: String?, exists: (String) -> Bool = { _ in true }) -> (appLast: String?, others: [String]) {
        let appLast = app.flatMap { lastByApp[$0] }.flatMap { exists($0) ? $0 : nil }
        let others = paths.filter { $0 != appLast && exists($0) }
        return (appLast, others)
    }
}

/// A folder the user pinned. Synced between Macs.
public struct Favorite: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var path: String
    /// Empty: the folder's own name.
    public var name: String

    public var id: String { path }

    public init(path: String, name: String = "") {
        self.path = FolderPath.normalized(path)
        self.name = name
    }

    public var displayName: String { name.isEmpty ? FolderPath.displayName(path) : name }
}

public enum Favorites {
    /// Adds `path` at the end unless it is already there. Returns whether it was added.
    @discardableResult
    public static func add(_ path: String, to list: inout [Favorite]) -> Bool {
        let path = FolderPath.normalized(path)
        guard !path.isEmpty, !list.contains(where: { $0.path == path }) else { return false }
        list.append(Favorite(path: path))
        return true
    }
}

public enum FolderPath {
    /// No trailing slash (except the root), no `~`, no `.` or `..` parts.
    public static func normalized(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return "" }
        let standard = (expanded as NSString).standardizingPath
        return standard.isEmpty ? "/" : standard
    }

    /// The last part of the path, "Macintosh HD"-style for the root.
    public static func displayName(_ path: String, rootName: String = "Computer") -> String {
        let path = normalized(path)
        if path == "/" { return rootName }
        return (path as NSString).lastPathComponent
    }

    /// `~/Documents` for a folder in `home`, the full path otherwise. For menus' hover text.
    public static func abbreviated(_ path: String, home: String = NSHomeDirectory()) -> String {
        let path = normalized(path)
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// The folder holding a file URL's item (for a folder row, the folder above it).
    public static func parent(of filePath: String) -> String {
        let path = normalized(filePath)
        guard path != "/" else { return "/" }
        return (path as NSString).deletingLastPathComponent
    }

    /// The text of the dialog's folder pop-up ("TextEdit — iCloud") without the
    /// direction marks AppKit wraps names in.
    public static func cleanedTitle(_ title: String) -> String {
        title.unicodeScalars.filter { !(0x2066...0x2069).contains($0.value) && $0.value != 0x200E && $0.value != 0x200F }
            .map(String.init).joined()
    }
}
