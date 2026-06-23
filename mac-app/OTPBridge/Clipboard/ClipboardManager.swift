import Cocoa

class ClipboardManager {

    static let shared = ClipboardManager()

    private var lastCopiedOTP: String?
    private var copyTimer: Timer?

    private init() {}

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastCopiedOTP = text

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.lastCopiedOTP = nil
        }
    }

    func getLastCopiedOTP() -> String? {
        return lastCopiedOTP
    }
}
