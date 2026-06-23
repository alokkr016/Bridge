import SwiftUI

struct PairingView: View {
    @State private var pairingURL: String?
    @State private var isListening = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Pair Your Android Device")
                .font(.title2)
                .fontWeight(.bold)

            Text("Open Bridge on your Android phone and scan this QR code")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let url = pairingURL, let qrImage = QRCodeGenerator.generate(from: url) {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 250, height: 250)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
            } else {
                ProgressView()
                    .frame(width: 250, height: 250)
            }

            if isListening {
                Label("Waiting for Android device...", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.blue)
            }

            Button("Start Pairing") {
                pairingURL = PairingManager.shared.getPairingURL()
                WebSocketServer.shared.start()
                isListening = true
            }
            .controlSize(.large)
            .disabled(isListening)
        }
        .padding(30)
        .frame(width: 400, height: 500)
    }
}
