import AppKit
import SwiftUI

/// Explains the permissions JumpFolder needs (Device Control and Data Access, then Finder
/// automation) and closes itself once access is granted.
@MainActor
final class WelcomeWindow: NSObject, NSWindowDelegate {
    static let shared = WelcomeWindow()

    private var window: NSWindow?
    private var timer: Timer?
    /// Called once access is granted, to refresh the menu bar icon.
    var onGranted: (() -> Void)?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: WelcomeView(
                open: { [weak self] in self?.openSettings() },
                later: { [weak self] in self?.window?.close() }))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to JumpFolder"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        watch()
    }

    /// The prompt adds JumpFolder to the list (switched off); then the Settings page opens.
    private func openSettings() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// No relaunch needed: the grant is noticed within a second and the window closes.
    private func watch() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                Diagnostics.note("access granted")
                self?.timer?.invalidate()
                self?.window?.close()
                self?.onGranted?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Keep watching while access is still off, so the menu bar badge clears when it's granted.
        if AXIsProcessTrusted() { timer?.invalidate() }
    }
}

private struct WelcomeView: View {
    let open: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                Text("Welcome to JumpFolder").font(.title2.bold())
            }
            Text("JumpFolder can't see Open and Save dialogs yet.")
                .font(.headline)
            Text("To find dialogs, place its folder buttons beside them and take them to a Finder window you click, JumpFolder needs access. Turn on JumpFolder in Privacy & Security › Device Control and Data Access.")
                .fixedSize(horizontal: false, vertical: true)
            Text("The first time you click a Finder window behind a dialog, macOS also asks to let JumpFolder control Finder, so it can read which folder that window shows. Click Allow.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("This window closes by itself once access is on.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Later", action: later).keyboardShortcut(.cancelAction)
                Button("Open Privacy Settings", action: open).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}
