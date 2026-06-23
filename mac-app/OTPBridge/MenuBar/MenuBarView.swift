import SwiftUI

struct MenuBarView: View {
    @State private var isConnected = false
    @State private var lastOTP: String?
    @State private var lastSender: String?
    @State private var recentOTPs: [(sender: String, otp: String, time: String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isConnected ? "Connected" : "Disconnected")
                    .font(.caption)
                Spacer()
            }

            Divider()

            if let otp = lastOTP, let sender = lastSender {
                Text("Last OTP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(otp)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    Text(sender)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Copied to clipboard")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text("No OTPs received")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if !recentOTPs.isEmpty {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(recentOTPs.prefix(5).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.sender)
                            .font(.caption)
                            .frame(width: 50, alignment: .leading)
                        Text(item.otp)
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Text(item.time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            Button("Pair New Device...") {
                NotificationCenter.default.post(name: openPairingNotification, object: nil)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            loadRecentOTPs()
            setupCallbacks()
        }
    }

    private func loadRecentOTPs() {
        let otps = StorageManager.shared.getRecentOTPs(limit: 10)
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

    private func setupCallbacks() {
        WebSocketServer.shared.onOTPReceived = { sender, otp, timestamp in
            DispatchQueue.main.async {
                ClipboardManager.shared.copyToClipboard(otp)
                NotificationManager.shared.showOTPNotification(sender: sender, otp: otp)
                StorageManager.shared.saveOTP(sender: sender, otp: otp)
                lastOTP = otp
                lastSender = sender
                loadRecentOTPs()
            }
        }
        WebSocketServer.shared.onConnectionChanged = { connected in
            DispatchQueue.main.async {
                isConnected = connected
            }
        }
    }
}
