import AppKit
import Combine
import JumpFolderKit

/// Quits JumpFolder without asking: for quitting itself (installing an update, ending a test).
@MainActor
enum QuitConfirmation {
    private(set) static var confirmed = false

    static func quitNow() {
        confirmed = true
        NSApp.terminate(nil)
    }
}

/// Owns the long-lived objects and starts them at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let launchAtLogin = LaunchAtLogin()
    private var statusItem: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything saves a setting: an empty domain means a brand-new install.
        let newInstall = SettingsSync.domainIsEmpty()
        Diagnostics.note("launch \(AppInfo.displayVersion) from \(Bundle.main.bundlePath)")
        AppAppearance.start()
        SettingsWindow.shared.launchAtLogin = launchAtLogin
        #if DEBUG
        // A test run of the agent CLI (APP_STORE): its own settings and log and the agent
        // socket. Nothing else starts: no menu bar item, dialog watching, click tap,
        // shortcuts, settings sync, updater or login item, and no Accessibility prompt.
        if AgentSocket.isTestRun {
            AgentSocket.listen { AgentRouter.handle($0) }
            if ProcessInfo.processInfo.environment["JUMPFOLDER_DEBUG_SHORTCUTS"] == "1" {
                HotKeyCenter.shared.apply()
                startShortcutsLensReport()
            }
            return
        }
        #endif
        statusItem = StatusItemController()
        let mainMenu = AppPresence.mainMenu(appName: "JumpFolder", settingsTitle: "Settings…",
                                            target: self, settings: #selector(showSettings))
        // Right below About in the app menu.
        let otherApps = NSMenuItem(title: "Our other apps…", action: #selector(showOtherApps), keyEquivalent: "")
        otherApps.target = self
        mainMenu.items.first?.submenu?.insertItem(otherApps, at: 1)
        // Help menu, with the standard ⌘? (macOS adds its search field).
        let helpItem = NSMenuItem()
        let help = NSMenu(title: "Help")
        let helpOpen = NSMenuItem(title: "JumpFolder Help", action: #selector(showHelp), keyEquivalent: "?")
        helpOpen.target = self
        help.addItem(helpOpen)
        helpItem.submenu = help
        mainMenu.addItem(helpItem)
        NSApp.helpMenu = help
        NSApp.mainMenu = mainMenu
        #if DEBUG
        // Renders pages to PNGs and quits; starts no dialog watching, tap or updates.
        Snapshot.menu = { [statusItem] in statusItem!.freshMenu() }
        if Snapshot.runIfAsked() { return }
        #endif

        // `jumpfolder` and the MCP server talk to the app through this.
        AgentSocket.listen { AgentRouter.handle($0) }
        listenForDebugCommands()
        EdgePanel.shared.start()
        DialogWatcher.shared.start()
        if AX.isTrusted { ClickThrough.shared.start() }
        HotKeyCenter.shared.perform = { id in Self.perform(shortcut: id) }
        HotKeyCenter.shared.apply()
        startShortcutsLensReport()
        WelcomeWindow.shared.onGranted = { [weak self] in
            self?.statusItem.updateIcon()
            // The tap needs the access just granted; asking about Finder now keeps that
            // question next to this one instead of in the middle of a dialog.
            ClickThrough.shared.start()
            FinderWindows.requestAccess()
        }
        launchAtLogin.enableOnFirstRun()
        // An automatic update must not restart JumpFolder while it is taking a dialog somewhere.
        AutoUpdater.shared.appBusyReason = { DialogWatcher.shared.dialog != nil ? "an Open or Save dialog is open" : nil }
        SettingsSync.shared.onApply = {
            AppSettings.shared.reload()
            HotKeyCenter.shared.apply()
            MenuHub.shared.reload()
            DialogWatcher.shared.settingsChanged()
        }
        if newInstall { SettingsSync.shared.adoptOnNewInstall() }
        SettingsSync.shared.start()
        AutoUpdater.shared.start(newInstall: newInstall)

        if !AX.isTrusted {
            // First run: say why nothing will happen yet. Opened at launch, which is a
            // deliberate act by the user, never from a background timer.
            WelcomeWindow.shared.show()
        }
    }

    /// A global shortcut fired.
    static func perform(shortcut id: String) {
        switch id {
        case "recents": EdgePanel.shared.open(.recents)
        case "favorites": EdgePanel.shared.open(.favorites)
        case "finder-windows": EdgePanel.shared.open(.finderWindows)
        case "reveal": EdgePanel.shared.open(.reveal)
        default: break
        }
    }

    /// ShortcutsLens lists the shortcuts and can give them new keys (its Change Shortcut).
    private func startShortcutsLensReport() {
        ShortcutsLensReport.start({ HotKeyCenter.shared.reportedShortcuts }, change: { id, keyCode, modifiers in
            HotKeyCenter.shared.change(id: id, keyCode: keyCode, carbonModifiers: modifiers)
        })
    }

    /// Quitting asks first while "Ask before quitting" is on — not when macOS is logging out,
    /// restarting or shutting down, and not when JumpFolder quits itself to install an update.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let systemQuit = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil
        guard AppSettings.shared.confirmQuit, !QuitConfirmation.confirmed, !systemQuit else { return .terminateNow }

        // A menu bar app needs to be a regular one for the alert to come to the front; the
        // old policy goes back a runloop turn later, once the alert is gone.
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        defer { DispatchQueue.main.async { NSApp.setActivationPolicy(previousPolicy) } }

        let alert = NSAlert()
        alert.messageText = "Quit JumpFolder?"
        alert.informativeText = "Open and Save dialogs lose their folder buttons, clicking Finder windows behind them stops working, and JumpFolder's shortcuts stop until you open JumpFolder again."
        // Quit has no key, so Return does nothing: quitting takes a click, never a stray keystroke.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit").keyEquivalent = ""
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        alert.layout()
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeKeyAndOrderFront(nil)

        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        if alert.suppressionButton?.state == .on { AppSettings.shared.confirmQuit = false }
        return .terminateNow
    }

    /// The Dock icon's right-click menu, when "Show in Dock" is on.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        AppPresence.dockMenu(title: "Settings…", target: self, action: #selector(showSettings))
    }

    /// Clicking the Dock icon, or opening the app again from Applications or Spotlight,
    /// opens Settings — the way back when both icons are hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    /// `jumpfolder://` URLs (from ToolHUD, Shortcuts or a script): `recents`, `favorites`,
    /// `finder-windows`, `reveal` (act on the dialog in front), `go?path=/some/folder` (takes
    /// the dialog there, or opens the folder in Finder with no dialog) and `settings`.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "jumpfolder" {
            let action = url.host() ?? url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            switch action {
            case "recents", "favorites", "finder-windows", "reveal": Self.perform(shortcut: action)
            case "go":
                let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "path" }?.value
                if let path { FolderMenus.open(path) } else { Diagnostics.note("url: go without path") }
            case "settings": showSettings()
            default: Diagnostics.note("url: unknown action \(action)")
            }
        }
    }

    @objc func showSettings() {
        SettingsWindow.shared.show()
    }

    @objc func showHelp() { HelpWindow.shared.show() }

    /// The app menu's About item (`AppPresence.mainMenu`).
    @objc func showAbout() { AppInfo.showAbout() }

    /// The developer's site, which lists every app.
    @objc func showOtherApps() {
        if let url = URL(string: "https://stevemanke.com/") { NSWorkspace.shared.open(url) }
    }

    /// Development affordance, only with JUMPFOLDER_DEBUG=1. A distributed notification
    /// `com.smanke.JumpFolder.debug` whose object is a command runs it in the installed,
    /// permission-holding build; results go to ~/Library/Logs/JumpFolder.log. Commands:
    /// `dump:menu`, `dump:dialog` (the frontmost app's windows as Accessibility shows them),
    /// `dump:edge`, `dump:finder`, `go:<path>`, `click:<x>,<y>` (as if that point of a Finder
    /// window were clicked), `show:settings|help|about|<tab>`, `help:<topic>`, `sync:on|off`.
    private func listenForDebugCommands() {
        guard Diagnostics.isEnabled else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.smanke.JumpFolder.debug"), object: nil, queue: .main
        ) { note in
            let command = note.object as? String ?? ""
            MainActor.assumeIsolated { [weak self] in self?.runDebugCommand(command) }
        }
        Diagnostics.note("debug commands on")
    }

    private func runDebugCommand(_ command: String) {
        let parts = command.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return Diagnostics.note("debug: bad command \(command)") }
        switch (parts[0], parts[1]) {
        case ("dump", "menu"): Diagnostics.note("debug: menu\n" + statusItem.dumpMenu())
        case ("dump", "dialog"): Diagnostics.note("debug: dialog\n" + DialogWatcher.shared.dump())
        case ("dump", "edge"):
            Diagnostics.note("debug: edge visible=\(EdgePanel.shared.isVisible) frame=\(EdgePanel.shared.debugFrame.map { "\($0)" } ?? "-") "
                             + "dialog=\(DialogWatcher.shared.frame.map { "\($0)" } ?? "-") tap=\(ClickThrough.shared.isRunning)")
        case ("dump", "finder"):
            FinderWindows.list { windows, error in
                Diagnostics.note("debug: finder \(error ?? "")\n" + windows.map { "\($0.path) \($0.bounds)" }.joined(separator: "\n"))
            }
        case ("go", let path): DialogNavigator.go(to: path)
        case ("click", let point):
            let numbers = point.split(separator: ",").compactMap { Double($0) }
            guard numbers.count == 2 else { return Diagnostics.note("debug: click needs x,y") }
            let hit = ClickTarget.hit(CGPoint(x: numbers[0], y: numbers[1]), in: ClickThrough.windowList())
            Diagnostics.note("debug: click hits \(hit.map { "\($0.ownerName) \($0.bounds)" } ?? "nothing")")
            if let hit, hit.ownerName == "Finder" { ClickThrough.jump(toFinderWindowAt: hit.bounds) }
        case ("show", "settings"): SettingsWindow.shared.show()
        case ("show", "help"): HelpWindow.shared.show()
        case ("show", "about"): AppInfo.showAbout()
        case ("help", let topic): HelpWindow.shared.show(topic: topic)
        case ("show", let tab): SettingsWindow.shared.show(tab: tab)
        case ("sync", "on"): SettingsSync.shared.isEnabled = true
        case ("sync", "off"): SettingsSync.shared.isEnabled = false
        default: Diagnostics.note("debug: unknown command \(command)")
        }
    }
}
