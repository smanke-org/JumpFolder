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
            Section("X-ray hidden Finder windows") {
                Toggle("Behind full-screen apps", isOn: $settings.xrayFullScreen)
                Toggle("On other Spaces and displays", isOn: $settings.xraySpaces)
                Toggle("Behind other windows", isOn: $settings.xrayCovered)
                Caption("When a Finder window is hidden, point where it sits, outside the dialog: a dashed outline and a “Jump to” label appear, and a click there takes the dialog to its folder. Nothing shows until you point at one.")
            }
            .disabled(!settings.clickThrough)
            Section {
                Toggle("Show folder buttons around dialogs", isOn: $settings.edgeControls)
                Picker("Style", selection: $settings.controlStyle) {
                    Text("Bars above and below").tag(ControlStyle.bars)
                    Text("Strip on the side").tag(ControlStyle.strip)
                }
                .disabled(!settings.edgeControls)
                if settings.controlStyle == .bars {
                    Toggle("Show the bar below the dialog", isOn: $settings.bottomBar)
                        .disabled(!settings.edgeControls)
                    Picker("Folders in it", selection: $settings.bottomSource) {
                        ForEach(BarSource.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .disabled(!settings.edgeControls || !settings.bottomBar)
                    Stepper("Show \(settings.bottomCount) folders", value: $settings.bottomCount, in: AppSettings.bottomCountRange)
                        .disabled(!settings.edgeControls || !settings.bottomBar)
                    Toggle("Show the folder path", isOn: $settings.breadcrumb)
                        .disabled(!settings.edgeControls || !settings.bottomBar)
                    Caption("Above the dialog: Recent, Favorites, Finder and Reveal. Below it: the dialog's folder path (click a folder to go up to it) and a few folders to jump to. Recently Used and Most Used are kept for each app, so Excel's folders differ from Word's; an app with only a few of its own also shows other apps' recent folders.")
                } else {
                    Picker("Side", selection: $settings.edgeSide) {
                        Text("Automatic").tag(EdgeSide.automatic)
                        Text("Left").tag(EdgeSide.left)
                        Text("Right").tag(EdgeSide.right)
                    }
                    .disabled(!settings.edgeControls)
                    Toggle("Show labels under the buttons", isOn: $settings.edgeLabels)
                        .disabled(!settings.edgeControls)
                    Caption("A strip on the dialog's edge with Recent Folders, Favorite Folders, Finder Windows and Reveal in Finder. Automatic puts it on the left, or on the right when there's no room.")
                }
            }
            Section("Per-App Settings") {
                if listedApps.isEmpty {
                    Caption("Every app uses the settings above.")
                }
                ForEach(listedApps, id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Picker("", selection: choice(for: bundleID)) {
                            Text("Use Default").tag("default")
                            ForEach(BarSource.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                            Divider()
                            Text("Leave Alone").tag("alone")
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Remove") { remove(bundleID) }
                            .controlSize(.small)
                    }
                }
                HStack {
                    Button("Add App…") { addApp() }
                    Spacer()
                }
                Caption("Pick which folders the bar below shows in an app's dialogs, or leave the app alone: no buttons, clicks go through to Finder, and its folders aren't remembered.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.clickThrough) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.hoverHint) { HoverHint.shared.update() }
        .onChange(of: settings.xrayOptions) { HoverHint.shared.update() }
        .onChange(of: settings.edgeControls) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.edgeSide) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.edgeLabels) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.controlStyle) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.bottomBar) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.bottomSource) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.bottomCount) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.breadcrumb) { DialogWatcher.shared.settingsChanged() }
        .onChange(of: settings.appSources) { DialogWatcher.shared.settingsChanged() }
    }

    /// Apps with a choice of their own, or left alone.
    private var listedApps: [String] {
        Array(Set(settings.excludedApps).union(settings.appSources.keys)).sorted {
            AppLabel.name(for: $0).localizedCaseInsensitiveCompare(AppLabel.name(for: $1)) == .orderedAscending
        }
    }

    private func choice(for bundleID: String) -> Binding<String> {
        Binding {
            if settings.excludedApps.contains(bundleID) { return "alone" }
            return settings.appSources[bundleID] ?? "default"
        } set: { value in
            if value == "alone" {
                if !settings.excludedApps.contains(bundleID) { settings.excludedApps.append(bundleID) }
                settings.appSources[bundleID] = "default"
            } else {
                settings.excludedApps.removeAll { $0 == bundleID }
                settings.appSources[bundleID] = value
            }
        }
    }

    private func remove(_ bundleID: String) {
        settings.excludedApps.removeAll { $0 == bundleID }
        settings.appSources[bundleID] = nil
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, settings.appSources[id] == nil, !settings.excludedApps.contains(id) {
                settings.appSources[id] = "default"
            }
        }
    }
}

/// An app's icon and name from its bundle id, or the id when it isn't installed.
struct AppLabel: View {
    let bundleID: String

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

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
