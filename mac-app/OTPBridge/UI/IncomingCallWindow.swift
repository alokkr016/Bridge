import SwiftUI
import AppKit

/// Floating incoming-call card. Audio stays on the phone; these buttons only
/// tell Android to answer or hang up.
struct IncomingCallView: View {
    let name: String
    let number: String
    let ringing: Bool
    let onAnswer: () -> Void
    let onHangup: () -> Void

    private var displayName: String {
        name.isEmpty ? (number.isEmpty ? "Unknown" : number) : name
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon container with soft background badge
            ZStack {
                Circle()
                    .fill(ringing ? Color.green.opacity(0.18) : Color.primary.opacity(0.08))
                    .frame(width: 34, height: 34)

                Image(systemName: ringing ? "phone.down.waves.left.and.right" : "phone.connection.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ringing ? Color.green : Color.primary.opacity(0.8))
                    .symbolEffect(.bounce, options: .repeating, isActive: ringing)
            }

            // Caller details
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if ringing {
                        Text("Incoming Call")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("On call")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    if !name.isEmpty && !number.isEmpty {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(number)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Buttons
            HStack(spacing: 8) {
                if ringing {
                    Button(action: onAnswer) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                in: Circle()
                            )
                            .shadow(color: Color.green.opacity(0.35), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onHangup) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            LinearGradient(
                                colors: [Color.red, Color.red.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Circle()
                        )
                        .shadow(color: Color.red.opacity(0.35), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 260, maxWidth: 300)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.25),
                                    Color.white.opacity(0.05),
                                    Color.black.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
        }
        .padding(8) // padding around pill for shadow rendering
    }
}

final class IncomingCallController {

    static let shared = IncomingCallController()

    private var window: NSWindow?
    private var ringing = false

    private init() {}

    func handle(state: String, number: String, name: String?) {
        switch state {
        case "ringing":
            ringing = true
            show(number: number, name: name ?? "", ringing: true)
            NotificationManager.shared.showIncomingCall(name: name ?? "", number: number)
            SoundManager.shared.play()
        case "offhook":
            ringing = false
            show(number: number, name: name ?? "", ringing: false)
            NotificationManager.shared.clearIncomingCall()
        default:
            ringing = false
            hide()
            NotificationManager.shared.clearIncomingCall()
        }
    }

    func answer() {
        WebSocketServer.shared.sendCallControl("answer")
    }

    func hangup() {
        WebSocketServer.shared.sendCallControl("hangup")
    }

    private func show(number: String, name: String, ringing: Bool) {
        let view = IncomingCallView(
            name: name,
            number: number,
            ringing: ringing,
            onAnswer: { [weak self] in self?.answer() },
            onHangup: { [weak self] in self?.hangup() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.invalidateIntrinsicContentSize()
        let size = hosting.fittingSize

        if let window {
            window.contentView = hosting
            window.setContentSize(size)
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Bridge Call"
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false // shadow is drawn via SwiftUI for crisp pill edges
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovableByWindowBackground = true
            window.contentView = hosting
            if let screen = NSScreen.main {
                let x = screen.visibleFrame.maxX - size.width - 20
                let y = screen.visibleFrame.maxY - size.height - 20
                window.setFrameOrigin(NSPoint(x: x, y: y))
            }
            window.makeKeyAndOrderFront(nil)
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hide() {
        window?.orderOut(nil)
    }
}
