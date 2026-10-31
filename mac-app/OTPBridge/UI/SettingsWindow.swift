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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(.system(size: 28, weight: .semibold))
                    .padding(.bottom, 22)

                sectionLabel("Features")
                toggleRow(
                    title: "Clipboard",
                    subtitle: "Copy on either device and paste on the other.",
                    isOn: $settings.clipboardSyncEnabled
                )
                toggleRow(
                    title: "Calls",
                    subtitle: "Show incoming calls and answer or decline from the Mac.",
                    isOn: $settings.callHandlingEnabled
                )
                toggleRow(
                    title: "Codes",
                    subtitle: "Receive one-time codes from your phone.",
                    isOn: $settings.otpForwardingEnabled
                )

                sectionLabel("Alerts")
                    .padding(.top, 18)
                toggleRow(
                    title: "Chime",
                    subtitle: "Play a sound when a code arrives.",
                    isOn: Binding(
                        get: { chimeEnabled },
                        set: { newValue in
                            chimeEnabled = newValue
                            SoundManager.shared.isEnabled = newValue
                            if newValue { SoundManager.shared.play() }
                        }
                    )
                )

                sectionLabel("This Mac")
                    .padding(.top, 18)
                actionRow("Connection") {
                    NotificationCenter.default.post(name: openDashboardNotification, object: nil)
                }
                actionRow("Pair a device") {
                    showPairing = true
                }

                sectionLabel("Updates")
                    .padding(.top, 18)
                if updater.updateAvailable {
                    actionRow(updater.isDownloading ? "Downloading…" : "Install \(updater.latestVersion)") {
                        updater.downloadAndInstallUpdate()
                    }
                    .disabled(updater.isDownloading)
                } else {
                    actionRow(updater.isChecking ? "Checking…" : (updater.statusMessage.isEmpty ? "Check for updates" : updater.statusMessage)) {
                        updater.checkForUpdates(manually: true)
                    }
                    .disabled(updater.isChecking)
                }
                infoLine("Version", value: UpdaterManager.currentVersion)
                Text("Made with ♥ by [Alok](https://github.com/alokkr016)")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)
                    .padding(.vertical, 12)

                sectionLabel("Danger")
                    .padding(.top, 18)
                if PairingManager.shared.isPaired() {
                    actionRow("Forget this phone", destructive: true) {
                        confirmForget = true
                    }
                }
                actionRow("Clear history", destructive: true) {
                    confirmClear = true
                }

                Text("Turning a feature off stops that data from being sent or received. Settings apply immediately and persist across restarts.")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
            }
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 28)
        }
        .frame(width: 440, height: 620)
        .background(Brand.canvas)
        .foregroundStyle(Brand.ink)
        .preferredColorScheme(.dark)
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

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .foregroundStyle(Brand.muted)
            .padding(.bottom, 4)
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.white)
                    .controlSize(.small)
                    .accessibilityLabel(title)
            }
            .padding(.vertical, 12)
            Rectangle().fill(Brand.line).frame(height: 1)
        }
    }

    private func actionRow(_ title: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(destructive ? Color.red : Brand.ink)
                    Spacer()
                }
                .padding(.vertical, 14)
                Rectangle().fill(Brand.line).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoLine(_ label: String, value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 15))
                    .foregroundStyle(Brand.muted)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 14)
            Rectangle().fill(Brand.line).frame(height: 1)
        }
    }
}
