import ApplicationServices
import CoreServices
import Foundation

/// The folders an Open or Save dialog's sidebar opens with one click, so DialogNavigator can
/// start there. Sidebar rows carry only a name, so names are matched to paths: Finder's
/// sidebar favorites by their display name, and cloud drives under Locations by provider
/// ("OneDrive" for ~/Library/CloudStorage/OneDrive-Personal). A name that appears twice is
/// skipped rather than guessed.
struct SidebarPlace {
    let name: String
    let path: String
    let cell: AXUIElement
}

enum SidebarPlaces {
    static func read(in dialog: AXUIElement) -> [SidebarPlace] {
        guard let outline = findOutline(dialog, depth: 0) else { return [] }
        var cells: [(String, AXUIElement)] = []
        for row in (AX.value(outline, kAXRowsAttribute) as? [AXUIElement] ?? []) {
            for cell in AX.children(row) {
                for text in AX.children(cell) where AX.role(text) == kAXStaticTextRole {
                    // Section headers ("Favorites", "Locations") are text too, but have an identifier.
                    if let name = AX.string(text, kAXValueAttribute), !name.isEmpty,
                       (AX.string(text, kAXIdentifierAttribute) ?? "").isEmpty {
                        cells.append((name, cell))
                    }
                }
            }
        }
        let counts = Dictionary(cells.map { ($0.0, 1) }, uniquingKeysWith: +)
        let paths = knownPaths()
        return cells.compactMap { name, cell in
            guard counts[name] == 1, let path = paths[key(name)] else { return nil }
            return SidebarPlace(name: name, path: path, cell: cell)
        }
    }

    /// Loose name ("googledrive" for "Google Drive") → folder, leaving out names that map to two folders.
    private static func knownPaths() -> [String: String] {
        var found: [(String, String)] = favorites()
        let home = NSHomeDirectory()
        let cloud = home + "/Library/CloudStorage"
        for dir in (try? FileManager.default.contentsOfDirectory(atPath: cloud)) ?? [] {
            let provider = dir.split(separator: "-", maxSplits: 1).first.map(String.init) ?? dir
            found.append((provider, cloud + "/" + dir))
        }
        found.append(("iCloud Drive", home + "/Library/Mobile Documents/com~apple~CloudDocs"))
        var byKey: [String: String] = [:]
        var clashes: Set<String> = []
        for (name, path) in found {
            let key = Self.key(name)
            if let other = byKey[key], other != path { clashes.insert(key) }
            byKey[key] = path
        }
        return byKey.filter { !clashes.contains($0.key) }
    }

    private static func key(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "").lowercased()
    }

    /// Finder's sidebar favorites, which Open and Save dialogs share.
    private static func favorites() -> [(String, String)] {
        guard let list = LSSharedFileListCreate(nil, "com.apple.LSSharedFileList.FavoriteItems" as CFString, nil)?
            .takeRetainedValue() else { return [] }
        var seed: UInt32 = 0
        guard let items = LSSharedFileListCopySnapshot(list, &seed)?.takeRetainedValue() as? [LSSharedFileListItem] else { return [] }
        return items.compactMap { item in
            guard let url = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL? else { return nil }
            let name = LSSharedFileListItemCopyDisplayName(item).takeRetainedValue() as String
            return (name, url.path)
        }
    }

    private static func findOutline(_ element: AXUIElement, depth: Int) -> AXUIElement? {
        if AX.role(element) == kAXOutlineRole, AX.string(element, kAXDescriptionAttribute) == "sidebar" { return element }
        guard depth < 14 else { return nil }
        for child in AX.children(element) {
            if let found = findOutline(child, depth: depth + 1) { return found }
        }
        return nil
    }
}
