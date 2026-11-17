import AppKit
import SwiftUI

// MARK: - Content

/// One page of Help. `Help.resolve` swaps `{…}` tokens for the user's own settings, such
/// as their shortcuts, so the text matches what they've set up.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let blocks: [HelpBlock]

    static func == (a: HelpTopic, b: HelpTopic) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
enum HelpBlock {
    case text(String)
    case heading(String)
    /// Keys on the left, what they do on the right.
    case keys([(String, String)])
    case tip(String)

    var searchText: String {
        switch self {
        case .text(let s), .heading(let s), .tip(let s): Help.resolve(s)
        case .keys(let rows): rows.map { Help.resolve($0.0) + " " + Help.resolve($0.1) }.joined(separator: " ")
        }
    }
}

@MainActor
enum Help {
    /// `{shortcut:<id>}` shows the user's own key for a shortcut in `ShortcutCatalog`
    /// (`{shortcut:recents}`).
    static func resolve(_ text: String) -> String {
        var result = text
        guard result.contains("{shortcut:") else { return result }
        while let open = result.range(of: "{shortcut:"), let close = result[open.upperBound...].firstIndex(of: "}") {
            let id = String(result[open.upperBound..<close])
            result.replaceSubrange(open.lowerBound...close, with: AppSettings.shared.shortcut(id)?.display ?? "(no shortcut set)")
        }
        return result
    }

    /// The page each Settings pane's ? button opens.
    static func topic(forSettingsTab tab: String) -> String {
        switch tab {
        case "Dialogs": "click-through"
        case "Folders": "folders"
        case "Shortcuts": "shortcuts"
        default: "settings"
        }
    }

    static var topicIDs: String { topics.map(\.id).joined(separator: ", ") }

    static var topics: [HelpTopic] { [
        HelpTopic(id: "getting-started", title: "Getting Started", symbol: "sparkles", blocks: [
            .text("JumpFolder makes every app's Open and Save dialogs quicker. While a dialog is in front, click any Finder window behind it and the dialog goes to that window's folder. Buttons above the dialog list your recent and favorite folders and Finder's open windows, and show the dialog's folder in Finder. A bar below it shows the dialog's folder path and a few folders to jump to."),
            .heading("Allow access"),
            .text("To see dialogs and the clicks around them, JumpFolder needs access. Turn on JumpFolder in System Settings › Privacy & Security › Device Control and Data Access. Until then the menu bar icon shows a warning sign and the menu's first item is \"Grant Access…\"."),
            .text("The first time JumpFolder asks Finder which folder a window shows, macOS asks whether JumpFolder may control Finder. Click Allow. You can change it later in Privacy & Security › Automation."),
            .tip("While ToolHUD is running, JumpFolder's menu moves into ToolHUD's menu bar menu as a submenu, and the icon here steps aside until ToolHUD quits. To keep the icon, turn off \"Put in ToolHUD's menu while ToolHUD is running\" in Settings › General."),
            .tip("Quitting asks first, since the dialog helpers and shortcuts stop working while JumpFolder is closed. Turn off \"Ask before quitting\" in Settings › General, or tick \"Don't ask again\" when it asks."),
        ]),

        HelpTopic(id: "click-through", title: "Clicking Finder Windows", symbol: "cursorarrow.click", blocks: [
            .text("With an Open or Save dialog in front, click a Finder window behind it. The dialog goes to that window's folder, and Finder stays behind, so you can keep going in the dialog."),
            .keys([
                ("Click a Finder window", "Take the dialog to that folder"),
                ("⌥-click a Finder window", "Bring Finder forward as usual"),
            ]),
            .text("When you point at a Finder window JumpFolder can use, it gets a colored outline and a “Jump to” label with its folder's name follows the pointer. Both go away when you click or move off the window. Turn highlighting off in Settings › Dialogs."),
            .heading("Hidden Finder windows (x-ray)"),
            .text("When the app with the dialog is full screen, or a Finder window is on another Space or under other windows, point where that window sits, outside the dialog. A dashed outline and a “Jump to” label appear; click there to take the dialog to its folder. Nothing shows until you point at one."),
            .text("Choose which hidden windows count in Settings › Dialogs › X-ray hidden Finder windows: behind full-screen apps, on other Spaces and displays, and behind other windows. All three are on at first."),
            .text("Clicks on the dialog itself, on other apps' windows and on the desktop work as usual, except where an x-ray outline is showing. Windows showing a search or Recents, which aren't folders, can't be used; you hear an alert sound instead."),
            .tip("Turn this off in Settings › Dialogs, or from the menu bar menu (Click Finder Windows to Jump)."),
        ]),

        HelpTopic(id: "edge", title: "Folder Buttons", symbol: "rectangle.topthird.inset.filled", blocks: [
            .text("While a dialog is open, JumpFolder puts buttons around it that move with it."),
            .heading("Above the dialog"),
            .keys([
                ("Recent", "Folders this app's dialogs used, then every app's"),
                ("Favorites", "Your favorite folders, plus Add to Favorites for the dialog's folder"),
                ("Finder", "The folder of every open Finder window"),
                ("Reveal", "Show the dialog's folder in Finder"),
            ]),
            .heading("Below the dialog"),
            .text("The dialog's folder path: click a folder in it to go up to it. Then a few folders to jump to, and a chevron for the rest. Choose Recently Used, Most Used or Favorites in Settings › Dialogs, and how many to show. Recently Used and Most Used are kept for each app, so Excel's folders differ from Word's. Until an app has a few folders of its own, other apps' recent folders fill in."),
            .text("In Per-App Settings, give an app its own choice, or have JumpFolder leave it alone. Prefer the older look? Choose Style › Strip on the side."),
        ]),

        HelpTopic(id: "folders", title: "Recent and Favorite Folders", symbol: "star", blocks: [
            .text("A folder becomes recent when a dialog closes in it, or when JumpFolder takes a dialog there. Each app's last folder is listed first in that app's dialogs. Settings › Folders sets how many to remember and clears them. Recent folders stay on this Mac."),
            .text("Favorites are folders you keep at hand. Add them in Settings › Folders or with Add to Favorites in the Favorites button above a dialog. Give one a shorter name, drag to reorder, or remove it. With settings sync on, favorites follow you to your other Macs."),
        ]),

        HelpTopic(id: "shortcuts", title: "Shortcuts", symbol: "keyboard", blocks: [
            .text("Each list above a dialog can have a keyboard shortcut. None is set at first: set them in Settings › Shortcuts. They work while an Open or Save dialog is in front."),
            .keys([
                ("{shortcut:recents}", "Show Recent Folders"),
                ("{shortcut:favorites}", "Show Favorite Folders"),
                ("{shortcut:finder-windows}", "Show Finder Windows"),
                ("{shortcut:reveal}", "Reveal Current Folder in Finder"),
            ]),
        ]),

        HelpTopic(id: "settings", title: "Settings and Updates", symbol: "gearshape", blocks: [
            .text("Settings › General has the appearance (System, Light or Dark), opening at login, asking before quitting, and whether JumpFolder shows in the Dock, the menu bar, both or neither. With neither, open JumpFolder again from Applications or Spotlight to get to Settings."),
            .heading("Sync"),
            .text("Turn on \"Sync settings with your other Macs\" to keep JumpFolder's settings, favorites, excluded apps and shortcuts the same on every Mac signed in to your iCloud account. They travel through your iCloud Drive. Recent folders stay on each Mac."),
            .heading("Updates"),
            .text("JumpFolder checks for new versions as often as you choose. It can install them automatically (only while no dialog is open), ask first, or never check."),
        ]),

        HelpTopic(id: "agents", title: "Command Line and AI Agents", symbol: "terminal", blocks: [
            .text("JumpFolder is also a command line tool, so scripts and AI agents such as Claude Code or Codex can read your recent and favorite folders, add favorites, take the dialog in front to a folder, and change settings. Commands run in the open app."),
            .keys([
                ("jumpfolder help", "List every command and its options"),
                ("jumpfolder status", "Whether access is on and which dialog is in front"),
                ("jumpfolder go ~/Documents", "Take the dialog in front to a folder"),
                ("jumpfolder favorites add ~/Projects", "Add a favorite folder"),
                ("jumpfolder mcp", "Offer the same commands to MCP apps, such as Claude Desktop"),
            ]),
            .text("To type jumpfolder in Terminal, link it once: ln -s /Applications/JumpFolder.app/Contents/MacOS/JumpFolder ~/.local/bin/jumpfolder (with ~/.local/bin on your PATH)."),
        ]),

        HelpTopic(id: "troubleshooting", title: "Troubleshooting", symbol: "wrench.and.screwdriver", blocks: [
            .heading("No buttons appear around dialogs"),
            .text("JumpFolder needs access. Choose \"Grant Access…\" in the menu bar menu. Also check that \"Show folder buttons around dialogs\" is on in Settings › Dialogs, and that the app isn't set to be left alone in Per-App Settings. If JumpFolder is on in Device Control and Data Access but nothing happens, remove it from the list and add it again, then quit and reopen JumpFolder."),
            .heading("Clicking a Finder window doesn't move the dialog"),
            .text("Check that JumpFolder may control Finder in Privacy & Security › Automation. Another dialog helper that also takes clicks on Finder windows can get them first; turn its click-through off."),
            .heading("The dialog shows the Go to Folder sheet briefly"),
            .text("JumpFolder usually moves the dialog by opening folders in its list, starting from a nearby place such as your home folder. Folders the list doesn't show, like hidden ones, or a Save dialog shown without its file list, need Go to Folder (⇧⌘G) instead: JumpFolder types the path and presses Return, just as you would."),
        ]),
    ] }
}

// MARK: - Window

@Observable
@MainActor
final class HelpState {
    var selection: String? = "getting-started"
    var query = ""
}

@MainActor
final class HelpWindow: NSObject, NSWindowDelegate {
    static let shared = HelpWindow()

    let state = HelpState()
    private(set) var window: NSWindow?

    /// Opens Help, on `topic` when given.
    func show(topic: String? = nil) {
        if let topic { state.query = ""; state.selection = topic }
        if window == nil {
            let hosting = NSHostingController(rootView: HelpView(state: state))
            hosting.sizingOptions = []
            let window = NSWindow(contentViewController: hosting)
            window.title = "\(AppInfo.name) Help"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            let screen = NSScreen.main?.visibleFrame.height ?? 800
            window.setContentSize(NSSize(width: 820, height: min(600, screen - 80)))
            window.contentMinSize = NSSize(width: 640, height: 400)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("JumpFolderHelp")
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HelpView: View {
    @Bindable var state: HelpState

    private var matches: [HelpTopic] {
        let query = state.query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return Help.topics }
        return Help.topics.filter { topic in
            topic.title.lowercased().contains(query) || topic.blocks.contains { $0.searchText.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(matches, selection: $state.selection) { topic in
                Label(topic.title, systemImage: topic.symbol).tag(topic.id)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .overlay {
                if matches.isEmpty { Text("No matches").foregroundStyle(.secondary) }
            }
        } detail: {
            if let topic = Help.topics.first(where: { $0.id == state.selection }) {
                HelpPage(topic: topic, query: state.query)
            } else {
                Text("Choose a topic").foregroundStyle(.secondary)
            }
        }
        .searchable(text: $state.query, placement: .sidebar, prompt: "Search Help")
        .onChange(of: state.query) {
            // Keep a matching topic on screen while searching.
            if let first = matches.first, !matches.contains(where: { $0.id == state.selection }) { state.selection = first.id }
        }
    }
}

struct HelpPage: View {
    let topic: HelpTopic
    let query: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(topic.title, systemImage: topic.symbol)
                    .font(.largeTitle.weight(.semibold))
                    .padding(.bottom, 4)
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func view(for block: HelpBlock) -> some View {
        switch block {
        case .text(let s):
            Text(Help.resolve(s)).fixedSize(horizontal: false, vertical: true)
        case .heading(let s):
            Text(Help.resolve(s)).font(.title3.weight(.semibold)).padding(.top, 8)
        case .tip(let s):
            Label { Text(Help.resolve(s)).fixedSize(horizontal: false, vertical: true) } icon: {
                Image(systemName: "lightbulb").foregroundStyle(.yellow)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        case .keys(let rows):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let keys = Help.resolve(row.0), what = Help.resolve(row.1)
                    let hit = !query.isEmpty && (keys + " " + what).lowercased().contains(query.lowercased())
                    GridRow {
                        Text(keys)
                            .font(.body.monospaced().weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                            // The same key column width in every table on every page.
                            .frame(width: 210, alignment: .leading)
                        Text(what).fixedSize(horizontal: false, vertical: true)
                    }
                    .background(hit ? Color.yellow.opacity(0.25) : .clear)
                }
            }
        }
    }
}

/// The round "?" button macOS puts in the corner of settings panes.
struct HelpButton: NSViewRepresentable {
    let topic: String

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open))
        button.bezelStyle = .helpButton
        button.toolTip = "\(AppInfo.name) Help"
        button.setAccessibilityLabel("Help")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.topic = topic }

    func makeCoordinator() -> Coordinator { Coordinator(topic: topic) }

    @MainActor
    final class Coordinator: NSObject {
        var topic: String
        init(topic: String) { self.topic = topic }
        @objc func open() { HelpWindow.shared.show(topic: topic) }
    }
}
