import Foundation
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func showOTPNotification(sender: String, otp: String) {
        let content = UNMutableNotificationContent()
        content.title = "OTP from \(sender)"
        content.body = "\(otp) — copied to clipboard"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func showClipboardNotification(preview: String) {
        let content = UNMutableNotificationContent()
        content.title = "Clipboard from iPhone"
        let short = preview.count > 40 ? String(preview.prefix(40)) + "…" : preview
        content.body = short
        content.sound = .default
        let request = UNNotificationRequest(identifier: "clipboard-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let otp = response.notification.request.content.body
        if let otpCode = otp.components(separatedBy: ": ").last?.components(separatedBy: "\n").first {
            ClipboardManager.shared.copyToClipboard(otpCode)
        }
        completionHandler()
    }
}
