import SwiftUI
import UIKit

struct SettingsView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var confirmUnpair = false

    var body: some View {
        NavigationStack {
            List {
                Section("This iPad") {
                    LabeledContent("Name", value: UIDevice.current.name)
                    LabeledContent("Address", value: LocalAddress.ipv4() ?? "—")
                }

                Section("Paired phone") {
                    if let device = PairingManager.shared.getPairedDevice() {
                        LabeledContent("Device", value: String(device.deviceId.prefix(8)) + "…")
                        LabeledContent("Phone IP", value: device.ip)
                    } else {
                        Text("Not paired").foregroundStyle(.secondary)
                    }
                }

                Section("Staying connected") {
                    Text("Bridge keeps working when you go to the Home screen or switch apps. "
                         + "Don’t swipe Bridge away in the app switcher — iPadOS won’t let it "
                         + "relaunch to receive codes after that.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    Text("Codes travel over your local Wi-Fi (and Bluetooth when this iPad is "
                         + "locked), encrypted with X25519 key exchange and AES-256-GCM. "
                         + "Nothing goes to a server.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Made with ♥ by [Alok](https://github.com/alokkr016)")
                        .font(.footnote)
                }

                if PairingManager.shared.isPaired() {
                    Section {
                        Button("Unpair Phone", role: .destructive) { confirmUnpair = true }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Unpair this phone?", isPresented: $confirmUnpair) {
                Button("Unpair", role: .destructive) {
                    PairingManager.shared.clearPairing()
                    OTPStore.shared.clear()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You’ll need to scan the pairing code again.")
            }
        }
    }
}
