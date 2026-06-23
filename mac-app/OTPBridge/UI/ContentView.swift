import SwiftUI

struct ContentView: View {
    @State private var isPaired = PairingManager.shared.isPaired()
    @State private var showQRCode = false
    @State private var pairingURL: String?

    var body: some View {
        VStack(spacing: 20) {
            headerSection
            connectionSection
            pairingSection
            Spacer()
        }
        .padding(20)
        .frame(width: 400, height: 500)
        .onAppear {
            isPaired = PairingManager.shared.isPaired()
            if isPaired {
                WebSocketServer.shared.restoreSharedSecret()
                WebSocketServer.shared.start()
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            Text("OTP Bridge")
                .font(.title)
                .fontWeight(.bold)
            Text("Sync OTPs from Android to Mac")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "wifi")
                    Text("Connection Status")
                        .fontWeight(.medium)
                    Spacer()
                }
                if isPaired {
                    Label("Paired with Android device", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Unpair Device") {
                        PairingManager.shared.clearPairing()
                        WebSocketServer.shared.stop()
                        isPaired = false
                    }
                    .foregroundStyle(.red)
                } else {
                    Label("Not paired", systemImage: "xmark.circle")
                        .foregroundStyle(.orange)
                }
            }
            .padding(8)
        }
    }

    private var pairingSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                if showQRCode, let url = pairingURL {
                    if let qrImage = QRCodeGenerator.generate(from: url) {
                        Image(nsImage: qrImage)
                            .resizable()
                            .frame(width: 200, height: 200)
                    }
                    Text("Scan this QR code with your Android app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Done") {
                        showQRCode = false
                    }
                } else {
                    Button(action: {
                        pairingURL = PairingManager.shared.getPairingURL()
                        showQRCode = true
                        WebSocketServer.shared.start()
                    }) {
                        Label("Pair New Device", systemImage: "qrcode")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .disabled(isPaired)
                }
            }
            .padding(8)
        }
    }
}
