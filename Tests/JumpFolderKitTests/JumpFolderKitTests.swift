import CoreGraphics
import Foundation
import Testing
@testable import JumpFolderKit

@Suite struct FolderHistoryTests {
    @Test func recordMovesToTopAndDedupes() {
        var h = FolderHistory()
        h.record("/a", app: "x")
        h.record("/b/", app: "y")
        h.record("/a", app: "x")
        #expect(h.paths == ["/a", "/b"])
        #expect(h.lastByApp == ["x": "/a", "y": "/b"])
    }

    @Test func limitIsClampedAndApplied() {
        var h = FolderHistory()
        for i in 0..<20 { h.record("/f\(i)", app: nil, limit: 5) }
        #expect(h.entries.count == 5)
        #expect(h.paths.first == "/f19")
        h.trim(to: 1) // clamped up to the lowest allowed
        #expect(h.entries.count == FolderHistory.limitRange.lowerBound)
    }

    @Test func menuPathsPutAppLastFirstAndSkipMissing() {
        var h = FolderHistory()
        h.record("/one", app: "a")
        h.record("/two", app: "b")
        h.record("/gone", app: nil)
        let menu = h.menuPaths(for: "a") { $0 != "/gone" }
        #expect(menu.appLast == "/one")
        #expect(menu.others == ["/two"])
        #expect(h.menuPaths(for: "zzz").appLast == nil)
    }

    @Test func removeDropsAppLast() {
        var h = FolderHistory()
        h.record("/one", app: "a")
        h.remove("/one")
        #expect(h.paths.isEmpty && h.lastByApp.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        var h = FolderHistory()
        h.record("/x", app: "a", at: Date(timeIntervalSince1970: 5))
        let back = try JSONDecoder().decode(FolderHistory.self, from: JSONEncoder().encode(h))
        #expect(back == h)
    }

    @Test func emptyAndRelativePathsAreIgnored() {
        var h = FolderHistory()
        h.record("", app: "a")
        h.record("relative/path", app: "a")
        #expect(h.entries.isEmpty)
    }
}

@Suite struct FolderPathTests {
    @Test func normalizes() {
        #expect(FolderPath.normalized("/a/b/") == "/a/b")
        #expect(FolderPath.normalized("/a/./b/../c") == "/a/c")
        #expect(FolderPath.normalized("/") == "/")
        #expect(FolderPath.normalized("  ") == "")
    }

    @Test func names() {
        #expect(FolderPath.displayName("/Users/me/Documents") == "Documents")
        #expect(FolderPath.displayName("/") == "Computer")
        #expect(FolderPath.abbreviated("/Users/me/Documents", home: "/Users/me") == "~/Documents")
        #expect(FolderPath.abbreviated("/Users/me", home: "/Users/me") == "~")
        #expect(FolderPath.abbreviated("/Users/meme", home: "/Users/me") == "/Users/meme")
        #expect(FolderPath.parent(of: "/a/b/file.txt") == "/a/b")
    }

    @Test func cleansDirectionMarks() {
        #expect(FolderPath.cleanedTitle("\u{2068}TextEdit\u{2069} — iCloud") == "TextEdit — iCloud")
    }

    @Test func favoritesAddOnce() {
        var list: [Favorite] = []
        #expect(Favorites.add("/a/", to: &list))
        #expect(!Favorites.add("/a", to: &list))
        #expect(list.map(\.path) == ["/a"])
        #expect(Favorite(path: "/a/Projects", name: "").displayName == "Projects")
        #expect(Favorite(path: "/a/Projects", name: "Work").displayName == "Work")
    }
}

@Suite struct EdgeLayoutTests {
    let visible = CGRect(x: 0, y: 25, width: 1000, height: 700)
    let strip = CGSize(width: 40, height: 200)

    @Test func automaticPrefersLeft() {
        let f = EdgeLayout.frame(for: CGRect(x: 300, y: 100, width: 400, height: 300), strip: strip, side: .automatic, visible: visible)
        #expect(f.maxX == 300 - EdgeLayout.gap)
        #expect(f.minY == 100 + EdgeLayout.topInset)
    }

    @Test func automaticFallsBackToRightThenInside() {
        let nearLeft = EdgeLayout.frame(for: CGRect(x: 10, y: 100, width: 400, height: 300), strip: strip, side: .automatic, visible: visible)
        #expect(nearLeft.minX == 410 + EdgeLayout.gap)
        let wide = EdgeLayout.frame(for: CGRect(x: 0, y: 100, width: 1000, height: 300), strip: strip, side: .automatic, visible: visible)
        #expect(wide.minX == EdgeLayout.gap)
    }

    @Test func staysOnScreenVertically() {
        let low = EdgeLayout.frame(for: CGRect(x: 300, y: 650, width: 400, height: 300), strip: strip, side: .left, visible: visible)
        #expect(low.maxY == visible.maxY)
    }

    @Test func forcedRightFallsInside() {
        let f = EdgeLayout.frame(for: CGRect(x: 580, y: 100, width: 420, height: 300), strip: strip, side: .right, visible: visible)
        #expect(f.maxX == 1000 - EdgeLayout.gap)
    }
}

@Suite struct ClickTargetTests {
    let windows: [ClickTarget.Window] = [
        .init(ownerPID: 1, ownerName: "Window Server", bounds: CGRect(x: 0, y: 0, width: 2000, height: 30), layer: 24),
        .init(ownerPID: 9, ownerName: "JumpFolder", bounds: CGRect(x: 50, y: 50, width: 40, height: 200), layer: 3),
        .init(ownerPID: 2, ownerName: "TextEdit", bounds: CGRect(x: 100, y: 100, width: 400, height: 300), layer: 0),
        .init(ownerPID: 3, ownerName: "Finder", bounds: CGRect(x: 0, y: 0, width: 800, height: 600), layer: 0),
    ]

    @Test func dialogWinsOverFinderBehindIt() {
        #expect(ClickTarget.hit(CGPoint(x: 200, y: 200), in: windows)?.ownerName == "TextEdit")
    }

    @Test func finderHitOutsideDialog() {
        #expect(ClickTarget.hit(CGPoint(x: 600, y: 500), in: windows)?.ownerName == "Finder")
    }

    @Test func ownWindowsCountWindowServerIsSkipped() {
        #expect(ClickTarget.hit(CGPoint(x: 60, y: 60), in: windows)?.ownerName == "JumpFolder")
        #expect(ClickTarget.hit(CGPoint(x: 10, y: 10), in: windows)?.ownerName == "Finder")
    }

    @Test func fullDisplayOverlaysAreSkipped() {
        let overlay = ClickTarget.Window(ownerPID: 7, ownerName: "Notification Center", bounds: CGRect(x: 0, y: 0, width: 1000, height: 800), layer: 23)
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(ClickTarget.hit(CGPoint(x: 600, y: 500), in: [overlay] + windows, displays: [display])?.ownerName == "Finder")
        // Without knowing the displays it would look like a click on the overlay.
        #expect(ClickTarget.hit(CGPoint(x: 600, y: 500), in: [overlay] + windows)?.ownerName == "Notification Center")
        // A normal-level window covering the display (a full-screen app) still counts.
        let fullScreenApp = ClickTarget.Window(ownerPID: 8, ownerName: "Safari", bounds: display, layer: 0)
        #expect(ClickTarget.hit(CGPoint(x: 600, y: 500), in: [fullScreenApp] + windows, displays: [display])?.ownerName == "Safari")
    }

    @Test func matchByBounds() {
        let finder: [(bounds: CGRect, value: String)] = [
            (CGRect(x: 0, y: 0, width: 10, height: 10), "/a"),
            (CGRect(x: 100, y: 100, width: 500, height: 400), "/b"),
        ]
        #expect(ClickTarget.match(CGRect(x: 101, y: 100, width: 500, height: 399), in: finder) == "/b")
        #expect(ClickTarget.match(CGRect(x: 120, y: 100, width: 500, height: 400), in: finder) == nil)
    }
}
