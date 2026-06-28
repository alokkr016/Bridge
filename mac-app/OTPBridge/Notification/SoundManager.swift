import AppKit

class SoundManager {

    static let shared = SoundManager()

    private let defaultsKey = "otpChimeEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    private init() {}

    func play() {
        guard isEnabled else { return }
        NSSound(named: "Tink")?.play()
    }
}
