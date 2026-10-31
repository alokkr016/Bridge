import SwiftUI

struct OTPItem: Identifiable {
    let id = UUID()
    let sender: String
    let otp: String
    let company: String?
    let date: Date

    var source: String { company ?? sender }
}

struct MenuBarView: View {
    @State private var lastOTP: OTPItem?
    @State private var recentOTPs: [OTPItem] = []
    @State private var serverConnected = WebSocketServer.shared.isConnected
    @State private var copiedOTP: String?
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if !serverConnected {
                Text("Phone isn’t connected. If this persists after a Mac restart, open Settings and scan the QR again.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
            }

            if let otp = lastOTP {
                hero(otp)
            } else {
                emptyState
            }

            let rest = Array(recentOTPs.dropFirst().prefix(2))
            if !rest.isEmpty {
                hairline
                recentSection(rest)
            }

            hairline
            footer
        }
        .frame(width: 340)
        .background(Brand.canvas)
        .foregroundStyle(Brand.ink)
        .preferredColorScheme(.dark)
        .onAppear {
            loadRecentOTPs()
            setupCallbacks()
        }
        .onReceive(NotificationCenter.default.publisher(for: otpReceivedNotification)) { note in
            if let otp = note.userInfo?["otp"] as? String {
                withAnimation { copiedOTP = otp }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if copiedOTP == otp { withAnimation { copiedOTP = nil } }
                }
                loadRecentOTPs()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: connectionChangedNotification)) { note in
            if let connected = note.userInfo?["connected"] as? Bool {
                serverConnected = connected
            }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Brand.line)
            .frame(height: 1)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bridge")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Text(serverConnected ? "Live" : "Offline")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)
            }
            Text("Made with ♥ by [Alok](https://github.com/alokkr016)")
                .font(.system(size: 12))
                .foregroundStyle(Brand.muted)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func hero(_ item: OTPItem) -> some View {
        let isCopied = copiedOTP == item.otp
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(item.source)  ·  \(relativeTime(item.date))")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                Button(action: { copyOTP(item.otp) }) {
                    Text(grouped(item.otp))
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(Brand.ink)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button(action: { copyOTP(item.otp) }) {
                Text(isCopied ? "Copied" : "Copy")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
        .animation(.easeOut(duration: 0.15), value: isCopied)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waiting for a code")
                .font(.system(size: 28, weight: .semibold))
            Text("Codes from your phone show up here and copy to the clipboard.")
                .font(.system(size: 13))
                .foregroundStyle(Brand.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentSection(_ items: [OTPItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                recentRow(item)
            }
        }
        .padding(.vertical, 6)
    }

    private func recentRow(_ item: OTPItem) -> some View {
        let isHovered = hoveredID == item.id
        let isCopied = copiedOTP == item.otp
        return Button(action: { copyOTP(item.otp) }) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(grouped(item.otp))
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Brand.ink)
                Text(isCopied ? "Copied" : item.source)
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(relativeTime(item.date))
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isHovered ? Color.white.opacity(0.04) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredID = item.id }
            else if hoveredID == item.id { hoveredID = nil }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: {
                NotificationCenter.default.post(name: openSettingsNotification, object: nil)
            }) {
                Text("Settings")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.ink)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func grouped(_ otp: String) -> String {
        guard otp.count == 6, otp.allSatisfy(\.isNumber) else { return otp }
        let mid = otp.index(otp.startIndex, offsetBy: 3)
        return "\(otp[otp.startIndex..<mid]) \(otp[mid...])"
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func copyOTP(_ otp: String) {
        ClipboardManager.shared.copyToClipboard(otp)
        withAnimation { copiedOTP = otp }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedOTP == otp { withAnimation { copiedOTP = nil } }
        }
    }

    private func loadRecentOTPs() {
        let otps = StorageManager.shared.getRecentOTPs(limit: 3)
        recentOTPs = otps.map { OTPItem(sender: $0.sender, otp: $0.otp, company: $0.company, date: $0.timestamp) }
        lastOTP = recentOTPs.first
    }

    private func setupCallbacks() {
        serverConnected = WebSocketServer.shared.isConnected
    }
}
