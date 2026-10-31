import Foundation
import Combine

struct OTPItem: Identifiable, Codable, Equatable {
    var id = UUID()
    let sender: String
    let otp: String
    let company: String?
    let date: Date

    var source: String { company ?? sender }
}

/// Keeps the last few OTPs in UserDefaults so they survive a background relaunch.
/// The UI shows 3 (latest hero + 2 recent) per the spec.
final class OTPStore: ObservableObject {

    static let shared = OTPStore()
    static let maxItems = 3

    @Published private(set) var items: [OTPItem] = []

    private let defaultsKey = "bridgepad.otpHistory"

    private init() {
        load()
    }

    var latest: OTPItem? { items.first }
    var recent: [OTPItem] { Array(items.dropFirst()) }

    func add(sender: String, otp: String, company: String?, date: Date = Date()) {
        let item = OTPItem(sender: sender, otp: otp, company: company, date: date)
        DispatchQueue.main.async {
            // Drop an identical code re-delivered over both TCP and BLE.
            if let first = self.items.first, first.otp == otp,
               date.timeIntervalSince(first.date) < 10 {
                return
            }
            self.items.insert(item, at: 0)
            if self.items.count > Self.maxItems {
                self.items = Array(self.items.prefix(Self.maxItems))
            }
            self.persist()
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.items = []
            self.persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([OTPItem].self, from: data) else { return }
        items = Array(decoded.prefix(Self.maxItems))
    }
}
