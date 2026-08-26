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
            Divider()

            if !serverConnected {
                offlineBanner
                Divider()
            }

            if let otp = lastOTP {
                heroCard(otp)
            } else {
                emptyState
            }

            let rest = Array(recentOTPs.dropFirst().prefix(2))
            if !rest.isEmpty {
                Divider()
                recentSection(rest)
            }

            Divider()
            footer
        }
        .frame(width: 320)
        .background(.regularMaterial)
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text("Bridge")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(serverConnected ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 6, height: 6)
                Text(serverConnected ? "Live" : "Offline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(serverConnected ? .green : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(serverConnected ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1))
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text("Phone isn’t connected. If this persists after a Mac restart, open Pair New Device and scan the QR again.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.orange.opacity(0.08))
    }

    // MARK: - Hero card

    private func heroCard(_ item: OTPItem) -> some View {
        let isCopied = copiedOTP == item.otp

        return Button(action: { copyOTP(item.otp) }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    sourceAvatar(item.source, size: 18)
                    Text(item.source)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(relativeTime(item.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(grouped(item.otp))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.orange)
                        .monospacedDigit()
                    Spacer()
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isCopied ? .green : .secondary)
                }

                Text(isCopied ? "Copied" : "Click to copy")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isCopied ? .green : .secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Brand.indigo.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Brand.indigo.opacity(isCopied ? 0.45 : 0.22), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .opacity(0.9)
            Text("Waiting for a code")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("OTPs from your phone appear here and copy automatically.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 14)
    }

    // MARK: - Recent

    private func recentSection(_ items: [OTPItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RECENT")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 2)

            ForEach(items) { item in
                recentRow(item)
            }
        }
        .padding(.bottom, 6)
    }

    private func recentRow(_ item: OTPItem) -> some View {
        let isHovered = hoveredID == item.id
        let isCopied = copiedOTP == item.otp

        return Button(action: { copyOTP(item.otp) }) {
            HStack(spacing: 8) {
                sourceAvatar(item.source, size: 16)
                Text(grouped(item.otp))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: 78, alignment: .leading)

                Text(item.source)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if isCopied {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                } else if isHovered {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text(relativeTime(item.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            if hovering { hoveredID = item.id }
            else if hoveredID == item.id { hoveredID = nil }
        }
    }

    private func sourceAvatar(_ source: String, size: CGFloat) -> some View {
        let letter = source.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
        return ZStack {
            Circle().fill(Brand.indigo.opacity(0.22))
            Text(letter)
                .font(.system(size: size * 0.62, weight: .bold))
                .foregroundStyle(Brand.indigo)
        }
        .frame(width: size + 6, height: size + 6)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(action: {
                NotificationCenter.default.post(name: openSettingsNotification, object: nil)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                    Text("Settings")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)

            Spacer()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

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


