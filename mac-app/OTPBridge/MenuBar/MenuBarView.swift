import SwiftUI

struct OTPItem: Identifiable {
    let id = UUID()
    let sender: String
    let otp: String
    let company: String?
    let date: Date

    /// What to show as the source label — friendly company name if known, else raw sender.
    var source: String { company ?? sender }
}

struct MenuBarView: View {
    @ObservedObject var updater = UpdaterManager.shared
    @State private var lastOTP: OTPItem?
    @State private var recentOTPs: [OTPItem] = []
    @State private var serverConnected = WebSocketServer.shared.isConnected
    @State private var copiedOTP: String?
    @State private var hoveredID: UUID?
    @State private var chimeEnabled = SoundManager.shared.isEnabled
    @State private var callsEnabled = CallHandling.enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let otp = lastOTP {
                heroCard(otp)
            } else {
                emptyState
            }

            let rest = Array(recentOTPs.dropFirst().prefix(6))
            if !rest.isEmpty {
                Divider()
                recentSection(rest)
            }

            Divider()
            footer
        }
        .frame(width: 300)
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
        HStack(spacing: 7) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("Bridge")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(serverConnected ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)
                Text(serverConnected ? "Connected" : "Offline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(serverConnected ? .green : .secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(serverConnected ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1))
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Hero card

    private func heroCard(_ item: OTPItem) -> some View {
        let isCopied = copiedOTP == item.otp

        return Button(action: { copyOTP(item.otp) }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.blue)
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
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .monospacedDigit()
                    Spacer()
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isCopied ? .green : .secondary)
                }

                Text(isCopied ? "Copied to clipboard" : "Click to copy")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isCopied ? .green : .secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.blue.opacity(isCopied ? 0.4 : 0.15), lineWidth: 1)
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
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No OTPs yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Codes from your phone appear here")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 14)
    }

    // MARK: - Recent

    private func recentSection(_ items: [OTPItem]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
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
            HStack(spacing: 10) {
                Text(grouped(item.otp))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: 84, alignment: .leading)

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

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            // Section 1: Dashboard & Sound
            footerButton(title: "Connection Dashboard", icon: "network") {
                NotificationCenter.default.post(name: openDashboardNotification, object: nil)
            }
            chimeToggleRow
            callToggleRow
            
            Divider().padding(.horizontal, 8).padding(.vertical, 4)
            
            // Section 2: Connection & Updates
            footerButton(title: "Pair New Device…", icon: "qrcode") {
                NotificationCenter.default.post(name: openPairingNotification, object: nil)
            }
            
            if updater.updateAvailable {
                footerButton(title: updater.isDownloading ? "Downloading update..." : "Install Update (\(updater.latestVersion))", icon: "arrow.down.circle") {
                    updater.downloadAndInstallUpdate()
                }
                .disabled(updater.isDownloading)
            } else {
                footerButton(title: updater.isChecking ? "Checking for updates..." : (updater.statusMessage.isEmpty ? "Check for Updates…" : updater.statusMessage), icon: "arrow.triangle.2.circlepath") {
                    updater.checkForUpdates(manually: true)
                }
                .disabled(updater.isChecking)
            }
            
            if PairingManager.shared.isPaired() || !recentOTPs.isEmpty {
                Divider().padding(.horizontal, 8).padding(.vertical, 4)
            }
            
            // Section 3: Destructive actions
            if PairingManager.shared.isPaired() {
                footerButton(title: "Forget Device", icon: "minus.circle", destructive: true) {
                    PairingManager.shared.clearPairing()
                    WebSocketServer.shared.stop()
                    recentOTPs = []
                    lastOTP = nil
                }
            }
            if !recentOTPs.isEmpty {
                footerButton(title: "Clear History", icon: "trash", destructive: true) {
                    StorageManager.shared.clearAllOTPs()
                    recentOTPs = []
                    lastOTP = nil
                }
            }
            
            Divider().padding(.horizontal, 8).padding(.vertical, 4)
            
            // Section 4: Version & Quit
            HStack {
                Text("v\(UpdaterManager.currentVersion)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 18)
                Spacer()
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "power")
                            .font(.system(size: 10))
                        Text("Quit Bridge")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
            .padding(.vertical, 4)

            Text("Made with ♥ by [Alok](https://github.com/alokkr016)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
        }
        .padding(.vertical, 5)
    }

    private var chimeToggleRow: some View {
        Button(action: {
            chimeEnabled.toggle()
            SoundManager.shared.isEnabled = chimeEnabled
            if chimeEnabled { SoundManager.shared.play() }
        }) {
            HStack(spacing: 9) {
                Image(systemName: chimeEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 15)
                Text("Chime on OTP")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
                Text(chimeEnabled ? "On" : "Off")
                    .font(.system(size: 11))
                    .foregroundStyle(chimeEnabled ? Color.green : Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
        .padding(.horizontal, 8)
    }

    private var callToggleRow: some View {
        Button(action: {
            callsEnabled.toggle()
            CallHandling.enabled = callsEnabled
            if !callsEnabled {
                IncomingCallController.shared.handle(state: "idle", number: "", name: nil)
            }
        }) {
            HStack(spacing: 9) {
                Image(systemName: callsEnabled ? "phone.fill" : "phone.down.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 15)
                Text("Incoming Calls")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
                Text(callsEnabled ? "On" : "Off")
                    .font(.system(size: 11))
                    .foregroundStyle(callsEnabled ? Color.green : Color.secondary.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
        .padding(.horizontal, 8)
    }

    private func footerButton(title: String, icon: String, shortcut: String? = nil, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(destructive ? .red : .secondary)
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(destructive ? .red : .primary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle())
        .padding(.horizontal, 8)
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
        let otps = StorageManager.shared.getRecentOTPs(limit: 20)
        recentOTPs = otps.map { OTPItem(sender: $0.sender, otp: $0.otp, company: $0.company, date: $0.timestamp) }
        lastOTP = recentOTPs.first
    }

    private func setupCallbacks() {
        // Connection status initial sync — callbacks are wired in AppDelegate
        serverConnected = WebSocketServer.shared.isConnected
    }
}

struct HoverRowStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.06) : .clear)
            )
            .onHover { hovering = $0 }
    }
}
