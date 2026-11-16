# JumpFolder

JumpFolder makes every app's Open and Save dialogs quicker. The folder you want is often already open in a Finder window, so with a dialog in front, just click that Finder window: the dialog goes to its folder and Finder stays behind. A small strip of buttons on the dialog's edge lists your recent and favorite folders and Finder's open windows, and reveals the dialog's folder in Finder.

<p align="center"><img src="docs/images/jumpfolder-strip.png" width="72" alt="The JumpFolder strip: Recent, Favorites, Finder and Reveal buttons"></p>

## Download

### [⬇ Download JumpFolder for Mac](https://github.com/smanke-org/JumpFolder/releases/latest/download/JumpFolder.dmg)

1. Open `JumpFolder.dmg`.
2. Drag JumpFolder to Applications.
3. Open JumpFolder, then turn it on under System Settings › Privacy & Security › Device Control and Data Access. It needs this to see dialogs and the clicks around them.
4. The first time you click a Finder window behind a dialog, macOS asks to let JumpFolder control Finder, so it can read which folder that window shows. Click Allow.

Requires macOS 26 or later. Free.

## Features

- **Click a Finder window to jump.** With an Open or Save dialog in front, click any Finder window behind it and the dialog goes to that folder. Finder doesn't come forward, so you keep going in the dialog. Hold ⌥ to bring Finder forward instead.
- **Folder buttons around the dialog.** Above it: Recent, Favorites, Finder and Reveal. Below it: the dialog's folder path, plus a few folders to jump to: each app's recently used or most used folders, or your favorites. Both follow the dialog and hide when it closes. Prefer a strip on the dialog's side? That style is still there.
  - **Recent Folders**, with the app's own last folder first.
  - **Favorite Folders**, with Add to Favorites for the folder the dialog shows.
  - **Finder Windows**: the folder of every open Finder window.
  - **Reveal in Finder** for the dialog's folder.
- **Leave apps alone.** List apps whose dialogs JumpFolder should ignore.
- **Shortcuts.** Give each list a keyboard shortcut; they work while a dialog is in front.
- **Works with your other apps.** `jumpfolder://` links for scripts and Shortcuts, buttons in ToolHUD, and its shortcuts listed in ShortcutsLens.
- **A command line for scripts and AI agents.** `jumpfolder` shows the dialog in front, takes it to a folder, and lists or changes recent folders, favorites and settings in the running app (`jumpfolder mcp` for MCP apps).
- **Settings sync.** Favorites, apps left alone, shortcuts and options follow you to your other Macs through iCloud Drive. Recent folders stay on each Mac.
- **Help built in.** ⌘? or the ? button in Settings.

<p align="center"><img src="docs/images/jumpfolder-settings-dialogs.png" width="420" alt="Settings › Dialogs: clicking Finder windows, folder buttons and their side, and apps to leave alone"> <img src="docs/images/jumpfolder-settings-folders.png" width="420" alt="Settings › Folders: favorite folders and how many recent folders to remember"></p>

## How it works

On macOS 26 and later, Open and Save dialogs run in a separate system service, but Accessibility still shows each one as a window of the app that opened it. JumpFolder watches the app in front for that window and places its strip beside it. To take the dialog somewhere, it starts from the nearest place the dialog has a key for (Home, Desktop, Documents, Downloads, Applications, or a folder or two up) and opens one folder after another in the dialog's own list, so no Go to Folder sheet pops up. For a folder the list can't show, such as a hidden one, it falls back to the dialog's Go to Folder (⇧⌘G), typing the path and pressing Return. Finder windows don't say which folder they show through Accessibility, so JumpFolder asks Finder and matches the window you clicked by its position.

## Updates

JumpFolder checks GitHub for new versions as often as you choose (daily by default). It can install them by itself when no dialog is open, ask first, or never check. Settings › General.

## Building

```bash
swift test          # unit tests
./build_app.sh      # Developer ID signed .app in .build/app
./install.sh        # copy to /Applications and open
```

## License

© 2026 Steve Manke. All rights reserved.
