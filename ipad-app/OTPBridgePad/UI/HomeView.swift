import SwiftUI

struct HomeView: View {

    @ObservedObject private var store = OTPStore.shared
    @State private var isConnected = false
    @State private var copiedOTP: String?
    @State private var showPairing = false
    @State private var showSettings = false
    @State private var isPaired = PairingManager.shared.isPaired()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    statusChip

                    if !isPaired {
                        pairCTA
                    } else if let latest = store.latest {
                        heroCard(latest)
                        if !store.recent.isEmpty {
                            recentSection
                        }
                    } else {
                        waitingState
                    }
                }
                .padding(28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Bridge")
            .safeAreaInset(edge: .bottom) {
                Text("Made with ♥ by [Alok](https://github.com/alokkr016)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showPairing, onDismiss: refreshPaired) {
                PairingView()
            }
            .sheet(isPresented: $showSettings, onDismiss: refreshPaired) {
                SettingsView()
            }
        }
        .onAppear { syncConnection() }
        .onReceive(NotificationCenter.default.publisher(for: TCPServer.connectionChanged)) { note in
            if let connected = note.userInfo?["connected"] as? Bool {
                isConnected = connected
                if connected { refreshPaired() }
            }
        }
    }

    private var statusChip: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isConnected ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 8, height: 8)
            Text(isConnected ? "Live" : "Offline")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isConnected ? .green : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(isConnected ? Color.green.opacity(0.12) : Color.secondary.opacity(0.12))
        )
    }

    private var pairCTA: some View {
        VStack(spacing: 14) {
            Image(systemName: "qrcode")
                .font(.system(size: 44))
                .foregroundStyle(Brand.indigo)
            Text("Pair with your phone")
                .font(.title3.weight(.semibold))
            Text("Codes from your phone will copy to this iPad automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Show Pairing Code") { showPairing = true }
                .buttonStyle(.borderedProminent)
                .tint(Brand.indigo)
                .controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Brand.indigo.opacity(0.08)))
    }

    private func heroCard(_ item: OTPItem) -> some View {
        let isCopied = copiedOTP == item.otp
        return Button { copy(item.otp) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(item.source)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(relativeTime(item.date))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(NotificationManager.grouped(item.otp))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(Brand.orange)
                        .monospacedDigit()
                    Spacer()
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 22))
                        .foregroundStyle(isCopied ? .green : .secondary)
                }
                Text(isCopied ? "Copied" : "Tap to copy")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isCopied ? .green : .secondary)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Brand.indigo.opacity(0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Brand.indigo.opacity(isCopied ? 0.45 : 0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.5)
            ForEach(store.recent) { item in
                Button { copy(item.otp) } label: {
                    HStack(spacing: 12) {
                        Text(NotificationManager.grouped(item.otp))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(item.source)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(relativeTime(item.date))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                        Image(systemName: copiedOTP == item.otp ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(copiedOTP == item.otp ? .green : .secondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var waitingState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)
            Text("Waiting for a code")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("OTPs from your phone appear here and copy automatically.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func copy(_ otp: String) {
        ClipboardManager.shared.copyToClipboard(otp)
        withAnimation { copiedOTP = otp }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedOTP == otp { withAnimation { copiedOTP = nil } }
        }
    }

    private func refreshPaired() {
        isPaired = PairingManager.shared.isPaired()
    }

    private func syncConnection() {
        isConnected = TCPServer.shared.isConnected
        if isConnected { refreshPaired() }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86_400)d ago"
    }
}
