import AppKit
import JumpFolderKit
import Observation

/// App-wide preferences (UserDefaults). Favorites and excluded apps sync between Macs;
/// recent folders describe this Mac and stay here.
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = AppSettings.store

    /// Where these settings and AppPresence's are kept. An agent CLI test copy (a Debug build run
    /// with `APP_STORE`) keeps its own, so `jumpfolder settings set` never reaches the real ones.
    nonisolated(unsafe) static let store: UserDefaults = {
        #if DEBUG
        if AgentSocket.isTestRun, let suite = UserDefaults(suiteName: "com.smanke.JumpFolder.agenttest") { return suite }
        #endif
        return .standard
    }()

    /// A scratch folder for test runs (`JUMPFOLDER_DATA_DIR`), so they never reach iCloud.
    nonisolated static var testFolder: URL? {
        guard let dir = ProcessInfo.processInfo.environment["JUMPFOLDER_DATA_DIR"], !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: dir)
    }

    enum Key {
        static let confirmQuit = "confirmQuit"
        static let shortcuts = "shortcuts"
        static let clickThrough = "clickThrough"
        static let edgeControls = "edgeControls"
        static let edgeSide = "edgeSide"
        static let edgeLabels = "edgeLabels"
        static let hoverHint = "hoverHint"
        static let favorites = "favorites"
        static let excludedApps = "excludedApps"
        static let recentsLimit = "recentsLimit"
        static let history = "folderHistory"
    }

    /// "Ask before quitting" in General.
    var confirmQuit: Bool {
        didSet { defaults.set(confirmQuit, forKey: Key.confirmQuit) }
    }

    /// Launch at login is switched on once, the first time the app runs from /Applications.
    var didOfferLaunchAtLogin: Bool {
        get { defaults.bool(forKey: "didOfferLaunchAtLogin") }
        set { defaults.set(newValue, forKey: "didOfferLaunchAtLogin") }
    }

    /// Mirrors AppPresence, so Settings can bind to it and the Dock icon follows at once.
    var showInDock: Bool {
        didSet {
            AppPresence.showInDock = showInDock
            AppPresence.applyDock(keepInFront: NSApp.keyWindow)
        }
    }

    var showInMenuBar: Bool {
        didSet { AppPresence.showInMenuBar = showInMenuBar }
    }

    /// Clicking a Finder window behind a dialog takes the dialog there (Settings › Dialogs).
    var clickThrough: Bool {
        didSet { defaults.set(clickThrough, forKey: Key.clickThrough) }
    }

    /// A ring and a "Jump to" label on the Finder window under the pointer (Settings › Dialogs).
    var hoverHint: Bool {
        didSet { defaults.set(hoverHint, forKey: Key.hoverHint) }
    }

    /// The strip of folder buttons beside every Open and Save dialog (Settings › Dialogs).
    var edgeControls: Bool {
        didSet { defaults.set(edgeControls, forKey: Key.edgeControls) }
    }

    var edgeSide: EdgeSide {
        didSet { defaults.set(edgeSide.rawValue, forKey: Key.edgeSide) }
    }

    /// Names under the strip's icons ("Recent", "Favorites"…), or icons alone.
    var edgeLabels: Bool {
        didSet { defaults.set(edgeLabels, forKey: Key.edgeLabels) }
    }

    var favorites: [Favorite] {
        didSet { if let data = try? JSONEncoder().encode(favorites) { defaults.set(data, forKey: Key.favorites) } }
    }

    /// Bundle ids of apps whose dialogs JumpFolder leaves alone.
    var excludedApps: [String] {
        didSet { defaults.set(excludedApps, forKey: Key.excludedApps) }
    }

    /// How many recent folders to keep.
    var recentsLimit: Int {
        didSet {
            defaults.set(recentsLimit, forKey: Key.recentsLimit)
            history.trim(to: recentsLimit)
        }
    }

    /// Recent folders and each app's last folder. Per Mac, never synced.
    var history: FolderHistory {
        didSet { if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: Key.history) } }
    }

    /// Shortcut id → key. A missing id means "the default"; an id stored as null means the
    /// user cleared it.
    private var shortcuts: [String: HotKey?]

    private init() {
        confirmQuit = defaults.object(forKey: Key.confirmQuit) as? Bool ?? true
        showInDock = AppPresence.showInDock
        showInMenuBar = AppPresence.showInMenuBar
        shortcuts = Self.loadShortcuts(from: defaults)
        clickThrough = defaults.object(forKey: Key.clickThrough) as? Bool ?? true
        hoverHint = defaults.object(forKey: Key.hoverHint) as? Bool ?? true
        edgeControls = defaults.object(forKey: Key.edgeControls) as? Bool ?? true
        edgeSide = defaults.string(forKey: Key.edgeSide).flatMap(EdgeSide.init(rawValue:)) ?? .automatic
        edgeLabels = defaults.object(forKey: Key.edgeLabels) as? Bool ?? true
        favorites = Self.loadFavorites(from: defaults)
        excludedApps = defaults.stringArray(forKey: Key.excludedApps) ?? []
        recentsLimit = defaults.object(forKey: Key.recentsLimit) as? Int ?? FolderHistory.defaultLimit
        history = defaults.data(forKey: Key.history).flatMap { try? JSONDecoder().decode(FolderHistory.self, from: $0) } ?? FolderHistory()
    }

    func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains(bundleID)
    }

    func recordFolder(_ path: String, app: String?) {
        guard !isExcluded(app) else { return }
        history.record(path, app: app, limit: recentsLimit)
    }

    func shortcut(_ id: String) -> HotKey? {
        if let stored = shortcuts[id] { return stored }
        return ShortcutCatalog.item(id)?.defaultKey
    }

    func setShortcut(_ id: String, _ key: HotKey?) {
        shortcuts[id] = .some(key)
        if let data = try? JSONEncoder().encode(shortcuts) { defaults.set(data, forKey: Key.shortcuts) }
    }

    /// The shortcut already using `key`, other than `id` itself.
    func owner(of key: HotKey, except id: String) -> ShortcutCatalog.Item? {
        ShortcutCatalog.all.first { $0.id != id && shortcut($0.id).map { $0.keyCode == key.keyCode && $0.modifiers == key.modifiers } == true }
    }

    /// After settings sync replaced values underneath.
    func reload() {
        confirmQuit = defaults.object(forKey: Key.confirmQuit) as? Bool ?? true
        shortcuts = Self.loadShortcuts(from: defaults)
        clickThrough = defaults.object(forKey: Key.clickThrough) as? Bool ?? true
        hoverHint = defaults.object(forKey: Key.hoverHint) as? Bool ?? true
        edgeControls = defaults.object(forKey: Key.edgeControls) as? Bool ?? true
        edgeSide = defaults.string(forKey: Key.edgeSide).flatMap(EdgeSide.init(rawValue:)) ?? .automatic
        edgeLabels = defaults.object(forKey: Key.edgeLabels) as? Bool ?? true
        favorites = Self.loadFavorites(from: defaults)
        excludedApps = defaults.stringArray(forKey: Key.excludedApps) ?? []
        recentsLimit = defaults.object(forKey: Key.recentsLimit) as? Int ?? FolderHistory.defaultLimit
    }

    private static func loadFavorites(from defaults: UserDefaults) -> [Favorite] {
        guard let data = defaults.data(forKey: Key.favorites), !data.isEmpty,
              let list = try? JSONDecoder().decode([Favorite].self, from: data) else { return [] }
        return list
    }

    private static func loadShortcuts(from defaults: UserDefaults) -> [String: HotKey?] {
        guard let data = defaults.data(forKey: Key.shortcuts),
              let decoded = try? JSONDecoder().decode([String: HotKey?].self, from: data) else { return [:] }
        return decoded
    }
}
