import AppKit
import SwiftUI

@main
struct YunleFunMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var workspace = MacWorkspace()

    var body: some Scene {
        Window("云乐坊", id: "main") {
            MacRootView(workspace: workspace, catalog: workspace.catalog,
                        accounts: workspace.accounts, runtime: workspace.runtime)
                .modifier(CatalogIconUpdates())
                .frame(minWidth: 860, minHeight: 560)
                .task { await workspace.start() }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("返回应用目录") { workspace.showCatalog() }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("刷新应用目录") { Task { await workspace.refreshCatalog() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Link("云乐坊帮助", destination: URL(string: "https://apps.yunle.fun")!)
            }
        }
        Settings {
            MacAccountView(accounts: workspace.accounts)
                .frame(width: 560, height: 520)
        }
    }
}

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
