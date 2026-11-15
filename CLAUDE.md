# JumpFolder — notes for agents

Menu bar helper for other apps' Open and Save dialogs: click a Finder window behind a dialog to take the dialog there, and a strip of folder buttons (Recent, Favorites, Finder Windows, Reveal) on the dialog's edge. Read `docs/BRIEF.md` before changing anything.

## Rules
- **Never name the reference app** (the paid dialog utility the brief mentions) anywhere: code, comments, commits, README, UI, tests. Call it "the reference app". Copy no code, resources or wording from it; behavior ideas only.
- US spelling in user-facing text. "Settings", never "Preferences".
- Coordinates: JumpFolderKit and Accessibility use global **top-left** coordinates. AppKit windows are bottom-left: convert with `EdgePanel.appKitRect`.
- Pure logic goes in `JumpFolderKit` with Swift Testing tests; AppKit/AX stays in the app target.
- Match the surrounding code: comment density, naming, the house helpers (`AppPresence`, `AppAppearance`, `MenuIcon.showIcon`, `Caption`).

## How dialogs look on macOS 27 (verified 2026-11-15)
- The Open/Save panel runs in `com.apple.appkit.xpc.openAndSavePanelService`, but AX shows it as a window of the host app with `AXIdentifier` `open-panel` (subrole AXStandardWindow); its children come from the service's pid. CGWindowList lists it under the host app, layer 0.
- File rows are `AXTextField`s with `AXURL` file-reference URLs (`file:///.file/id=…`); their parent is the current folder. The folder pop-up has identifier `where popup` (value wrapped in Unicode isolate marks).
- ⌘⇧G opens an `AXSheet` `GoToWindow` with `PathTextField`. Setting its AXValue shows the text but does not change the panel's own path (Return then does nothing), so `DialogNavigator` types the path as key events.
- Finder windows expose no folder through AX (`AXDocument` is nil): `FinderWindows` asks Finder over Apple Events and matches by bounds (AppleScript bounds are top-left, same as AX).

## Build and test
- Unit tests: `swift test`
- Snapshots without touching the real app: `JUMPFOLDER_DATA_DIR=<scratch>/data JUMPFOLDER_SNAPSHOT=<scratch>/snaps "$(swift build --show-bin-path)/JumpFolder"` (debug build; `JUMPFOLDER_SNAPSHOT_PAGES=settings-dialogs,edge,…`).
- Signed app: `./build_app.sh` (Developer ID; keeps the Accessibility grant across rebuilds). Install: `./install.sh`.
- Debug hook (installed app launched with `open --env JUMPFOLDER_DEBUG=1 /Applications/JumpFolder.app`): post distributed notification `com.smanke.JumpFolder.debug` with object `dump:dialog`, `dump:edge`, `dump:finder`, `dump:menu`, `go:<path>`, `click:<x>,<y>`, `show:<Tab>`, `help:<topic>`; results in `~/Library/Logs/JumpFolder.log`.
- Never capture the live screen; capture only your own test windows (`screencapture -x -o -l <CGWindowID>`). Only send keys or clicks after confirming the test app is frontmost.
- Drive the app with `jumpfolder` (the app binary; `jumpfolder help`). Commands live in `Sources/JumpFolder/Agent/AgentCommands.swift`.
