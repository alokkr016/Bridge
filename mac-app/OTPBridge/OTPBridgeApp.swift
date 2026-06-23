import SwiftUI

let openPairingNotification = Notification.Name("openPairingWindow")

@main
struct OTPBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            Image(systemName: "key.fill")
        }
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
        if PairingManager.shared.isPaired() {
            WebSocketServer.shared.restoreSharedSecret()
            WebSocketServer.shared.start()
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
            window.title = "OTP Bridge Pairing"
            window.contentView = NSHostingView(rootView: PairingWindow())
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self?.pairingWindow = window
        }
    }
}
