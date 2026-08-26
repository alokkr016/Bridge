import SwiftUI

struct PairingView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var qr: UIImage?
    @State private var isPaired = false

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
            TCPServer.shared.onNewPairingCompleted = nil
            PairingManager.shared.endPairingMode()
        }
    }

    private func refresh() {
        isPaired = false
        PairingManager.shared.beginPairingMode()
        TCPServer.shared.onNewPairingCompleted = { _, _ in
            isPaired = true
            PairingManager.shared.endPairingMode()
        }
        TCPServer.shared.start()
        if let url = PairingManager.shared.getPairingURL() {
            qr = QRCodeGenerator.generate(from: url)
            NSLog("[BridgePad] Pairing URL: \(url)")
        }
    }
}
