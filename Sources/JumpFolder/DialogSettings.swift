import AppKit
import JumpFolderKit
import SwiftUI
import UniformTypeIdentifiers

/// How JumpFolder helps with Open and Save dialogs, and which apps it leaves alone.
struct DialogSettings: View {
    @Bindable var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Click a Finder window to take the dialog there", isOn: $settings.clickThrough)
                Toggle("Highlight the Finder window under the pointer", isOn: $settings.hoverHint)
                    .disabled(!settings.clickThrough)
                Caption("While an Open or Save dialog is in front, clicking a Finder window behind it takes the dialog to that window's folder, and Finder stays where it is. Hold Option (⌥) while clicking to bring Finder forward instead. With highlighting on, the window you point at gets a colored outline and a “Jump to” label.")
            }
            Section {
                Toggle("Show folder buttons beside dialogs", isOn: $settings.edgeControls)
                Picker("Side", selection: $settings.edgeSide) {
                    Text("Automatic").tag(EdgeSide.automatic)
                    Text("Left").tag(EdgeSide.left)
                    Text("Right").tag(EdgeSide.right)
                }
                .disabled(!settings.edgeControls)
                Toggle("Show labels under the buttons", isOn: $settings.edgeLabels)
                    .disabled(!settings.edgeControls)
                Caption("A strip on the dialog's edge with Recent Folders, Favorite Folders, Finder Windows and Reveal in Finder. Automatic puts it on the left, or on the right when there's no room. Turn labels off for a narrower strip of icons only.")
            }
            Section("Leave These Apps Alone") {
                if settings.excludedApps.isEmpty {
                    Caption("JumpFolder helps with every app's dialogs.")
                }
                ForEach(settings.excludedApps, id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Button("Remove") { settings.excludedApps.removeAll { $0 == bundleID } }
                            .controlSize(.small)
                    }
                }
                HStack {
                    Button("Add App…") { addApp() }
                    Spacer()
                }
                Caption("In these apps' Open and Save dialogs, JumpFolder shows no buttons, lets clicks through to Finder and doesn't remember folders.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.clickThrough) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.hoverHint) { HoverHint.shared.update() }
        .onChange(of: settings.edgeControls) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.edgeSide) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.edgeLabels) { DialogWatcher.shared.settingsChanged() }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Leave Alone"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !settings.excludedApps.contains(id) {
                settings.excludedApps.append(id)
            }
        }
    }
}

/// An app's icon and name from its bundle id, or the id when it isn't installed.
struct AppLabel: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Label {
                Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
            }
        } else {
            Label(bundleID, systemImage: "app.dashed")
        }
    }
}
