import AppKit
import JumpFolderKit
import SwiftUI

/// Favorite folders (synced) and recent folders (this Mac).
struct FolderSettings: View {
    @Bindable var settings = AppSettings.shared
    @State private var selection: Favorite.ID?

    var body: some View {
        Form {
            Section("Favorite Folders") {
                if settings.favorites.isEmpty {
                    Caption("No favorites yet. Add folders here, or choose Add to Favorites from the star button beside a dialog.")
                }
                List(selection: $selection) {
                    ForEach($settings.favorites) { $favorite in
                        FavoriteRow(favorite: $favorite)
                    }
                    .onMove { settings.favorites.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { settings.favorites.remove(atOffsets: $0) }
                }
                .frame(minHeight: 120)
                HStack {
                    Button("Add Folder…") { addFolders() }
                    Button("Remove") {
                        settings.favorites.removeAll { $0.id == selection }
                        selection = nil
                    }
                    .disabled(selection == nil)
                    Spacer()
                }
                Caption("Drag to reorder. Favorites follow you to your other Macs when settings sync is on.")
            }
            Section("Recent Folders") {
                Stepper(value: $settings.recentsLimit, in: FolderHistory.limitRange) {
                    Text("Remember \(settings.recentsLimit) folders")
                }
                HStack {
                    Text(settings.history.entries.isEmpty ? "No recent folders yet." : "\(settings.history.entries.count) remembered on this Mac.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear Recent Folders") { settings.history.clear() }
                        .disabled(settings.history.entries.isEmpty)
                }
                Caption("A folder becomes recent when a dialog closes in it or JumpFolder takes a dialog there. Each app's last folder is listed first in that app's dialogs. Recent folders stay on this Mac.")
            }
        }
        .formStyle(.grouped)
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Favorites"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { Favorites.add(url.path, to: &settings.favorites) }
    }
}

private struct FavoriteRow: View {
    @Binding var favorite: Favorite

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: favorite.path)).resizable().frame(width: 18, height: 18)
            TextField("Name", text: $favorite.name, prompt: Text(FolderPath.displayName(favorite.path)))
                .textFieldStyle(.plain)
                .frame(maxWidth: 180, alignment: .leading)
            Text(FolderPath.abbreviated(favorite.path))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(favorite.path)
        }
    }
}
