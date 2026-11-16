import AppKit
import JumpFolderKit

/// While an Open or Save dialog is in front, a click on a Finder window behind it takes the
/// dialog to that window's folder, and Finder stays where it is. Holding Option lets the
/// click through to Finder as usual.
///
/// The event tap runs on its own thread, so a busy main thread (or a slow answer from
/// Finder) never makes the pointer stutter: the tap only decides, from the window list and
/// the dialog snapshot, whether to keep the click, and hands the work to the main thread.
final class ClickThrough: @unchecked Sendable {
    static let shared = ClickThrough()

    private var tap: CFMachPort?
    private var thread: Thread?
    /// Set when a mouse-down was kept, so its drags and mouse-up are kept too.
    private var swallowing = false
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Starts the tap (needs Device Control and Data Access). Safe to call again later.
    func start() {
        guard tap == nil else { return }
        let thread = Thread { [weak self] in self?.runTap() }
        thread.name = "JumpFolder click tap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    private func runTap() {
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<ClickThrough>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type, event)
        }, userInfo: refcon) else {
            Diagnostics.note("click tap could not start (no access?)")
            DispatchQueue.main.async { self.thread = nil }
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Diagnostics.note("click tap started")
        CFRunLoopRun()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .leftMouseDragged:
            return swallowing ? nil : Unmanaged.passUnretained(event)
        case .leftMouseUp:
            if swallowing {
                swallowing = false
                return nil
            }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown:
            swallowing = false
            DispatchQueue.main.async { MainActor.assumeIsolated { HoverHint.shared.clicked() } }
            guard let target = finderWindowHit(by: event) else { return Unmanaged.passUnretained(event) }
            swallowing = true
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ClickThrough.jump(toFinderWindowAt: target) }
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// The bounds of the Finder window this click lands on, if the click should take the
    /// dialog there instead.
    private func finderWindowHit(by event: CGEvent) -> CGRect? {
        if event.flags.contains(.maskAlternate) { return nil }
        let state = DialogWatcher.snapshot.current
        guard state.clickThrough, state.pid != 0 else { return nil }
        let point = event.location
        // A click on the dialog (or inside its frame) is the dialog's.
        if state.frame.contains(point) { return nil }
        // JumpFolder's own windows (the hover ring sits right on top of the Finder window)
        // never take clicks, so look past them.
        let windows = Self.windowList().filter { $0.ownerPID != ownPID }
        guard let hit = ClickTarget.hit(point, in: windows, displays: Self.displayFrames()),
              hit.ownerName == "Finder", hit.layer == 0 else { return nil }
        return hit.bounds
    }

    /// Every display's frame in global top-left coordinates (CoreGraphics', safe off the main thread).
    static func displayFrames() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    static func windowList() -> [ClickTarget.Window] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return info.compactMap { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            return ClickTarget.Window(ownerPID: pid, ownerName: w[kCGWindowOwnerName as String] as? String ?? "",
                                      bounds: bounds, layer: w[kCGWindowLayer as String] as? Int ?? 0,
                                      alpha: w[kCGWindowAlpha as String] as? Double ?? 1,
                                      number: w[kCGWindowNumber as String] as? Int ?? 0)
        }
    }

    /// Asks Finder which folder the clicked window shows and takes the dialog there.
    @MainActor
    static func jump(toFinderWindowAt bounds: CGRect) {
        Diagnostics.note("click on Finder window at \(bounds)")
        EdgePanel.shared.flash()
        FinderWindows.list { windows, error in
            let candidates = windows.filter { !$0.path.isEmpty }.map { (bounds: $0.bounds, value: $0.path) }
            guard let path = ClickTarget.match(bounds, in: candidates) else {
                Diagnostics.note("no folder for that Finder window (\(error ?? "not a folder window"))")
                if let error { EdgePanel.shared.showMessage(error) } else { NSSound.beep() }
                return
            }
            DialogNavigator.go(to: path)
        }
    }
}
