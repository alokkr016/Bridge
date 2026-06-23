import Foundation
import Combine

@MainActor
class MenuBarState: ObservableObject {
    @Published var isConnected = false
    @Published var lastOTP: String?
    @Published var lastSender: String?
    @Published var recentOTPs: [(sender: String, otp: String, time: String)] = []

    private let storageManager = StorageManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupCallbacks()
        loadRecentOTPs()
    }

    private func setupCallbacks() {
        WebSocketServer.shared.onOTPReceived = { [weak self] sender, otp, timestamp in
            Task { @MainActor in
                self?.lastOTP = otp
                self?.lastSender = sender
                self?.loadRecentOTPs()
            }
        }

        WebSocketServer.shared.onConnectionChanged = { [weak self] connected in
            Task { @MainActor in
                self?.isConnected = connected
            }
        }
    }

    func loadRecentOTPs() {
        let otps = storageManager.getRecentOTPs(limit: 10)
        recentOTPs = otps.map { record in
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return (record.sender, record.otp, formatter.string(from: record.timestamp))
        }
        if let first = otps.first {
            lastOTP = first.otp
            lastSender = first.sender
        }
    }
}
