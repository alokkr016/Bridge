import UIKit

/// Copies incoming OTPs / clipboard text to the iPad pasteboard.
///
/// Deliberately simpler than the Mac version: iPadOS gives no background
/// pasteboard-change callback and polling UIPasteboard triggers the "pasted from"
/// privacy banner, so iPad → phone sync is user-initiated only.
final class ClipboardManager {

    static let shared = ClipboardManager()

    /// Last value written locally, so text arriving from the phone is not echoed back.
    private var lastAppliedText: String?

    private init() {}

    func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        lastAppliedText = text
    }

    /// Applies clipboard text pushed from the phone.
    func receiveFromPhone(_ text: String) {
        guard text != lastAppliedText else { return }
        copyToClipboard(text)
        NotificationManager.shared.showClipboardNotification(preview: text)
    }

    /// Explicit user action — send whatever is on the iPad pasteboard to the phone.
    func sendCurrentClipboardToPhone() -> Bool {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return false }
        lastAppliedText = text
        TCPServer.shared.sendClipboard(text)
        return true
    }
}
