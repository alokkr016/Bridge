import SwiftUI

struct MenuBarView: View {
    @State private var lastOTP: String?
    @State private var lastSender: String?
    @State private var recentOTPs: [(sender: String, otp: String, time: String)] = []
    @State private var serverConnected = WebSocketServer.shared.isConnected
    @State private var copiedOTP: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(serverConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(serverConnected ? "Connected" : "Disconnected")
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
                        .onTapGesture {
                            copyOTP(otp)
                        }
                    Text(sender)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if copiedOTP == otp {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Text("Click OTP to copy · Copied to clipboard")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text("No OTPs received")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if !recentOTPs.isEmpty {
                Text("Recent OTPs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(recentOTPs.prefix(10).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.sender)
                            .font(.caption)
                            .frame(width: 60, alignment: .leading)
                            .lineLimit(1)
                        Text(item.otp)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                            .onTapGesture {
                                copyOTP(item.otp)
                            }
                        Spacer()
                        if copiedOTP == item.otp {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption2)
                        }
                        Text(item.time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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
        .frame(width: 300)
        .onAppear {
            loadRecentOTPs()
            setupCallbacks()
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                serverConnected = WebSocketServer.shared.isConnected
            }
        }
    }

    private func copyOTP(_ otp: String) {
        ClipboardManager.shared.copyToClipboard(otp)
        copiedOTP = otp
        withAnimation {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if copiedOTP == otp {
                    copiedOTP = nil
                }
            }
        }
    }

    private func loadRecentOTPs() {
        let otps = StorageManager.shared.getRecentOTPs(limit: 20)
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
                copiedOTP = otp
                withAnimation {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedOTP = nil
                    }
                }
                loadRecentOTPs()
            }
        }
        WebSocketServer.shared.onConnectionChanged = { connected in
            DispatchQueue.main.async {
                serverConnected = connected
            }
        }
    }
}
