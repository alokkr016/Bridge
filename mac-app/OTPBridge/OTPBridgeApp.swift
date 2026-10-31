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
    private var settingsWindow: NSWindow?

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings),
            name: openSettingsNotification,
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
                if !connected {
                    IncomingCallController.shared.handle(state: "idle", number: "", name: nil)
                }
            }
        }

        WebSocketServer.shared.onCallReceived = { state, number, name in
            DispatchQueue.main.async {
                IncomingCallController.shared.handle(state: state, number: number, name: name)
            }
        }

        WebSocketServer.shared.start()
        BLEAdvertiser.shared.start()
        LanBeacon.shared.start()
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
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            self?.styleAsCanvas(window)
            window.contentView = NSHostingView(rootView: ConnectionDashboard())
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self?.dashboardWindow = window
        }
    }

    @objc func handleOpenSettings() {
        DispatchQueue.main.async { [weak self] in
            if let existing = self?.settingsWindow, existing.isVisible {
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            self?.styleAsCanvas(window)
            window.contentView = NSHostingView(rootView: SettingsWindow())
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self?.settingsWindow = window
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
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 560),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            self?.styleAsCanvas(window)
            window.contentView = NSHostingView(rootView: PairingWindow())
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self?.pairingWindow = window
        }
    }

    private func styleAsCanvas(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .black
        window.isMovableByWindowBackground = true
    }
}
