import Cocoa
import SwiftUI

@main
struct PerfGuardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var performanceManager: PerformanceManager!
    var cleanupTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        performanceManager = PerformanceManager()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: "PerfGuard")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(manager: performanceManager)
        )

        // Auto-cleanup every 30 minutes
        schedulePeriodicCleanup()
        
        // Update RAM stats every 3 seconds
        performanceManager.startMonitoring()
    }

    @objc func togglePopover() {
        if let button = statusItem.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover.contentViewController?.view.window?.makeKey()
            }
        }
    }

    func schedulePeriodicCleanup() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            self.performanceManager.runCleanup()
        }
    }
}
