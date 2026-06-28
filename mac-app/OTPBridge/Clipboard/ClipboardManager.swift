import Cocoa

class ClipboardManager {

    static let shared = ClipboardManager()

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var pollTimer: Timer?
    private var lastSentString: String?

    private init() {}

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastSentString = text
        lastChangeCount = pasteboard.changeCount
    }

    func getLastCopiedOTP() -> String? { nil }

    /// Start watching the clipboard and sending changes to Android.
    func startSyncing() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopSyncing() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        // Don't echo back something we just received from Android
        guard text != lastSentString else { return }
        lastSentString = nil
        WebSocketServer.shared.sendClipboard(text)
    }

    /// Called when clipboard text arrives from Android — apply it locally.
    func receiveFromAndroid(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastSentString = text
        lastChangeCount = pasteboard.changeCount
        NotificationManager.shared.showClipboardNotification(preview: text)
    }
}
