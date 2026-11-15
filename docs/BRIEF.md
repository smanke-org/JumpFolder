# JumpFolder

A menu bar helper that makes every app's Open and Save dialog faster: click a Finder window behind the dialog to jump there, and pick recent or favorite folders from a strip attached to the dialog's edge. For one person who saves and opens files all day.

## Replaces
The Open/Save dialog features of a third-party dialog utility (click-through to Finder windows, recent/favorite folder menus), which broke on macOS 27.2 until its permission was toggled.

## Main jobs
1. **Jump to a Finder window.** While an Open/Save dialog is frontmost, clicking a Finder window behind it moves the dialog to that window's folder; Finder does not come forward. Hold ⌥ while clicking to bring Finder forward as usual.
2. **Edge controls.** A small floating strip sits on the dialog's left edge, follows it as it moves and resizes, and hides when it closes. Buttons: Recent folders, Favorite folders, Open Finder windows (menus), and Reveal current folder in Finder.
3. **Manage favorites and recents in Settings.** Add, remove, reorder favorites; set how many recents to keep; clear recents; exclude apps.
4. **Last folder per app.** Each app's last-used folder appears at the top of Recents in that app's dialogs.
5. **Recents shortcut.** Optional global shortcut (off by default, standard shortcut editor) pops the Recent folders menu while a dialog is up.

## Data
- **Favorite**: folder path, display name, order (synced).
- **Recent folder**: path, last-used date (per Mac, capped, default 15).
- **App last folder**: bundle id → path (per Mac).
- **Excluded app**: bundle id (synced).
- Settings in UserDefaults; no database.

## Shape
Menu bar extra (accessory app) plus a Settings window, macOS 26 or later. Local data. Works offline except update checks. No accounts. Needs Accessibility ("Device Control and Data Access" on macOS 27); Input Monitoring only if the event tap requires it.

## Standard pattern (same as the other apps)
- Settings window that scrolls and drags bigger (size remembered); "Settings", never "Preferences".
- General first: Appearance (System/Light/Dark), Ask before quitting, Show in Dock / Show in menu bar (any combo; reopen opens Settings), Dock right-click Settings item.
- Opt-in iCloud settings sync (iCloud Drive/JumpFolder/Settings.plist, whitelisted keys: favorites, excluded apps, behavior switches, appearance, update choice).
- AutoUpdater with Automatic / Ask / Don't check, check every 1 day by default, install only when idle; notarized Developer ID builds.
- Help window (?, menu item, ⌘?), About window with release notes, menu icons via MenuIcon, app icon via the shared drawSymbol rule ("Jf").
- ToolHUD menu hub, agent CLI + MCP (`jumpfolder`), Shortcuts report if a global shortcut is added.

## System hooks
Accessibility observer for dialogs, CGEventTap for clicks, Finder via Apple Events (needs Automation permission for Finder), menu bar, optional global shortcut for the Recent folders menu (off by default).

## Reference
The third-party dialog utility the user already owns (never named in the repo).

## Look
Native, system accent. The edge strip is a small vibrant glass panel with SF Symbols, matching the dialog's light/dark look.

## Not in version one
- File info, tags, rename/delete/preview inside the dialog.
- Per-app default folders and folder sets.
- Finder-window drawer, spring-loaded folders, Finder click-through for non-Finder file managers.
