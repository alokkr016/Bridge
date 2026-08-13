import SwiftUI

let openSettingsNotification = Notification.Name("openSettings")

/// Feature on/off switches. Each toggle is enforced where data actually moves
/// (see FeatureSettings), so turning one off stops the traffic, not just the UI.
struct SettingsWindow: View {

    @ObservedObject private var settings = FeatureSettings.shared
    @State private var chimeEnabled = SoundManager.shared.isEnabled

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
                    footerNote
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
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
