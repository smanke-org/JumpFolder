import CoreGraphics

/// Which side of the dialog the edge controls sit on.
public enum EdgeSide: String, CaseIterable, Sendable {
    /// Left when there is room, otherwise right, otherwise just inside the left edge.
    case automatic
    case left
    case right
}

/// Where the edge controls go next to a dialog. All rectangles are in global top-left
/// coordinates (Accessibility's), so this works without AppKit.
public enum EdgeLayout {
    /// Space between the dialog and the strip.
    public static let gap: CGFloat = 6
    /// How far below the dialog's top the strip starts, clear of its title area.
    public static let topInset: CGFloat = 44

    /// The strip's frame for a dialog `dialog` on a display whose usable area is `visible`.
    public static func frame(for dialog: CGRect, strip: CGSize, side: EdgeSide, visible: CGRect) -> CGRect {
        let y = clamp(dialog.minY + topInset, visible.minY, visible.maxY - strip.height)
        let leftX = dialog.minX - gap - strip.width
        let rightX = dialog.maxX + gap
        let fitsLeft = leftX >= visible.minX
        let fitsRight = rightX + strip.width <= visible.maxX
        let x: CGFloat
        switch side {
        case .left:
            x = fitsLeft ? leftX : dialog.minX + gap
        case .right:
            x = fitsRight ? rightX : dialog.maxX - gap - strip.width
        case .automatic:
            if fitsLeft { x = leftX } else if fitsRight { x = rightX } else { x = dialog.minX + gap }
        }
        return CGRect(x: x, y: y, width: strip.width, height: strip.height)
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        high < low ? low : min(max(value, low), high)
    }
}

/// Picks the window a click lands on from the window list (front to back), so a click on a
/// Finder window behind a dialog can be told from a click on the dialog itself.
public enum ClickTarget {
    public struct Window: Equatable, Sendable {
        public var ownerPID: Int32
        public var ownerName: String
        public var bounds: CGRect
        public var layer: Int
        public var alpha: Double
        public var number: Int

        public init(ownerPID: Int32, ownerName: String, bounds: CGRect, layer: Int, alpha: Double = 1, number: Int = 0) {
            self.ownerPID = ownerPID
            self.ownerName = ownerName
            self.bounds = bounds
            self.layer = layer
            self.alpha = alpha
            self.number = number
        }
    }

    /// The frontmost visible window under `point`, ignoring the window server's own bits and
    /// invisible windows. Menu bar, overlay and our own windows count: a click there is not a
    /// click on a Finder window.
    public static func hit(_ point: CGPoint, in windows: [Window]) -> Window? {
        windows.first { w in
            w.alpha > 0.01 && w.bounds.width > 4 && w.bounds.height > 4
                && w.ownerName != "Window Server" && w.bounds.contains(point)
        }
    }

    /// The Finder window (from Finder's own list, front to back) whose bounds match `bounds`.
    public static func match<T>(_ bounds: CGRect, in finderWindows: [(bounds: CGRect, value: T)], tolerance: CGFloat = 2) -> T? {
        finderWindows.first { candidate in
            abs(candidate.bounds.minX - bounds.minX) <= tolerance && abs(candidate.bounds.minY - bounds.minY) <= tolerance
                && abs(candidate.bounds.width - bounds.width) <= tolerance && abs(candidate.bounds.height - bounds.height) <= tolerance
        }?.value
    }
}
