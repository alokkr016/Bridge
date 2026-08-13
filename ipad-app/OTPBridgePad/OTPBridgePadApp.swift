import SwiftUI

@main
struct OTPBridgePadApp: App {

    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationManager.shared.requestPermission()
        TCPServer.shared.restoreSharedSecret()
        wireCallbacks()
        TCPServer.shared.start()
        BLECentral.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // NWListener may have been suspended in the background.
                        TCPServer.shared.start()
                        UIApplication.shared.isIdleTimerDisabled = true
                        // Announce our IP only while nothing is connected — the
                        // phone only listens for this when it's hunting an IP.
                        if !TCPServer.shared.isConnected {
                            LanBeacon.shared.start()
                        }
                    case .background, .inactive:
                        // Deliberately leave BLE central running — it is the
                        // background delivery path. Do not tear it down.
                        // The beacon, however, is pointless in the background:
                        // iPadOS suspends our sockets, so stop burning the timer.
                        LanBeacon.shared.stop()
                        UIApplication.shared.isIdleTimerDisabled = false
                    @unknown default:
                        break
                    }
                }
        }
    }

    /// Both transports funnel into the same handling: copy, notify, store.
    private func wireCallbacks() {
        TCPServer.shared.onOTPReceived = { sender, otp, company, timestamp in
            Self.handleOTP(sender: sender, otp: otp, company: company,
                           date: Date(timeIntervalSince1970: timestamp))
        }

        TCPServer.shared.onClipboardReceived = { text in
            ClipboardManager.shared.receiveFromPhone(text)
        }

        // The beacon exists purely to be found. Once a phone is connected there
        // is nothing to announce; if it drops, start announcing again so the
        // phone can recover a changed IP without re-pairing.
        // Observes the notification rather than assigning onConnectionChanged,
        // which HomeView also owns.
        NotificationCenter.default.addObserver(
            forName: TCPServer.connectionChanged,
            object: nil,
            queue: .main
        ) { note in
            let connected = note.userInfo?["connected"] as? Bool ?? false
            if connected {
                LanBeacon.shared.stop()
            } else {
                LanBeacon.shared.start()
            }
        }

        BLECentral.shared.onOTPPayload = { json in
            guard (json["type"] as? String) == "otp" else { return }
            let sender = json["sender"] as? String ?? "Unknown"
            let otp = json["otp"] as? String ?? ""
            let company = json["company"] as? String
            let rawTs = json["timestamp"] as? TimeInterval ?? (Date().timeIntervalSince1970 * 1000)
            let seconds = rawTs > 1_000_000_000_000 ? rawTs / 1000.0 : rawTs
            Self.handleOTP(sender: sender, otp: otp, company: company,
                           date: Date(timeIntervalSince1970: seconds))
        }
    }

    private static func handleOTP(sender: String, otp: String, company: String?, date: Date) {
        guard !otp.isEmpty else { return }
        ClipboardManager.shared.copyToClipboard(otp)
        NotificationManager.shared.showOTPNotification(sender: company ?? sender, otp: otp)
        OTPStore.shared.add(sender: sender, otp: otp, company: company, date: date)
    }
}
