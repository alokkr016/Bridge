import Foundation
import UserNotifications

/// Local notifications for OTPs and clipboard pushes. No remote/APNs — everything
/// stays on the LAN.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                NSLog("[BridgePad] Notification permission error: \(error)")
            } else {
                NSLog("[BridgePad] Notifications granted: \(granted)")
            }
        }
    }

    /// Groups a numeric code for readability: 484711 → "484 711".
    static func grouped(_ code: String) -> String {
        guard code.count == 6, code.allSatisfy(\.isNumber) else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<mid]) \(code[mid...])"
    }

    func showOTPNotification(sender: String, otp: String) {
        let content = UNMutableNotificationContent()
        content.title = sender
        content.body = "\(Self.grouped(otp)) — copied"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "otp-\(otp)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func showClipboardNotification(preview: String) {
        let content = UNMutableNotificationContent()
        content.title = "Clipboard from phone"
        content.body = preview.count > 80 ? String(preview.prefix(80)) + "…" : preview
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: "clipboard-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Show banners even while Bridge is foregrounded.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
