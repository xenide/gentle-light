import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    static func main() {
        installSignalHandlers()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = DisplayController.shared

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 280)
        popover.contentViewController = NSHostingController(
            rootView: SettingsView(controller: controller)
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "eye",
                accessibilityDescription: "GentleLight"
            )
            button.action = #selector(toggle(_:))
            button.target = self
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DisplayController.shared.shutdown()
    }

    @objc private func toggle(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    nonisolated private static func installSignalHandlers() {
        signal(SIGINT) { _ in
            CGDisplayRestoreColorSyncSettings()
            exit(0)
        }
        signal(SIGTERM) { _ in
            CGDisplayRestoreColorSyncSettings()
            exit(0)
        }
    }
}
