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
        VStack(spacing: 14) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottomTrailing) {
                    if didPair {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.green)
                            .background(Circle().fill(Color(NSColor.windowBackgroundColor)))
                            .offset(x: 4, y: 4)
                    }
                }

            VStack(spacing: 4) {
                Text(didPair ? "Phone paired" : "Pair this Mac")
                    .font(.system(size: 17, weight: .semibold))
                Text(didPair ? "OTPs from your phone will appear here." : macName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if didPair {
                VStack(spacing: 10) {
                    Label("Ready to receive codes", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                    if let id = pairedDeviceId {
                        Text("Phone \(id.prefix(8))…")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    Button("Done") { close() }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                }
                .padding(.top, 8)
            } else {
                Text("On your phone open Bridge → Add Mac or iPad\nand scan this code.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let img = qrImage {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 220, height: 220)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    ProgressView()
                        .frame(width: 244, height: 244)
                }

                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(isListening ? "Waiting for a scan…" : "Preparing…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Button("Close") { close() }
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(width: 360)
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
