import Foundation
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    static let callCategory = "INCOMING_CALL"
    static let answerAction = "ANSWER_CALL"
    static let hangupAction = "HANGUP_CALL"
    static let callNotificationId = "incoming-call"

    func requestPermission() {
        let answer = UNNotificationAction(identifier: Self.answerAction, title: "Answer", options: [.foreground])
        let hangup = UNNotificationAction(identifier: Self.hangupAction, title: "Decline", options: [.destructive])
        let category = UNNotificationCategory(
            identifier: Self.callCategory,
            actions: [answer, hangup],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
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

    func showIncomingCall(name: String, number: String) {
        let content = UNMutableNotificationContent()
        let title = name.isEmpty ? (number.isEmpty ? "Incoming call" : number) : name
        content.title = title
        content.body = number.isEmpty || number == title ? "Incoming call on your phone" : number
        content.sound = .default
        content.categoryIdentifier = Self.callCategory
        let request = UNNotificationRequest(identifier: Self.callNotificationId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func clearIncomingCall() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.callNotificationId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.callNotificationId])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case Self.answerAction:
            IncomingCallController.shared.answer()
        case Self.hangupAction:
            IncomingCallController.shared.hangup()
        default:
            if response.notification.request.content.categoryIdentifier == Self.callCategory {
                break
            }
            let otp = response.notification.request.content.body
            if let otpCode = otp.components(separatedBy: ": ").last?.components(separatedBy: "\n").first {
                ClipboardManager.shared.copyToClipboard(otpCode)
            }
        }
        completionHandler()
    }
}
