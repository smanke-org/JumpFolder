import AppKit
import JumpFolderKit
import SwiftUI

/// A shortcut box for every shortcut in `ShortcutCatalog`, grouped as the catalog groups them.
/// Keys another JumpFolder action already uses move to the one being set; the editor says so first.
struct ShortcutsSettings: View {
    var body: some View {
        Form {
            Section("Dialogs") {
                ForEach(ShortcutCatalog.all, id: \.id) { item in row(item) }
            }
            Section {
                Caption("These shortcuts work while an Open or Save dialog is in front: they open the same lists as the buttons beside the dialog, at the pointer when the buttons are hidden. None is set at first. Click a shortcut to set it: pick the modifier keys and type a key, or press the shortcut. Keys another JumpFolder shortcut has are moved here. A shortcut another app already uses may not respond.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(_ item: ShortcutCatalog.Item) -> some View {
        LabeledContent(item.title) {
            // The editor has already taken these keys off any other shortcut.
            ShortcutRecorder(hotKey: Binding(
                get: { AppSettings.shared.shortcut(item.id) },
                set: { AppSettings.shared.setShortcut(item.id, $0) }), id: item.id)
                .fixedSize()
        }
    }

    /// The other action using this key, if any (ShortcutsLens's Change Shortcut refuses it).
    static func clashingAction(_ key: HotKey, for id: String) -> ShortcutCatalog.Item? {
        func combo(_ k: HotKey) -> [UInt32] { [k.keyCode, k.modifiers] }
        let owner = ShortcutClash.owner(of: combo(key), for: id, among: ShortcutCatalog.all.map(\.id)) {
            AppSettings.shared.shortcut($0).map(combo)
        }
        return owner.flatMap(ShortcutCatalog.item)
    }
}
