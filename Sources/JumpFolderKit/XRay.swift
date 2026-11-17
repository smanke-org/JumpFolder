import CoreGraphics

/// Finder windows the person can't see while a dialog is up: behind a full-screen app, on
/// another Space, or covered by other windows. Pointing at where one sits (outside the dialog)
/// outlines it, and a click there takes the dialog to its folder.
public enum XRay {
    public enum Kind: Sendable, Equatable {
        /// Off screen while the dialog's app fills the display (the desktop is a Space away).
        case behindFullScreen
        /// Off screen otherwise: on another Space, or the display's own full-screen Space.
        case otherSpace
        /// On screen but under other windows at the pointer.
        case covered
    }

    public struct Options: Sendable, Equatable {
        public var behindFullScreen: Bool
        public var otherSpaces: Bool
        public var covered: Bool

        public init(behindFullScreen: Bool = true, otherSpaces: Bool = true, covered: Bool = true) {
            self.behindFullScreen = behindFullScreen
            self.otherSpaces = otherSpaces
            self.covered = covered
        }

        public func allows(_ kind: Kind) -> Bool {
            switch kind {
            case .behindFullScreen: behindFullScreen
            case .otherSpace: otherSpaces
            case .covered: covered
            }
        }

        public var any: Bool { behindFullScreen || otherSpaces || covered }
    }

    public static func kind(of bounds: CGRect, onScreen: [CGRect], hostFullScreen: Bool,
                            dialogDisplay: CGRect?) -> Kind {
        if onScreen.contains(where: { close($0, bounds) }) { return .covered }
        if hostFullScreen, let dialogDisplay, dialogDisplay.contains(CGPoint(x: bounds.midX, y: bounds.midY)) {
            return .behindFullScreen
        }
        return .otherSpace
    }

    /// The front-most Finder window (`finder` is front to back) under `point` that the options
    /// allow, or nil. Call only when no visible Finder window is under the pointer.
    public static func target<T>(at point: CGPoint, finder: [(bounds: CGRect, value: T)], onScreen: [CGRect],
                                 hostFullScreen: Bool, dialogDisplay: CGRect?, options: Options) -> (bounds: CGRect, value: T)? {
        for window in finder where window.bounds.contains(point) {
            let kind = kind(of: window.bounds, onScreen: onScreen, hostFullScreen: hostFullScreen, dialogDisplay: dialogDisplay)
            if options.allows(kind) { return window }
        }
        return nil
    }

    /// Whether an app window fills a display: what a full-screen app looks like in the window list.
    public static func fillsDisplay(_ bounds: CGRect, displays: [CGRect]) -> CGRect? {
        displays.first { close($0, bounds, tolerance: 1) }
    }

    private static func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
