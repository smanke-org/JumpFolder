import AppKit
import JumpFolderKit

/// The strip of folder buttons beside the dialog in front: Recent Folders, Favorite Folders,
/// Finder Windows, and Reveal in Finder. It follows the dialog as it moves and resizes, and
/// hides when the dialog closes or its app goes to the back. It never activates JumpFolder,
/// so the dialog keeps the keyboard.
@MainActor
final class EdgePanel {
    static let shared = EdgePanel()

    enum Button: String, CaseIterable {
        case recents, favorites, finderWindows, reveal

        var symbol: String {
            switch self {
            case .recents: "clock.arrow.circlepath"
            case .favorites: "star"
            case .finderWindows: "macwindow.on.rectangle"
            case .reveal: "magnifyingglass"
            }
        }

        var help: String {
            switch self {
            case .recents: "Recent Folders"
            case .favorites: "Favorite Folders"
            case .finderWindows: "Finder Windows"
            case .reveal: "Reveal Current Folder in Finder"
            }
        }
    }

    static let buttonSize: CGFloat = 30
    static let padding: CGFloat = 5
    static let spacing: CGFloat = 4
    static var stripSize: CGSize {
        let count = CGFloat(Button.allCases.count)
        return CGSize(width: buttonSize + padding * 2,
                      height: count * buttonSize + (count - 1) * spacing + padding * 2)
    }

    private lazy var panel = makePanel()
    private var buttons: [Button: NSButton] = [:]
    private lazy var messagePanel = MessagePanel()

    func start() {
        DialogWatcher.shared.onChange = { [weak self] in self?.update() }
    }

    /// Shown and placed beside the dialog, or hidden.
    func update() {
        let watcher = DialogWatcher.shared
        guard AppSettings.shared.edgeControls, let frame = watcher.frame, watcher.dialog != nil,
              frame.width > 50, frame.height > 50 else {
            if panel.isVisible { panel.orderOut(nil) }
            if watcher.dialog == nil { messagePanel.hide() }
            return
        }
        let visible = Self.visibleFrame(around: frame)
        let strip = EdgeLayout.frame(for: frame, strip: Self.stripSize, side: AppSettings.shared.edgeSide, visible: visible)
        panel.setFrame(Self.appKitRect(strip), display: true)
        buttons[.reveal]?.isEnabled = watcher.currentFolder != nil
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    var isVisible: Bool { panel.isVisible }

    #if DEBUG
    /// Snapshot mode: the strip on its own, without a dialog.
    func debugShow(at point: NSPoint) -> NSWindow {
        panel.setFrameOrigin(point)
        panel.orderFrontRegardless()
        return panel
    }
    #endif
    var debugFrame: CGRect? { panel.isVisible ? panel.frame : nil }

    /// A quick pulse to show a click on a Finder window was taken.
    func flash() {
        guard panel.isVisible, let content = panel.contentView else { return }
        content.alphaValue = 0.4
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            content.animator().alphaValue = 1
        }
    }

    /// A short note beside the dialog, gone after a few seconds.
    func showMessage(_ text: String) {
        guard let frame = DialogWatcher.shared.frame else { return }
        messagePanel.show(text, below: Self.appKitRect(frame))
    }

    /// Opens a button's menu, from the strip if it's showing, otherwise at the pointer
    /// (the shortcuts).
    func open(_ button: Button) {
        let watcher = DialogWatcher.shared
        guard watcher.dialog != nil else {
            NSSound.beep()
            return
        }
        if button == .reveal {
            FolderMenus.reveal(watcher.currentFolder)
            return
        }
        menu(for: button) { [weak self] menu in
            if let self, self.panel.isVisible, let view = self.buttons[button] {
                let leftSide = self.panel.frame.maxX <= (watcher.frame.map { Self.appKitRect($0).minX } ?? .infinity) + 1
                let point = leftSide ? NSPoint(x: 0, y: view.bounds.maxY) : NSPoint(x: view.bounds.maxX, y: view.bounds.maxY)
                menu.popUp(positioning: nil, at: point, in: view)
            } else {
                menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            }
        }
    }

    private func menu(for button: Button, _ done: @escaping @MainActor (NSMenu) -> Void) {
        let watcher = DialogWatcher.shared
        switch button {
        case .recents: done(FolderMenus.recentsMenu(for: watcher.dialog))
        case .favorites: done(FolderMenus.favoritesMenu(currentFolder: watcher.currentFolder))
        case .finderWindows: FolderMenus.finderWindowsMenu(done)
        case .reveal: break
        }
    }

    // MARK: - Building

    private func makePanel() -> NSPanel {
        let size = Self.stripSize
        let panel = StripPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        // Above dialogs (which may sit at the modal-panel level), below the app's menus.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        AppAppearance.followSystem(panel)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = Self.spacing
        stack.edgeInsets = NSEdgeInsets(top: Self.padding, left: Self.padding, bottom: Self.padding, right: Self.padding)
        for kind in Button.allCases {
            let button = StripButton(symbol: kind.symbol, help: kind.help) { [weak self] in self?.open(kind) }
            button.widthAnchor.constraint(equalToConstant: Self.buttonSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: Self.buttonSize).isActive = true
            buttons[kind] = button
            stack.addArrangedSubview(button)
        }
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        glass.cornerRadius = 12
        glass.contentView = stack
        panel.contentView = glass
        return panel
    }

    // MARK: - Coordinates

    /// Global top-left (Accessibility) to AppKit's bottom-left.
    static func appKitRect(_ rect: CGRect) -> NSRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The usable area of the display holding most of `rect`, in top-left coordinates.
    static func visibleFrame(around rect: CGRect) -> CGRect {
        let appKit = appKitRect(rect)
        let screen = NSScreen.screens.max { a, b in
            a.frame.intersection(appKit).width * a.frame.intersection(appKit).height
                < b.frame.intersection(appKit).width * b.frame.intersection(appKit).height
        } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return rect }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: visible.minX, y: mainHeight - visible.maxY, width: visible.width, height: visible.height)
    }
}

/// Never takes the keyboard from the dialog.
private final class StripPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A borderless symbol button that acts on mouse-down, even while JumpFolder is in the
/// background (the first click on another app's floating panel would otherwise be eaten).
private final class StripButton: NSButton {
    private let onPress: () -> Void

    init(symbol: String, help: String, action: @escaping () -> Void) {
        self.onPress = action
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .regularSquare
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        contentTintColor = .labelColor
        toolTip = help
        setAccessibilityLabel(help)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.15).cgColor
        onPress()
        layer?.backgroundColor = nil
    }

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }

    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = nil }
}

/// A small floating note under the dialog ("JumpFolder isn't allowed to control Finder…").
@MainActor
private final class MessagePanel {
    private var panel: NSPanel?
    private var label = NSTextField(wrappingLabelWithString: "")
    private var hideTask: Task<Void, Never>?

    func show(_ text: String, below dialog: NSRect) {
        let panel = self.panel ?? make()
        label.stringValue = text
        let width = min(max(dialog.width - 40, 260), 520)
        label.preferredMaxLayoutWidth = width - 24
        let height = label.intrinsicContentSize.height + 20
        panel.setFrame(NSRect(x: dialog.midX - width / 2, y: dialog.minY - height - 8, width: width, height: height), display: true)
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() { panel?.orderOut(nil) }

    private func make() -> NSPanel {
        let panel = StripPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        AppAppearance.followSystem(panel)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let glass = NSGlassEffectView()
        glass.cornerRadius = 10
        let holder = NSView()
        holder.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
        ])
        glass.contentView = holder
        panel.contentView = glass
        self.panel = panel
        return panel
    }
}
