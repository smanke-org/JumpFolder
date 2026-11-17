import Foundation

/// How to take a dialog to a folder without its "Go to" sheet: start where it is, a few
/// folders up (⌘↑), or at a place the dialog has a shortcut for, then open one folder row
/// after another. Fewer visible steps wins.
public enum FolderRoute {
    /// Places Open and Save dialogs go to with a key: Home ⇧⌘H, Desktop ⇧⌘D, Documents ⇧⌘O,
    /// Downloads ⌥⌘L, Applications ⇧⌘A, Computer ⇧⌘C.
    public enum Place: String, CaseIterable, Sendable {
        case home, desktop, documents, downloads, applications, computer

        /// The folder it shows; Computer lists volumes, so it has none.
        public func path(home: String) -> String? {
            switch self {
            case .home: home
            case .desktop: home + "/Desktop"
            case .documents: home + "/Documents"
            case .downloads: home + "/Downloads"
            case .applications: "/Applications"
            case .computer: nil
            }
        }
    }

    public enum Start: Equatable, Sendable {
        case here
        case up(Int)
        case place(Place)
        /// A folder in the dialog's sidebar (a favorite, or a cloud drive under Locations),
        /// opened by clicking it there.
        case sidebar(String)
    }

    public struct Plan: Equatable, Sendable {
        public let start: Start
        /// Full paths of the folders to open, in order; the last is the target.
        public let opens: [String]

        public init(start: Start, opens: [String]) {
            self.start = start
            self.opens = opens
        }

        /// Folder changes the person sees.
        public var steps: Int {
            switch start {
            case .here: opens.count
            case .up(let count): count + opens.count
            case .place, .sidebar: 1 + opens.count
            }
        }
    }

    /// The route with the fewest steps, or nil when there is none (a hidden folder on the way,
    /// which dialogs don't list). `volume` is the root of the disk holding `target`, which
    /// Computer lists as a row.
    /// `real` turns a path into the one the dialog's rows carry (symlinks resolved: a Desktop
    /// kept in a cloud folder lists that folder's path).
    /// `sidebar` are the folders the dialog's sidebar can open with one click. `hidden` says
    /// which folders the list leaves out (~/Library, /private…): routes through them are dropped.
    public static func plan(to target: String, from current: String?, home: String,
                            volume: String = "/", maxUps: Int = 2, sidebar: [String] = [],
                            real: @escaping (String) -> String = { $0 },
                            hidden: (String) -> Bool = { _ in false }) -> Plan? {
        let clean = { (path: String) in Self.clean(real(Self.clean(path))) }
        let target = clean(target)
        var plans: [Plan] = []
        if let current = current.map(clean) {
            var base = current
            for ups in 0...maxUps {
                if let opens = opens(from: base, to: target) {
                    plans.append(Plan(start: ups == 0 ? .here : .up(ups), opens: opens))
                }
                guard base != "/" else { break }
                base = parent(base)
            }
        }
        for place in Place.allCases {
            if let path = place.path(home: home) {
                if let opens = opens(from: clean(path), to: target) { plans.append(Plan(start: .place(place), opens: opens)) }
            } else if let below = opens(from: clean(volume), to: target) {
                plans.append(Plan(start: .place(.computer), opens: [clean(volume)] + below))
            }
        }
        for path in sidebar {
            if let opens = opens(from: clean(path), to: target) { plans.append(Plan(start: .sidebar(path), opens: opens)) }
        }
        plans.removeAll { $0.opens.contains(where: hidden) }
        // Stable: the first of equal plans wins, so "here" beats "up" beats a place.
        return plans.enumerated().min { a, b in
            (a.element.steps, a.offset) < (b.element.steps, b.offset)
        }?.element
    }

    /// The folders to open, one level at a time, to get from `base` down to `target`; empty
    /// when they are the same; nil when `target` isn't inside `base` or a step is hidden.
    public static func opens(from base: String, to target: String) -> [String]? {
        if base == target { return [] }
        let prefix = base == "/" ? "/" : base + "/"
        guard target.hasPrefix(prefix) else { return nil }
        let parts = target.dropFirst(prefix.count).split(separator: "/").map(String.init)
        guard !parts.contains(where: { $0.hasPrefix(".") }) else { return nil }
        var path = base == "/" ? "" : base
        return parts.map { part in
            path += "/" + part
            return path
        }
    }

    private static func clean(_ path: String) -> String {
        var path = path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path.isEmpty ? "/" : path
    }

    private static func parent(_ path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }
}
