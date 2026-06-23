import SwiftUI

struct StatusView: View {
    @State private var isConnected = false
    @State private var lastOTP: String?
    @State private var lastSender: String?
    @State private var lastTimestamp: Date?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text(isConnected ? "Connected to Android" : "Disconnected")
                    .font(.headline)
                Spacer()
            }

            Divider()

            if let otp = lastOTP, let sender = lastSender {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest OTP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(otp)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(sender)
                                .font(.subheadline)
                            if let ts = lastTimestamp {
                                Text(ts, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color.primary.opacity(0.05))
                .cornerRadius(12)
            }
        }
        .padding()
    }
}
