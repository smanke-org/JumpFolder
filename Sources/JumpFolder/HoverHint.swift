import AppKit
import JumpFolderKit

/// While an Open or Save dialog is in front, pointing at a Finder window behind it shows that
/// a click will take the dialog there: an accent ring around the window and a "Jump to
/// <folder>" pill beside the pointer. Neither ever takes a click.
@MainActor
final class HoverHint {
    static let shared = HoverHint()

    static let ringWidth: CGFloat = 3

    private var monitor: Any?
    private var refreshTimer: Timer?
    private lazy var ring = RingPanel()
    private lazy var pill = PillPanel()

    /// The Finder window pointed at (CG window number) and its folder, once Finder said.
    private var target: (number: Int, bounds: CGRect)?
    private var folder: String?
    private var showing = false

    /// Finder's windows, asked once per dialog and again for a window it didn't know.
    private var finderWindows: [FinderWindows.Window] = []
    private var askedFinder = false
    private var asking = false

    private var windowsCache: (date: Date, list: [ClickTarget.Window])?
    /// The hint shows a hidden Finder window (x-ray) rather than a visible one.
    private var showingXRay = false
    private var lastFinderAsk = Date.distantPast

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .flagsChanged, .leftMouseDown, .rightMouseDown]) { event in
            MainActor.assumeIsolated {
                switch event.type {
                case .leftMouseDown, .rightMouseDown: HoverHint.shared.hide()
                default: HoverHint.shared.update()
                }
            }
        }
    }

    /// The dialog came, went or changed: forget what Finder said and look again.
    func dialogChanged() {
        if DialogWatcher.shared.dialog == nil {
            finderWindows = []
            askedFinder = false
        }
        update()
    }

    /// The click tap took a click: the hint has done its job.
    func clicked() { hide() }

    func update() {
        guard let hit = targetUnderPointer() else {
            if let xray = xrayUnderPointer() {
                showXRay(xray)
            } else {
                hide()
            }
            return
        }
        XRayTarget.set(nil)
        let point = Self.pointer()
        if target?.number != hit.number || target?.bounds != hit.bounds {
            target = (hit.number, hit.bounds)
            folder = folderFor(hit.bounds)
            if folder == nil { askFinder() }
        }
        guard let folder else {
            // Not known yet (Finder is answering), or not a folder window (Recents, a search).
            if showing { hide(keepTarget: true) }
            return
        }
        ring.show(around: hit.bounds, above: hit.number, dashed: false, animate: !showing || showingXRay)
        showingXRay = false
        pill.show(name: FileManager.default.displayName(atPath: folder), at: point, animate: !showing)
        showing = true
        startRefreshing()
    }

    func hide() { hide(keepTarget: false) }

    private func hide(keepTarget: Bool) {
        XRayTarget.set(nil)
        showingXRay = false
        if !keepTarget {
            target = nil
            folder = nil
        }
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard showing else { return }
        showing = false
        ring.fadeOut()
        pill.fadeOut()
    }

    /// While shown, look again now and then: the window may move or close under a still pointer.
    private func startRefreshing() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { HoverHint.shared.update() }
        }
    }

    // MARK: - What's under the pointer

    private func targetUnderPointer() -> ClickTarget.Window? {
        let settings = AppSettings.shared
        let watcher = DialogWatcher.shared
        guard settings.clickThrough, settings.hoverHint, watcher.dialog != nil, !DialogNavigator.isBusy,
              !NSEvent.modifierFlags.contains(.option) else { return nil }
        let point = Self.pointer()
        if let frame = watcher.frame, frame.contains(point) { return nil }
        let own = ProcessInfo.processInfo.processIdentifier
        let windows = windowList().filter { $0.ownerPID != own }
        guard let hit = ClickTarget.hit(point, in: windows, displays: ClickThrough.displayFrames()),
              hit.ownerName == "Finder", hit.layer == 0 else { return nil }
        return hit
    }

    // MARK: - X-ray: Finder windows the person can't see

    /// A Finder window hidden at the pointer (behind a full-screen app, on another Space, or
    /// under other windows), outside the dialog, that the X-ray settings allow.
    private func xrayUnderPointer() -> (bounds: CGRect, path: String, dialogNumber: Int?)? {
        let settings = AppSettings.shared
        let watcher = DialogWatcher.shared
        guard settings.clickThrough, settings.xrayOptions.any, let dialog = watcher.dialog, let frame = watcher.frame,
              !DialogNavigator.isBusy, !NSEvent.modifierFlags.contains(.option) else { return nil }
        let point = Self.pointer()
        if frame.contains(point) { return nil }
        let own = ProcessInfo.processInfo.processIdentifier
        let all = windowList()
        let displays = ClickThrough.displayFrames()
        // JumpFolder's own buttons and menus keep the pointer.
        if let top = ClickTarget.hit(point, in: all, displays: displays), top.ownerPID == own, top.layer != 0 { return nil }
        refreshFinderWindows()
        let onScreen = all.filter { $0.ownerName == "Finder" && $0.layer == 0 }.map(\.bounds)
        let dialogDisplay = displays.first { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }
        let hostFullScreen = all.contains { $0.ownerPID == dialog.pid && $0.layer == 0
            && XRay.fillsDisplay($0.bounds, displays: displays) == dialogDisplay && dialogDisplay != nil }
        let finder = finderWindows.filter { !$0.path.isEmpty }.map { (bounds: $0.bounds, value: $0.path) }
        guard let found = XRay.target(at: point, finder: finder, onScreen: onScreen, hostFullScreen: hostFullScreen,
                                      dialogDisplay: dialogDisplay, options: settings.xrayOptions) else { return nil }
        // The ring goes right under the dialog, so the dialog still covers it.
        let dialogNumber = all.first { $0.ownerPID == dialog.pid && $0.layer == 0
            && abs($0.bounds.minX - frame.minX) < 3 && abs($0.bounds.minY - frame.minY) < 3 }?.number
        return (found.bounds, found.value, dialogNumber)
    }

    private func showXRay(_ xray: (bounds: CGRect, path: String, dialogNumber: Int?)) {
        XRayTarget.set((xray.bounds, xray.path))
        ring.show(around: xray.bounds, below: xray.dialogNumber, dashed: true, animate: !showing || !showingXRay)
        pill.show(name: FileManager.default.displayName(atPath: xray.path), at: Self.pointer(), animate: !showing)
        showing = true
        showingXRay = true
        startRefreshing()
    }

    /// Hidden windows can't be seen opening, moving or closing: ask Finder again every couple
    /// of seconds while the pointer is out looking for one.
    private func refreshFinderWindows() {
        guard !asking, Date().timeIntervalSince(lastFinderAsk) > 2 else { return }
        lastFinderAsk = Date()
        asking = true
        FinderWindows.list { [weak self] windows, _ in
            guard let self else { return }
            self.asking = false
            self.askedFinder = true
            self.finderWindows = windows
        }
    }

    /// The window list changes slowly next to the pointer; don't ask for it on every move.
    private func windowList() -> [ClickTarget.Window] {
        if let cache = windowsCache, Date().timeIntervalSince(cache.date) < 0.1 { return cache.list }
        let list = ClickThrough.windowList()
        windowsCache = (Date(), list)
        return list
    }

    private func folderFor(_ bounds: CGRect) -> String? {
        let candidates = finderWindows.filter { !$0.path.isEmpty }.map { (bounds: $0.bounds, value: $0.path) }
        return ClickTarget.match(bounds, in: candidates)
    }

    private func askFinder() {
        guard !asking else { return }
        // Once per window Finder hasn't told us about yet.
        if askedFinder, let target, ClickTarget.match(target.bounds, in: finderWindows.map { (bounds: $0.bounds, value: 0) }) != nil {
            return
        }
        asking = true
        FinderWindows.list { [weak self] windows, _ in
            guard let self else { return }
            self.asking = false
            self.askedFinder = true
            self.finderWindows = windows
            if let target = self.target {
                self.folder = self.folderFor(target.bounds)
                if self.folder != nil { self.update() }
            }
        }
    }

    /// The pointer in global top-left coordinates, like the window list's.
    static func pointer() -> CGPoint {
        let location = NSEvent.mouseLocation
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: location.x, y: mainHeight - location.y)
    }
}

// MARK: - Ring

/// An accent outline just outside a Finder window, stacked right above that window so the
/// dialog and anything else in front still cover it.
@MainActor
private final class RingPanel {
    /// A Finder window's corner radius on macOS 26 and later.
    static let windowCornerRadius: CGFloat = 24
    private lazy var panel = make()
    private let shape = CAShapeLayer()

    func show(around bounds: CGRect, above windowNumber: Int, dashed: Bool, animate: Bool) {
        place(around: bounds, dashed: dashed)
        panel.level = .normal
        panel.order(.above, relativeTo: windowNumber)
        if animate { fade(in: true) }
    }

    /// X-ray: the Finder window is hidden, so the ring goes over everything but the dialog
    /// (right under it), with a faint fill so the window's place reads as a target.
    func show(around bounds: CGRect, below dialogNumber: Int?, dashed: Bool, animate: Bool) {
        place(around: bounds, dashed: dashed)
        if let dialogNumber {
            panel.level = .normal
            panel.order(.below, relativeTo: dialogNumber)
        } else {
            panel.level = .floating
            panel.orderFrontRegardless()
        }
        if animate { fade(in: true) }
    }

    private func place(around bounds: CGRect, dashed: Bool) {
        let width = HoverHint.ringWidth
        let frame = EdgePanel.appKitRect(bounds.insetBy(dx: -width, dy: -width))
        if panel.frame != frame {
            panel.setFrame(frame, display: false)
            layout()
        }
        shape.strokeColor = NSColor.controlAccentColor.cgColor
        shape.lineDashPattern = dashed ? [10, 6] : nil
        shape.fillColor = dashed ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor : nil
    }

    func fadeOut() { fade(in: false) }

    private func fade(in visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated {
                if !visible && panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    private func layout() {
        guard let view = panel.contentView else { return }
        let width = HoverHint.ringWidth
        shape.frame = view.bounds
        // Windows on macOS 26 and later have large rounded corners; follow them, a ring's
        // width out.
        let rect = view.bounds.insetBy(dx: width / 2, dy: width / 2)
        let radius = Self.windowCornerRadius + width / 2
        shape.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .normal
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.alphaValue = 0
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView()
        view.wantsLayer = true
        shape.fillColor = nil
        shape.lineWidth = HoverHint.ringWidth
        shape.shadowColor = NSColor.black.cgColor
        shape.shadowOpacity = 0.25
        shape.shadowRadius = 2
        shape.shadowOffset = .zero
        view.layer?.addSublayer(shape)
        panel.contentView = view
        return panel
    }
}

// MARK: - Pill

/// "Jump to <folder>" in an accent capsule just below and right of the pointer.
@MainActor
private final class PillPanel {
    private lazy var panel = make()
    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private var name = ""

    static let offset = CGSize(width: 14, height: 20)

    func show(name: String, at point: CGPoint, animate: Bool) {
        _ = panel
        if name != self.name {
            self.name = name
            label.stringValue = "Jump to \(name)"
        }
        let size = fittingSize()
        // Below-right of the pointer, flipped to stay on its display.
        var origin = CGPoint(x: point.x + Self.offset.width, y: point.y + Self.offset.height)
        let visible = EdgePanel.visibleFrame(around: CGRect(origin: point, size: CGSize(width: 1, height: 1)))
        if origin.x + size.width > visible.maxX { origin.x = point.x - Self.offset.width / 2 - size.width }
        if origin.y + size.height > visible.maxY { origin.y = point.y - 8 - size.height }
        panel.setFrame(EdgePanel.appKitRect(CGRect(origin: origin, size: size)), display: true)
        panel.contentView?.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        panel.orderFrontRegardless()
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    func fadeOut() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated {
                if panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    private func fittingSize() -> CGSize {
        let text = label.intrinsicContentSize
        // icon 14 + gap 5, padding 10 each side
        return CGSize(width: ceil(min(text.width, 320) + 14 + 5 + 20), height: 24)
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // Above the dialog and every other window, like a tooltip.
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.alphaValue = 0
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.cornerCurve = .continuous
        icon.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        icon.contentTintColor = .white
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        panel.contentView = view
        return panel
    }
}

/// The hidden Finder window the x-ray outline shows, for the click tap (its own thread) to
/// take: a click inside it goes to its folder.
enum XRayTarget {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var value: (bounds: CGRect, path: String)?

    static func set(_ target: (bounds: CGRect, path: String)?) {
        lock.lock(); defer { lock.unlock() }
        value = target
    }

    static func current() -> (bounds: CGRect, path: String)? {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}
