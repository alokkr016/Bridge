import SwiftUI

struct PairingWindow: View {
    @Environment(\.dismiss) private var dismiss

    @State private var qrImage: NSImage?
    @State private var isListening = false
    @State private var didPair = false
    @State private var pairedDeviceId: String?
    @State private var hostWindow: NSWindow?
    @State private var macName = Host.current().localizedName ?? "This Mac"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(didPair ? "Paired" : "Pair")
                .font(.system(size: 28, weight: .semibold))
            Text(didPair ? "Codes from your phone will show in the menu." : macName)
                .font(.system(size: 13))
                .foregroundStyle(Brand.muted)
                .lineLimit(1)

            if didPair {
                VStack(alignment: .leading, spacing: 16) {
                    if let id = pairedDeviceId {
                        Text("Phone \(id.prefix(8))…")
                            .font(.system(size: 13))
                            .foregroundStyle(Brand.muted)
                    }
                    Button(action: close) {
                        Text("Done")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 18)
            } else {
                Text("On your phone open Bridge, then Add Mac or iPad, and scan this code.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                if let img = qrImage {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 220, height: 220)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    ProgressView()
                        .frame(width: 244, height: 244)
                        .frame(maxWidth: .infinity)
                }

                Text(isListening ? "Waiting for a scan" : "Preparing")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.muted)

                Button(action: close) {
                    Text("Close")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Brand.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 48)
        .padding(.bottom, 28)
        .frame(width: 380)
        .background(Brand.canvas)
        .foregroundStyle(Brand.ink)
        .preferredColorScheme(.dark)
        .background(WindowAccessor { hostWindow = $0 })
        .onAppear(perform: startPairing)
        .onDisappear {
            WebSocketServer.shared.onNewPairingCompleted = nil
            PairingManager.shared.endPairingMode()
        }
    }

    private func close() {
        PairingManager.shared.endPairingMode()
        hostWindow?.close()
        dismiss()
    }

    private func startPairing() {
        didPair = false
        PairingManager.shared.beginPairingMode()
        if let url = PairingManager.shared.getPairingURL() {
            qrImage = QRCodeGenerator.generate(from: url)
        }

        WebSocketServer.shared.onNewPairingCompleted = { deviceId, _ in
            DispatchQueue.main.async {
                didPair = true
                pairedDeviceId = deviceId
                PairingManager.shared.endPairingMode()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    close()
                }
            }
        }

        WebSocketServer.shared.start()
        isListening = true
    }
}

/// Reaches the NSWindow hosting this SwiftUI view so it can close itself
/// without the view needing a reference to the AppDelegate.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
