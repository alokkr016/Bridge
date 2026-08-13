import SwiftUI

struct PairingWindow: View {
    @State private var pairingURL: String?
    @State private var qrImage: NSImage?
    @State private var isListening = false
    @State private var isConnected = false
    @State private var pairedDeviceId: String?
    @State private var hostWindow: NSWindow?
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                .overlay(alignment: .bottomTrailing) {
                    if isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.green)
                            .background(Circle().fill(.background))
                            .offset(x: 4, y: 4)
                    }
                }

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

            Button(action: primaryAction) {
                Label(isConnected ? "Done" : (isListening ? "Listening..." : "Start Pairing"), systemImage: isConnected ? "checkmark" : "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isListening && !isConnected)
        }
        .padding(40)
        .frame(width: 400, height: 520)
        .background(WindowAccessor { window in self.hostWindow = window })
        .onAppear(perform: startPairing)
        .onDisappear {
            pollTimer?.invalidate()
            pollTimer = nil
            // Close the pairing window's trust exception as soon as it goes away.
            PairingManager.shared.endPairingMode()
        }
    }

    /// Once paired the button becomes "Done" and its job is to dismiss.
    private func primaryAction() {
        if isConnected {
            pollTimer?.invalidate()
            pollTimer = nil
            hostWindow?.close()
        } else {
            startPairing()
        }
    }

    private func startPairing() {
        if isConnected { return }
        // Opens the only window in which an unknown device may pair.
        PairingManager.shared.beginPairingMode()
        pairingURL = PairingManager.shared.getPairingURL()
        if let url = pairingURL {
            qrImage = QRCodeGenerator.generate(from: url)
        }

        WebSocketServer.shared.onHandshakeReceived = { deviceId, publicKey in
            DispatchQueue.main.async {
                self.isConnected = true
                self.pairedDeviceId = deviceId
                self.pollTimer?.invalidate()
                self.pollTimer = nil
                // Paired — no reason to keep accepting new devices.
                PairingManager.shared.endPairingMode()
            }
        }

        WebSocketServer.shared.start()
        isListening = true

        // Fallback for a handshake that landed before this window opened.
        // Invalidated on connect and in onDisappear so it can't outlive the view.
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if WebSocketServer.shared.isConnected {
                DispatchQueue.main.async {
                    self.isConnected = true
                    timer.invalidate()
                    if self.pollTimer === timer { self.pollTimer = nil }
                }
            }
        }
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
