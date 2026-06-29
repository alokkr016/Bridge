import SwiftUI
import ServiceManagement

let openPairingNotification = Notification.Name("openPairingWindow")
let otpReceivedNotification = Notification.Name("otpReceived")
let connectionChangedNotification = Notification.Name("connectionChanged")

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
    private var dashboardWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestPermission()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenPairing),
            name: openPairingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenDashboard),
            name: openDashboardNotification,
            object: nil
        )
        registerLoginItem()
        if PairingManager.shared.isPaired() {
            WebSocketServer.shared.restoreSharedSecret()
        }

        // Wire OTP and connection callbacks at the app level so they fire
        // even when the menu bar popover is closed.
        WebSocketServer.shared.onOTPReceived = { sender, otp, company, timestamp in
            DispatchQueue.main.async {
                StorageManager.shared.saveOTP(sender: sender, otp: otp, company: company)
                NotificationManager.shared.showOTPNotification(sender: company ?? sender, otp: otp)
                ClipboardManager.shared.copyToClipboard(otp)
                SoundManager.shared.play()
                NotificationCenter.default.post(
                    name: otpReceivedNotification,
                    object: nil,
                    userInfo: ["sender": sender, "otp": otp, "company": company as Any, "timestamp": timestamp]
                )
            }
        }

        WebSocketServer.shared.onConnectionChanged = { connected in
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: connectionChangedNotification,
                    object: nil,
                    userInfo: ["connected": connected]
                )
            }
        }

        WebSocketServer.shared.start()
        BLEAdvertiser.shared.start()
        UpdaterManager.shared.checkForUpdates(manually: false)
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

    @objc func handleOpenDashboard() {
        DispatchQueue.main.async { [weak self] in
            if let existing = self?.dashboardWindow, existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.title = "Bridge — Dashboard"
            window.contentView = NSHostingView(rootView: ConnectionDashboard())
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self?.dashboardWindow = window
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
