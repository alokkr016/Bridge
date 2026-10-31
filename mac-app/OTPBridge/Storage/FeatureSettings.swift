import Foundation
import Combine

/// User-facing on/off switches for Bridge's optional features.
///
/// Each flag is enforced at the point where data actually moves — not merely in
/// the UI — so turning a feature off stops the traffic rather than just hiding
/// it. Defaults are "on" so existing installs behave as before.
final class FeatureSettings: ObservableObject {

    static let shared = FeatureSettings()

    private enum Key {
        static let clipboardSync = "featureClipboardSyncEnabled"
        static let callHandling = "featureCallHandlingEnabled"
        static let otpForwarding = "featureOTPForwardingEnabled"
    }

    /// Two-way clipboard sync between Mac and Android.
    @Published var clipboardSyncEnabled: Bool {
        didSet {
            guard oldValue != clipboardSyncEnabled else { return }
            UserDefaults.standard.set(clipboardSyncEnabled, forKey: Key.clipboardSync)
            applyClipboardState()
        }
    }

    /// Incoming-call card, notification and answer/hangup control.
    @Published var callHandlingEnabled: Bool {
        didSet {
            guard oldValue != callHandlingEnabled else { return }
            UserDefaults.standard.set(callHandlingEnabled, forKey: Key.callHandling)
            if !callHandlingEnabled {
                // Tear down anything already on screen.
                IncomingCallController.shared.handle(state: "idle", number: "", name: nil)
            }
        }
    }

    /// OTP messages forwarded from the phone.
    @Published var otpForwardingEnabled: Bool {
        didSet {
            guard oldValue != otpForwardingEnabled else { return }
            UserDefaults.standard.set(otpForwardingEnabled, forKey: Key.otpForwarding)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        // `object(forKey:)` so a missing key defaults to true rather than false.
        clipboardSyncEnabled = defaults.object(forKey: Key.clipboardSync) as? Bool ?? true
        callHandlingEnabled = defaults.object(forKey: Key.callHandling) as? Bool ?? true
        otpForwardingEnabled = defaults.object(forKey: Key.otpForwarding) as? Bool ?? true
    }

    /// Starts or stops the pasteboard poll to match the current setting.
    /// Only syncs while a device is actually connected.
    func applyClipboardState() {
        DispatchQueue.main.async {
            if self.clipboardSyncEnabled && WebSocketServer.shared.isConnected {
                ClipboardManager.shared.startSyncing()
            } else {
                ClipboardManager.shared.stopSyncing()
            }
        }
    }
}
