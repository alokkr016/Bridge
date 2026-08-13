import SwiftUI

struct PairingView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var qr: UIImage?
    @State private var isPaired = PairingManager.shared.isPaired()

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if isPaired {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("Device Connected")
                        .font(.title2.weight(.bold))
                    Text("Codes will copy to this iPad as they arrive.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.indigo)
                        .controlSize(.large)
                } else {
                    Text("Scan with your phone")
                        .font(.title2.weight(.bold))

                    if let qr {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 320, height: 320)
                            .padding(18)
                            .background(Color.white)
                            .cornerRadius(18)
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    } else {
                        ProgressView().frame(width: 320, height: 320)
                    }

                    VStack(spacing: 6) {
                        Text("Keep Bridge open on this iPad (it can sit in the background).")
                        Text("On your phone: Settings → Add Mac or iPad → scan this code.")
                        Text("Codes copy to the clipboard as they arrive.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
            }
            .padding(36)
            .navigationTitle("Pairing")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear(perform: refresh)
        .onDisappear {
            // Close the pairing window's trust exception when the sheet goes away.
            PairingManager.shared.endPairingMode()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Flip to the success state as soon as the handshake lands.
            let paired = PairingManager.shared.isPaired()
            if paired != isPaired {
                isPaired = paired
                // Paired — stop accepting new devices.
                if paired { PairingManager.shared.endPairingMode() }
            }
        }
    }

    private func refresh() {
        isPaired = PairingManager.shared.isPaired()
        // Opens the only window in which an unknown device may pair.
        PairingManager.shared.beginPairingMode()
        TCPServer.shared.start()
        if let url = PairingManager.shared.getPairingURL() {
            qr = QRCodeGenerator.generate(from: url)
            NSLog("[BridgePad] Pairing URL: \(url)")
        }
    }
}
