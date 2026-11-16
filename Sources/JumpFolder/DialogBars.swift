import AppKit
import JumpFolderKit

/// The bar style: Recent, Favorites, Finder and Reveal in a row of pills above the dialog,
/// and under it a bar with the dialog's folder path and a few folders to jump to (the app's
/// recently used or most used folders, or the favorites). Both follow the dialog and never
/// take the keyboard from it.
@MainActor
final class DialogBars {
    static let shared = DialogBars()

    static let gap: CGFloat = 6

    private lazy var top = BarWindow()
    private lazy var bottom = BarWindow()
    /// What each bar was last built from; rebuilt only when it changes.
    private var topKey = ""
    private var bottomKey = ""
    private var revealChip: Chip?

    var isVisible: Bool { top.isVisible }

    func update() {
        let watcher = DialogWatcher.shared
        let settings = AppSettings.shared
        guard settings.edgeControls, settings.controlStyle == .bars, let dialog = watcher.dialog,
              let frame = watcher.frame, frame.width > 50, frame.height > 50 else {
            hide()
            return
        }
        let visible = EdgePanel.visibleFrame(around: frame)

        let folder = watcher.currentFolder
        let key = "\(folder ?? "")"
        if key != topKey || top.contentViews.isEmpty {
            buildTop(folder: folder)
            topKey = key
        }
        var topRect = CGRect(origin: .zero, size: top.fittingSize)
        topRect.origin.x = min(max(frame.midX - topRect.width / 2, visible.minX), visible.maxX - topRect.width)
        topRect.origin.y = max(frame.minY - Self.gap - topRect.height, visible.minY)
        top.place(topRect)

        let source = settings.source(for: dialog.bundleID)
        let folders = settings.bottomBar ? bottomFolders(source: source, app: dialog.bundleID, current: folder) : []
        let showPath = settings.bottomBar && settings.breadcrumb && folder != nil
        guard settings.bottomBar, showPath || !folders.isEmpty else {
            bottom.hide()
            bottomKey = ""
            return
        }
        let bottomKey = [folder ?? "", source.rawValue, "\(showPath)", "\(frame.width)"].joined(separator: "|") + folders.map(\.path).joined()
        if bottomKey != self.bottomKey {
            buildBottom(folder: showPath ? folder : nil, source: source, folders: folders, maxWidth: max(frame.width, 420))
            self.bottomKey = bottomKey
        }
        var bottomRect = CGRect(origin: .zero, size: bottom.fittingSize)
        bottomRect.origin.x = min(max(frame.midX - bottomRect.width / 2, visible.minX), visible.maxX - bottomRect.width)
        bottomRect.origin.y = min(frame.maxY + Self.gap, visible.maxY - bottomRect.height)
        bottom.place(bottomRect)
    }

    func hide() {
        top.hide()
        bottom.hide()
    }

    /// A quick pulse when a click on a Finder window was taken.
    func flash() { top.flash() }

    /// Opens the top bar's menu for `kind` (the shortcuts use this); false when the bar is hidden.
    func open(_ kind: EdgePanel.Button) -> Bool {
        guard top.isVisible, let chip = top.contentViews.compactMap({ $0 as? Chip }).first(where: { $0.kind == kind }) else { return false }
        chip.press()
        return true
    }

    // MARK: - Top

    private func buildTop(folder: String?) {
        var chips: [NSView] = []
        for kind in EdgePanel.Button.allCases {
            let chip = Chip(title: kind.label, symbol: kind.symbol, style: .action, menu: kind != .reveal, help: kind.help)
            chip.kind = kind
            chip.onPress = { [weak chip] in
                guard let chip else { return }
                Self.openMenu(kind, from: chip)
            }
            if kind == .reveal {
                chip.isEnabled = folder != nil
                revealChip = chip
            }
            chips.append(chip)
        }
        top.setContent(chips, spacing: 4, insets: 4)
    }

    private static func openMenu(_ kind: EdgePanel.Button, from chip: Chip) {
        let watcher = DialogWatcher.shared
        let show = { (menu: NSMenu) in menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: chip) }
        switch kind {
        case .recents: show(FolderMenus.recentsMenu(for: watcher.dialog))
        case .favorites: show(FolderMenus.favoritesMenu(currentFolder: watcher.currentFolder))
        case .finderWindows: FolderMenus.finderWindowsMenu { show($0) }
        case .reveal: FolderMenus.reveal(watcher.currentFolder)
        }
    }

    // MARK: - Bottom

    struct BarFolder {
        let path: String
        let name: String
    }

    private func bottomFolders(source: BarSource, app: String?, current: String?) -> [BarFolder] {
        let settings = AppSettings.shared
        let count = settings.bottomCount
        let others = { (paths: [String]) -> [BarFolder] in
            let shown = Array(paths.filter { $0 != current }.prefix(count))
            let titles = FolderMenus.distinctTitles(shown)
            return shown.map { BarFolder(path: $0, name: titles[$0] ?? FolderPath.displayName($0)) }
        }
        switch source {
        case .recent: return others(settings.history.recent(for: app, count: count + 1, exists: FolderMenus.exists))
        case .mostUsed: return others(settings.history.mostUsed(for: app, count: count + 1, exists: FolderMenus.exists))
        case .favorites:
            return settings.favorites.filter { $0.path != current && FolderMenus.exists($0.path) }
                .prefix(count).map { BarFolder(path: $0.path, name: $0.displayName) }
        }
    }

    private func buildBottom(folder: String?, source: BarSource, folders: [BarFolder], maxWidth: CGFloat) {
        // Shorten the path first, then drop folders, until the bar fits under the dialog.
        var segments = folder.map(Self.ancestors) ?? []
        var shown = folders
        var maxSegments = 3
        while true {
            let views = bottomViews(segments: segments, maxSegments: maxSegments, source: source, folders: shown)
            bottom.setContent(views, spacing: 4, insets: 4)
            if bottom.fittingSize.width <= maxWidth { return }
            if maxSegments > 1 { maxSegments -= 1 }
            else if shown.count > 1 { shown.removeLast() }
            else if !segments.isEmpty { segments = [] }
            else { return }
        }
    }

    private func bottomViews(segments: [String], maxSegments: Int, source: BarSource, folders: [BarFolder]) -> [NSView] {
        var views: [NSView] = []
        if !segments.isEmpty {
            let icon = NSImageView(image: NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = .secondaryLabelColor
            icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
            views.append(Self.padded(icon, left: 6))
            let hidden = segments.dropLast(maxSegments)
            if !hidden.isEmpty {
                let more = Chip(title: "…", symbol: nil, style: .path, menu: false, help: "Folders further up")
                more.onPress = { [weak more] in
                    guard let more else { return }
                    let menu = NSMenu()
                    for path in hidden.reversed() { menu.addItem(FolderMenus.folderItem(path)) }
                    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: more.bounds.height + 4), in: more)
                }
                views.append(more)
                views.append(Self.separator("›"))
            }
            let shown = Array(segments.suffix(maxSegments))
            for (index, path) in shown.enumerated() {
                let last = index == shown.count - 1
                let chip = Chip(title: FileManager.default.displayName(atPath: path), symbol: nil, style: last ? .current : .path,
                                menu: false, help: FolderPath.abbreviated(path))
                if !last { chip.onPress = { FolderMenus.open(path) } }
                views.append(chip)
                if !last { views.append(Self.separator("›")) }
            }
        }
        if !folders.isEmpty {
            if !views.isEmpty { views.append(Self.divider()) }
            let label = NSTextField(labelWithString: source.shortTitle)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .tertiaryLabelColor
            views.append(Self.padded(label, left: views.isEmpty ? 8 : 2))
            for folder in folders {
                let chip = Chip(title: folder.name, symbol: source == .favorites ? "star" : nil, style: .folder,
                                menu: false, help: FolderPath.abbreviated(folder.path))
                chip.onPress = { FolderMenus.open(folder.path) }
                views.append(chip)
            }
            let more = Chip(title: "", symbol: "chevron.down", style: .path, menu: false, help: "More \(source.title) Folders")
            more.onPress = { [weak more] in
                guard let more else { return }
                FolderMenus.sourceMenu(source).popUp(positioning: nil, at: NSPoint(x: 0, y: more.bounds.height + 4), in: more)
            }
            views.append(more)
        }
        return views
    }

    /// `path` and every folder above it, top first, without the disk root.
    static func ancestors(of path: String) -> [String] {
        var list: [String] = []
        var current = path
        while current != "/" && !current.isEmpty {
            list.insert(current, at: 0)
            current = (current as NSString).deletingLastPathComponent
        }
        return list
    }

    private static func separator(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabelColor
        return label
    }

    private static func divider() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 16).isActive = true
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(line)
        NSLayoutConstraint.activate([
            holder.widthAnchor.constraint(equalToConstant: 9),
            line.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            holder.heightAnchor.constraint(equalToConstant: 16),
        ])
        return holder
    }

    private static func padded(_ view: NSView, left: CGFloat) -> NSView {
        let stack = NSStackView(views: [view])
        stack.edgeInsets = NSEdgeInsets(top: 0, left: left, bottom: 0, right: 0)
        return stack
    }
}

extension BarSource {
    /// The quiet label before the bottom bar's folders.
    var shortTitle: String {
        switch self {
        case .recent: "Recent"
        case .mostUsed: "Most used"
        case .favorites: "Favorites"
        }
    }
}

// MARK: - Window

/// A floating capsule that never takes the keyboard.
@MainActor
private final class BarWindow {
    private lazy var panel = make()
    private let stack = NSStackView()
    private var glass: NSGlassEffectView?

    var isVisible: Bool { panel.isVisible }
    var contentViews: [NSView] { stack.arrangedSubviews }
    var fittingSize: CGSize {
        _ = panel
        let size = stack.fittingSize
        return CGSize(width: ceil(size.width), height: 34)
    }

    func setContent(_ views: [NSView], spacing: CGFloat, insets: CGFloat) {
        _ = panel
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.spacing = spacing
        stack.edgeInsets = NSEdgeInsets(top: insets, left: insets, bottom: insets, right: insets + 2)
        views.forEach { stack.addArrangedSubview($0) }
        stack.layoutSubtreeIfNeeded()
    }

    func place(_ rect: CGRect) {
        let frame = EdgePanel.appKitRect(rect)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        glass?.cornerRadius = rect.height / 2
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        if panel.isVisible { panel.orderOut(nil) }
    }

    func flash() {
        guard panel.isVisible, let content = panel.contentView else { return }
        content.alphaValue = 0.4
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            content.animator().alphaValue = 1
        }
    }

    private func make() -> NSPanel {
        let panel = NonKeyPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 34),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        AppAppearance.followSystem(panel)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        let glass = NSGlassEffectView()
        glass.cornerRadius = 17
        let holder = NSView()
        holder.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            stack.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
        ])
        glass.contentView = holder
        panel.contentView = glass
        self.glass = glass
        return panel
    }
}

private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Chip

/// A capsule button that acts on mouse-down, even while JumpFolder is in the background.
@MainActor
final class Chip: NSView {
    enum Style {
        /// Top bar: neutral, with a chevron when it opens a menu.
        case action
        /// A folder to jump to: accent tint.
        case folder
        /// A folder in the path: plain text.
        case path
        /// The dialog's own folder at the end of the path: bold, not a button.
        case current
    }

    var onPress: (() -> Void)?
    var kind: EdgePanel.Button?
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.4 } }

    private let style: Style
    private var hovering = false { didSet { updateBackground() } }

    init(title: String, symbol: String?, style: Style, menu: Bool, help: String) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        toolTip = help
        setAccessibilityElement(true)
        setAccessibilityRole(style == .current ? .staticText : .button)
        setAccessibilityLabel(title.isEmpty ? help : title)

        let tint: NSColor = switch style {
        case .action: .labelColor
        case .folder: .controlAccentColor
        case .path: .secondaryLabelColor
        case .current: .labelColor
        }
        var views: [NSView] = []
        if let symbol {
            let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
            image.symbolConfiguration = .init(pointSize: 12, weight: .medium)
            image.contentTintColor = tint
            views.append(image)
        }
        if !title.isEmpty {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12, weight: style == .current || style == .action ? .medium : .regular)
            label.textColor = tint
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 150).isActive = true
            views.append(label)
        }
        if menu {
            let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) ?? NSImage())
            chevron.symbolConfiguration = .init(pointSize: 8, weight: .semibold)
            chevron.contentTintColor = .secondaryLabelColor
            views.append(chevron)
        }
        let stack = NSStackView(views: views)
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let horizontal: CGFloat = style == .path || style == .current ? 6 : 10
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontal),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontal),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 26),
        ])
        updateBackground()
    }

    required init?(coder: NSCoder) { fatalError() }

    func press() {
        guard isEnabled, style != .current else { return }
        onPress?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, style != .current else { return }
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
        onPress?()
        updateBackground()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = isEnabled && style != .current }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color: NSColor? = switch style {
            case .action: NSColor.labelColor.withAlphaComponent(hovering ? 0.12 : 0.06)
            case .folder: NSColor.controlAccentColor.withAlphaComponent(hovering ? 0.26 : 0.15)
            case .path: hovering ? NSColor.labelColor.withAlphaComponent(0.08) : nil
            case .current: nil
            }
            layer?.backgroundColor = color?.cgColor
        }
    }
}
