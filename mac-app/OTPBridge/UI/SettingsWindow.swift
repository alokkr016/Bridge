import SwiftUI

let openSettingsNotification = Notification.Name("openSettings")

/// Feature on/off switches. Each toggle is enforced where data actually moves
/// (see FeatureSettings), so turning one off stops the traffic, not just the UI.
struct SettingsWindow: View {

    @ObservedObject private var settings = FeatureSettings.shared
    @ObservedObject private var updater = UpdaterManager.shared
    @State private var chimeEnabled = SoundManager.shared.isEnabled
    @State private var confirmForget = false
    @State private var confirmClear = false
    @State private var showPairing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    featuresSection
                    Divider()
                    alertsSection
                    Divider()
                    deviceSection
                    Divider()
                    updatesSection
                    Divider()
                    dangerSection
                    footerNote
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showPairing) {
            PairingWindow()
        }
        .alert("Forget this phone?", isPresented: $confirmForget) {
            Button("Forget", role: .destructive) {
                PairingManager.shared.clearPairing()
                WebSocketServer.shared.stop()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You’ll need to scan the QR code again to reconnect.")
        }
        .alert("Clear OTP history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) {
                StorageManager.shared.clearAllOTPs()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            Text("Bridge Settings")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Features")

            toggleRow(
                title: "Clipboard Sync",
                subtitle: "Copy on either device and paste on the other.",
                icon: "doc.on.clipboard",
                isOn: $settings.clipboardSyncEnabled
            )

            toggleRow(
                title: "Call Handling",
                subtitle: "Show incoming calls and answer or decline from the Mac.",
                icon: "phone",
                isOn: $settings.callHandlingEnabled
            )

            toggleRow(
                title: "OTP Forwarding",
                subtitle: "Receive one-time codes from your phone.",
                icon: "key",
                isOn: $settings.otpForwardingEnabled
            )
        }
    }

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Alerts")
            toggleRow(
                title: "Chime on OTP",
                subtitle: "Play a sound when a code arrives.",
                icon: chimeEnabled ? "speaker.wave.2" : "speaker.slash",
                isOn: Binding(
                    get: { chimeEnabled },
                    set: { newValue in
                        chimeEnabled = newValue
                        SoundManager.shared.isEnabled = newValue
                        if newValue { SoundManager.shared.play() }
                    }
                )
            )
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Device")
            settingsButton(title: "Connection Dashboard", icon: "network") {
                NotificationCenter.default.post(name: openDashboardNotification, object: nil)
            }
            settingsButton(title: "Pair New Device…", icon: "qrcode") {
                showPairing = true
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Updates")
            if updater.updateAvailable {
                settingsButton(
                    title: updater.isDownloading ? "Downloading…" : "Install Update (\(updater.latestVersion))",
                    icon: "arrow.down.circle"
                ) {
                    updater.downloadAndInstallUpdate()
                }
                .disabled(updater.isDownloading)
            } else {
                settingsButton(
                    title: updater.isChecking ? "Checking…" : (updater.statusMessage.isEmpty ? "Check for Updates" : updater.statusMessage),
                    icon: "arrow.triangle.2.circlepath"
                ) {
                    updater.checkForUpdates(manually: true)
                }
                .disabled(updater.isChecking)
            }
            Text("v\(UpdaterManager.currentVersion)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Danger zone")
            if PairingManager.shared.isPaired() {
                settingsButton(title: "Forget Device", icon: "minus.circle", destructive: true) {
                    confirmForget = true
                }
            }
            settingsButton(title: "Clear History", icon: "trash", destructive: true) {
                confirmClear = true
            }
        }
    }

    private func settingsButton(title: String, icon: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(destructive ? .red : .secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(destructive ? .red : .primary)
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footerNote: some View {
        Text("Turning a feature off stops that data from being sent or received. "
             + "Settings apply immediately and persist across restarts.")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.5)
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        icon: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : .secondary)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
    }
}
