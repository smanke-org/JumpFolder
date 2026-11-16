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

    /// A folder as one app used it.
    public struct AppFolder: Codable, Equatable, Sendable {
        public var path: String
        public var lastUsed: Date
        public var uses: Int
        public init(path: String, lastUsed: Date, uses: Int) {
            self.path = path
            self.lastUsed = lastUsed
            self.uses = uses
        }
    }

    public static let defaultLimit = 15
    public static let limitRange = 5...50
    /// How many folders each app keeps for Recent and Most Used.
    public static let perAppLimit = 50
    /// Below this many folders of its own, an app's lists are topped up from every app's.
    public static let ownFolderMinimum = 3

    public private(set) var entries: [Entry] = []
    /// Bundle id → the folder that app's dialog was last in.
    public private(set) var lastByApp: [String: String] = [:]
    /// Bundle id → the folders that app's dialogs used, with how often.
    public private(set) var byApp: [String: [AppFolder]] = [:]

    public init(entries: [Entry] = [], lastByApp: [String: String] = [:], byApp: [String: [AppFolder]] = [:]) {
        self.entries = entries
        self.lastByApp = lastByApp
        self.byApp = byApp
    }

    private enum CodingKeys: String, CodingKey { case entries, lastByApp, byApp }

    /// History saved before per-app lists existed still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        lastByApp = try c.decodeIfPresent([String: String].self, forKey: .lastByApp) ?? [:]
        byApp = try c.decodeIfPresent([String: [AppFolder]].self, forKey: .byApp) ?? [:]
    }

    public var paths: [String] { entries.map(\.path) }

    /// Moves `path` to the top (or adds it there), notes it as `app`'s last folder, counts a
    /// use for `app`, and keeps at most `limit` entries.
    public mutating func record(_ path: String, app: String?, at date: Date = Date(), limit: Int = defaultLimit) {
        let path = FolderPath.normalized(path)
        guard !path.isEmpty else { return }
        entries.removeAll { $0.path == path }
        entries.insert(Entry(path: path, date: date), at: 0)
        trim(to: limit)
        guard let app, !app.isEmpty else { return }
        lastByApp[app] = path
        var folders = byApp[app] ?? []
        if let index = folders.firstIndex(where: { $0.path == path }) {
            folders[index].uses += 1
            folders[index].lastUsed = date
        } else {
            folders.append(AppFolder(path: path, lastUsed: date, uses: 1))
        }
        if folders.count > Self.perAppLimit {
            folders.sort { $0.lastUsed > $1.lastUsed }
            folders.removeLast(folders.count - Self.perAppLimit)
        }
        byApp[app] = folders
    }

    public mutating func trim(to limit: Int) {
        let limit = min(max(limit, Self.limitRange.lowerBound), Self.limitRange.upperBound)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    public mutating func remove(_ path: String) {
        entries.removeAll { $0.path == path }
        lastByApp = lastByApp.filter { $0.value != path }
        byApp = byApp.mapValues { $0.filter { $0.path != path } }
    }

    public mutating func clear() {
        entries = []
        lastByApp = [:]
        byApp = [:]
    }

    /// Only `app`'s own folders, newest first (no topping up).
    public func ownRecent(for app: String?, count: Int, exists: (String) -> Bool = { _ in true }) -> [String] {
        let own = (app.flatMap { byApp[$0] } ?? []).sorted { $0.lastUsed > $1.lastUsed }.map(\.path)
        return Array(own.filter(exists).prefix(count))
    }

    /// `app`'s folders, newest first.
    public func recent(for app: String?, count: Int, exists: (String) -> Bool = { _ in true }) -> [String] {
        let own = (app.flatMap { byApp[$0] } ?? []).sorted { $0.lastUsed > $1.lastUsed }.map(\.path)
        return topUp(own, count: count, exists: exists)
    }

    /// `app`'s folders, most used first (ties: newest first).
    public func mostUsed(for app: String?, count: Int, exists: (String) -> Bool = { _ in true }) -> [String] {
        let own = (app.flatMap { byApp[$0] } ?? [])
            .sorted { ($0.uses, $0.lastUsed) > ($1.uses, $1.lastUsed) }.map(\.path)
        return topUp(own, count: count, exists: exists)
    }

    /// An app with only a few folders of its own gets every app's recent ones after them.
    private func topUp(_ own: [String], count: Int, exists: (String) -> Bool) -> [String] {
        var result = own.filter(exists)
        if result.count < Self.ownFolderMinimum {
            for path in paths where !result.contains(path) && exists(path) { result.append(path) }
        }
        return Array(result.prefix(count))
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
