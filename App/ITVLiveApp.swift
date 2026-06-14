import SwiftUI
import AppKit

@main
struct ITVLiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        // A single-window utility, so use `Window` (not `WindowGroup`) — it
        // always presents one window and avoids the restore-zero-windows trap.
        Window("itv.live", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
                .task {
                    // Skip normal bootstrap in headless snapshot mode (the
                    // AppDelegate drives rendering there with its own model).
                    if SnapshotMode.requestedDirectory == nil { await model.bootstrap() }
                }
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Refresh EPG") { Task { await model.loadEPG(forceRefresh: true) } }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(model.playlist == nil)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}

/// Drives headless snapshot rendering from `applicationDidFinishLaunching`, which
/// fires once `NSApplication` is up — independent of whether the SwiftUI window
/// scene ever presents a window (it may not in a restricted/headless session).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force a dark AppKit appearance so the titlebar, toolbar and the
        // AVPlayerView transport controls match the SwiftUI dark theme.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        guard let dir = SnapshotMode.requestedDirectory else { return }
        FileHandle.standardError.write(Data("snapshot: launching for \(dir.path)\n".utf8))
        Task { @MainActor in await SnapshotMode.run(into: dir) }
    }
}
