import SwiftUI
import ServiceManagement

let openPairingNotification = Notification.Name("openPairingWindow")

@main
struct OTPBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: "infinity")
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var pairingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestPermission()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenPairing),
            name: openPairingNotification,
            object: nil
        )
        registerLoginItem()
        if PairingManager.shared.isPaired() {
            WebSocketServer.shared.restoreSharedSecret()
        }
        WebSocketServer.shared.start()
        BLEAdvertiser.shared.start()
    }

    /// Register the app to launch automatically at login (macOS 13+).
    private func registerLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
                NSLog("Registered as login item")
            }
        } catch {
            NSLog("Failed to register login item: \(error.localizedDescription)")
        }
    }

    @objc func handleOpenPairing() {
        DispatchQueue.main.async { [weak self] in
            if let existing = self?.pairingWindow, existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "Bridge"
            window.contentView = NSHostingView(rootView: PairingWindow())
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self?.pairingWindow = window
        }
    }
}
