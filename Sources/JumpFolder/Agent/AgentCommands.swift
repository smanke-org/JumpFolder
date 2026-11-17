import AppKit
import JumpFolderKit

/// Everything an agent can do in JumpFolder. Add a command here and the CLI, `help`, and the MCP
/// tools all get it. Each `run` is on the main actor and calls the same code as the menu bar
/// menu, the folder buttons, Settings and the jumpfolder:// links.
enum AgentCommands {
    static let all: [AgentCommand] = [
        AgentCommand(name: "status", summary: "Show the version, whether JumpFolder may see dialogs (`accessAllowed`), whether the click tap runs, and the Open or Save dialog in front (`dialog`: app, kind, folder, frame), if any.",
                     example: "jumpfolder status --json", readOnly: true) { _ in
            let watcher = DialogWatcher.shared
            return ["app": AppInfo.name, "version": AppInfo.version, "accessAllowed": AX.isTrusted,
                    "clickTapRunning": ClickThrough.shared.isRunning,
                    "dialog": watcher.dialog.map { dialog -> JSONObject in
                        ["app": dialog.appName, "bundleID": dialog.bundleID ?? NSNull(), "kind": dialog.kind.rawValue,
                         "folder": watcher.currentFolder ?? NSNull(), "folderTitle": watcher.folderTitle ?? NSNull(),
                         "frame": watcher.frame.map(rectJSON) ?? NSNull()]
                    } ?? NSNull()]
        },
        AgentCommand(name: "go", summary: "Take the Open or Save dialog in front to a folder, the way picking it beside the dialog does. Fails with `not_found` when no dialog is in front; the folder must exist.",
                     params: [.init(name: "path", kind: .path, required: true, positional: true, help: "the folder")],
                     example: "jumpfolder go ~/Documents --json") { args in
            guard AX.isTrusted else { throw AgentError.noAccess }
            let path = FolderPath.normalized(try args.required("path"))
            guard FolderMenus.exists(path) else { throw AgentError.notFound("no folder at \(path)") }
            guard DialogWatcher.shared.dialog != nil else {
                throw AgentError.notFound("no Open or Save dialog is in front. The person must open one first; running this in Terminal puts Terminal in front.")
            }
            DialogNavigator.go(to: path)
            return ["path": path, "started": true]
        },

        // MARK: Folders

        AgentCommand(name: "recents list", summary: "List the recent folders, newest first, and each app's last folder. Returns `recents` (path, date), `lastByApp` (bundle id → path) and `limit`.",
                     example: "jumpfolder recents list --json", readOnly: true) { _ in
            let settings = AppSettings.shared
            return ["recents": settings.history.entries.map { ["path": $0.path, "date": JSON.date($0.date)] as JSONObject },
                    "lastByApp": settings.history.lastByApp, "limit": settings.recentsLimit]
        },
        AgentCommand(name: "recents clear", summary: "Forget every recent folder and each app's last folder, as Settings › Folders does. Without --yes it only says how many it would forget.",
                     example: "jumpfolder recents clear --yes --json", destructive: true) { args in
            let count = AppSettings.shared.history.entries.count
            guard args.confirmed else { return ["wouldClear": count, "cleared": false] }
            AppSettings.shared.history.clear()
            return ["cleared": true, "count": count]
        },
        AgentCommand(name: "favorites list", summary: "List the favorite folders in menu order. Returns `favorites` (index, path, name, exists).",
                     example: "jumpfolder favorites list --json", readOnly: true) { _ in
            ["favorites": AppSettings.shared.favorites.enumerated().map { index, favorite -> JSONObject in
                ["index": index + 1, "path": favorite.path, "name": favorite.displayName, "exists": FolderMenus.exists(favorite.path)]
            }]
        },
        AgentCommand(name: "favorites add", summary: "Add a folder to the end of the favorites. Already there: nothing changes.",
                     params: [.init(name: "path", kind: .path, required: true, positional: true, help: "the folder"),
                              .init(name: "name", help: "a shorter name for the menu (default: the folder's own)")],
                     example: "jumpfolder favorites add ~/Projects --name Work --json") { args in
            let path = FolderPath.normalized(try args.required("path"))
            guard FolderMenus.exists(path) else { throw AgentError.notFound("no folder at \(path)") }
            let settings = AppSettings.shared
            let added = Favorites.add(path, to: &settings.favorites)
            if added, let name = args.string("name"), let index = settings.favorites.firstIndex(where: { $0.path == path }) {
                settings.favorites[index].name = name
            }
            return ["path": path, "added": added, "total": settings.favorites.count]
        },
        AgentCommand(name: "favorites remove", summary: "Remove a favorite folder (by path or 1-based index). Without --yes it only says which it would remove.",
                     params: [.init(name: "favorite", required: true, positional: true, help: "the folder's path, or its index in `favorites list`")],
                     example: "jumpfolder favorites remove 2 --yes --json", destructive: true) { args in
            let settings = AppSettings.shared
            let key = try args.required("favorite")
            let index: Int?
            if let number = Int(key) {
                index = settings.favorites.indices.contains(number - 1) ? number - 1 : nil
            } else {
                let path = FolderPath.normalized(key)
                index = settings.favorites.firstIndex { $0.path == path }
            }
            guard let index else { throw AgentError.notFound("no favorite \"\(key)\". See `jumpfolder favorites list`") }
            let favorite = settings.favorites[index]
            guard args.confirmed else { return ["wouldRemove": favorite.path, "removed": false] }
            settings.favorites.remove(at: index)
            return ["removed": true, "path": favorite.path]
        },

        // MARK: Settings

        AgentCommand(name: "settings show", summary: "Show JumpFolder's settings: clicking Finder windows behind dialogs, the folder buttons, their side and labels, apps left alone, how many recent folders to keep, Ask before quitting, the Dock and menu bar icons, and every global shortcut.",
                     example: "jumpfolder settings show --json", readOnly: true) { _ in
            settingsJSON()
        },
        AgentCommand(name: "settings set", summary: "Change JumpFolder's settings. Only the options you give change.",
                     params: [.init(name: "click-through", kind: .boolean, help: "true or false: clicking a Finder window takes the dialog there"),
                              .init(name: "hover-hint", kind: .boolean, help: "true or false: outline and label the Finder window under the pointer"),
                              .init(name: "xray-fullscreen", kind: .boolean, help: "true or false: x-ray Finder windows behind a full-screen app"),
                              .init(name: "xray-spaces", kind: .boolean, help: "true or false: x-ray Finder windows on other Spaces and displays"),
                              .init(name: "xray-covered", kind: .boolean, help: "true or false: x-ray Finder windows covered by other windows"),
                              .init(name: "edge-controls", kind: .boolean, help: "true or false: folder buttons beside dialogs"),
                              .init(name: "style", help: "bars or strip: pills above and a bar below the dialog, or a strip on its side"),
                              .init(name: "bottom-bar", kind: .boolean, help: "true or false: the bar below the dialog"),
                              .init(name: "bottom-source", help: "recent, mostUsed or favorites: the folders in the bar below"),
                              .init(name: "bottom-count", kind: .integer, help: "how many folders the bar below shows, 3–5"),
                              .init(name: "breadcrumb", kind: .boolean, help: "true or false: the folder path in the bar below"),
                              .init(name: "edge-side", help: EdgeSide.allCases.map(\.rawValue).joined(separator: ", ")),
                              .init(name: "edge-labels", kind: .boolean, help: "true or false: names under the folder buttons"),
                              .init(name: "recents-limit", kind: .integer, help: "how many recent folders to keep, \(FolderHistory.limitRange.lowerBound)–\(FolderHistory.limitRange.upperBound)"),
                              .init(name: "ask-before-quitting", kind: .boolean, help: "true or false"),
                              .init(name: "show-in-dock", kind: .boolean, help: "true or false"),
                              .init(name: "show-in-menu-bar", kind: .boolean, help: "true or false")],
                     example: "jumpfolder settings set --edge-side right --json") { args in
            let settings = AppSettings.shared
            let click = try args.bool("click-through"), edge = try args.bool("edge-controls"), labels = try args.bool("edge-labels"), hint = try args.bool("hover-hint")
            let xrayFull = try args.bool("xray-fullscreen"), xraySpaces = try args.bool("xray-spaces"), xrayCovered = try args.bool("xray-covered")
            let quit = try args.bool("ask-before-quitting"), dock = try args.bool("show-in-dock"), menuBar = try args.bool("show-in-menu-bar")
            let bottomBar = try args.bool("bottom-bar"), breadcrumb = try args.bool("breadcrumb")
            var style: ControlStyle?
            if let name = args.string("style") {
                guard let value = ControlStyle(rawValue: name.lowercased()) else { throw AgentError.usage("--style must be bars or strip") }
                style = value
            }
            var source: BarSource?
            if let name = args.string("bottom-source") {
                guard let value = BarSource(rawValue: name) else { throw AgentError.usage("--bottom-source must be recent, mostUsed or favorites") }
                source = value
            }
            var count: Int?
            if args.string("bottom-count") != nil {
                let value = try args.int("bottom-count", default: settings.bottomCount)
                guard AppSettings.bottomCountRange.contains(value) else { throw AgentError.usage("--bottom-count must be 3–5") }
                count = value
            }
            var side: EdgeSide?
            if let name = args.string("edge-side") {
                guard let value = EdgeSide(rawValue: name.lowercased()) else {
                    throw AgentError.usage("--edge-side must be one of \(EdgeSide.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                side = value
            }
            var limit: Int?
            if args.string("recents-limit") != nil {
                let value = try args.int("recents-limit", default: settings.recentsLimit)
                guard FolderHistory.limitRange.contains(value) else {
                    throw AgentError.usage("--recents-limit must be \(FolderHistory.limitRange.lowerBound)–\(FolderHistory.limitRange.upperBound)")
                }
                limit = value
            }
            guard style != nil || bottomBar != nil || breadcrumb != nil || source != nil || count != nil || click != nil || hint != nil || xrayFull != nil || xraySpaces != nil || xrayCovered != nil || edge != nil || labels != nil || side != nil || limit != nil || quit != nil || dock != nil || menuBar != nil else {
                throw AgentError.usage("give at least one option; see `jumpfolder help settings set`")
            }
            if let click { settings.clickThrough = click }
            if let hint { settings.hoverHint = hint }
            if let xrayFull { settings.xrayFullScreen = xrayFull }
            if let xraySpaces { settings.xraySpaces = xraySpaces }
            if let xrayCovered { settings.xrayCovered = xrayCovered }
            if let style { settings.controlStyle = style }
            if let bottomBar { settings.bottomBar = bottomBar }
            if let breadcrumb { settings.breadcrumb = breadcrumb }
            if let source { settings.bottomSource = source }
            if let count { settings.bottomCount = count }
            if let edge { settings.edgeControls = edge }
            if let side { settings.edgeSide = side }
            if let labels { settings.edgeLabels = labels }
            if let limit { settings.recentsLimit = limit }
            if let quit { settings.confirmQuit = quit }
            if let dock { settings.showInDock = dock }
            if let menuBar { settings.showInMenuBar = menuBar }
            DialogWatcher.shared.settingsChanged()
            var result = settingsJSON()
            if !settings.showInDock && !settings.showInMenuBar {
                result["note"] = AppPresence.hiddenEverywhereNote(appName: "JumpFolder", settingsName: "Settings")
            }
            return result
        },
        AgentCommand(name: "open", summary: "Bring up a JumpFolder window: Settings on one of its panes, or Help on a topic.",
                     params: [.init(name: "page", required: true, positional: true,
                                    help: "settings, general, dialogs, folders, shortcuts or help"),
                              .init(name: "topic", help: "with help: a topic, like getting-started, click-through, edge, folders, shortcuts, settings, agents or troubleshooting")],
                     example: "jumpfolder open folders --json") { args in
            let page = try args.required("page").lowercased()
            let tabs = ["settings": "General", "general": "General", "dialogs": "Dialogs", "folders": "Folders", "shortcuts": "Shortcuts"]
            if page == "help" {
                let topic = args.string("topic")
                if let topic, !Help.topics.contains(where: { $0.id == topic }) {
                    throw AgentError.notFound("no Help topic \"\(topic)\". Topics: \(Help.topics.map(\.id).joined(separator: ", "))")
                }
                HelpWindow.shared.show(topic: topic)
                return ["open": "help", "topic": topic.map { $0 as Any } ?? NSNull()]
            }
            guard let tab = tabs[page] else {
                throw AgentError.notFound("no page \"\(page)\". Pages: settings, general, dialogs, folders, shortcuts, help")
            }
            SettingsWindow.shared.show(tab: tab)
            return ["open": "settings", "pane": tab]
        },
    ]

    @MainActor
    private static func settingsJSON() -> JSONObject {
        let settings = AppSettings.shared
        return ["clickThrough": settings.clickThrough, "hoverHint": settings.hoverHint,
                "xrayFullScreen": settings.xrayFullScreen, "xraySpaces": settings.xraySpaces, "xrayCovered": settings.xrayCovered, "edgeControls": settings.edgeControls, "edgeSide": settings.edgeSide.rawValue,
                "edgeLabels": settings.edgeLabels,
                "style": settings.controlStyle.rawValue, "bottomBar": settings.bottomBar, "bottomSource": settings.bottomSource.rawValue,
                "bottomCount": settings.bottomCount, "breadcrumb": settings.breadcrumb, "appSources": settings.appSources,
                "excludedApps": settings.excludedApps, "recentsLimit": settings.recentsLimit,
                "askBeforeQuitting": settings.confirmQuit, "showInDock": settings.showInDock, "showInMenuBar": settings.showInMenuBar,
                "shortcuts": ShortcutCatalog.all.map { item -> JSONObject in
                    ["id": item.id, "title": item.title, "key": settings.shortcut(item.id)?.display ?? ""]
                }]
    }

    private static func rectJSON(_ rect: CGRect) -> JSONObject {
        ["x": Int(rect.minX), "y": Int(rect.minY), "width": Int(rect.width), "height": Int(rect.height)]
    }
}
