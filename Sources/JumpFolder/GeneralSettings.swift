import SwiftUI

struct GeneralSettings: View {
    @Bindable var settings = AppSettings.shared
    @Bindable var hub = MenuHub.shared
    let launchAtLogin: LaunchAtLogin
    @State private var trusted = AX.isTrusted

    var body: some View {
        Form {
            if !trusted {
                Section {
                    Label("JumpFolder can't see Open and Save dialogs yet. Turn on JumpFolder in Privacy & Security › Device Control and Data Access.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Open Privacy Settings") { WelcomeWindow.shared.show() }
                }
            }
            Section {
                AppearancePicker()
                Caption(AppAppearance.footer(appName: "JumpFolder"))
            }
            Section {
                Toggle("Open JumpFolder at login", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                    .disabled(!LaunchAtLogin.isInstalled && !launchAtLogin.isEnabled)
                if !LaunchAtLogin.isInstalled && !launchAtLogin.isEnabled {
                    Caption("Only the copy of JumpFolder in Applications can open at login.")
                }
                if launchAtLogin.needsApproval {
                    HStack {
                        Caption("Waiting for approval in Login Items.")
                        Button("Open Login Items") { launchAtLogin.openLoginItemsSettings() }.controlSize(.small)
                    }
                }
                Toggle("Ask before quitting", isOn: $settings.confirmQuit)
                    .help("Quitting JumpFolder asks first, so a stray ⌘Q doesn't turn off its dialog helpers and shortcuts.")
            }
            Section {
                Toggle("Show in Dock", isOn: $settings.showInDock)
                    .help("Adds a Dock icon whose right-click menu opens Settings.")
                Toggle("Show in menu bar", isOn: $settings.showInMenuBar)
                Toggle("Put in ToolHUD’s menu while ToolHUD is running", isOn: $hub.foldIntoToolHUD)
                    .help("ToolHUD shows this menu as a submenu of its own, and JumpFolder’s icon leaves the menu bar until ToolHUD quits.")
                if !settings.showInDock && !settings.showInMenuBar {
                    Caption(AppPresence.hiddenEverywhereNote(appName: "JumpFolder", settingsName: "Settings"))
                }
            }
            SyncUpdateSections()
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin.refresh()
            trusted = AX.isTrusted
        }
    }
}
