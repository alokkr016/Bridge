import SwiftUI

struct PairingWindow: View {
    @State private var pairingURL: String?
    @State private var qrImage: NSImage?
    @State private var isListening = false
    @State private var isConnected = false
    @State private var pairedDeviceId: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(isConnected ? .green : .blue)

            Text(isConnected ? "Device Connected!" : "Pair Your Android Device")
                .font(.title2)
                .fontWeight(.bold)

            if isConnected {
                Text("Paired with Android device")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let id = pairedDeviceId {
                    Text("Device: \(String(id.prefix(8)))...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Label("Ready to receive OTPs", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else {
                Text("Open Bridge on your Android phone\nand tap 'Pair with Mac'")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let img = qrImage {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 300, height: 300)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                } else {
                    ProgressView()
                        .frame(width: 300, height: 300)
                }

                if isListening {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for connection...")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Button(action: startPairing) {
                Label(isConnected ? "Done" : (isListening ? "Listening..." : "Start Pairing"), systemImage: isConnected ? "checkmark" : "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(isListening && !isConnected)
        }
        .padding(40)
        .frame(width: 400, height: 520)
        .onAppear {
            startPairing()
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if WebSocketServer.shared.isConnected && !self.isConnected {
                    DispatchQueue.main.async {
                        self.isConnected = true
                    }
                }
            }
        }
    }

    private func startPairing() {
        if isConnected { return }
        pairingURL = PairingManager.shared.getPairingURL()
        if let url = pairingURL {
            qrImage = QRCodeGenerator.generate(from: url)
        }

        WebSocketServer.shared.onHandshakeReceived = { deviceId, publicKey in
            DispatchQueue.main.async {
                self.isConnected = true
                self.pairedDeviceId = deviceId
            }
        }

        WebSocketServer.shared.start()
        isListening = true
    }
}
