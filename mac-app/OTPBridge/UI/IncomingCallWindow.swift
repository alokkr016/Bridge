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

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: ringing ? "phone.fill" : "phone.connection.fill")
                .font(.system(size: 28))
                .foregroundStyle(ringing ? Color.green : Color.secondary)

            Text(ringing ? "Incoming call" : "On a call")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text(name.isEmpty ? (number.isEmpty ? "Unknown" : number) : name)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
            if !name.isEmpty && !number.isEmpty {
                Text(number)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if ringing {
                    Button(action: onAnswer) {
                        Label("Answer", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                }
                Button(role: .destructive, action: onHangup) {
                    Label(ringing ? "Decline" : "Hang up", systemImage: "phone.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(.regularMaterial)
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
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Bridge"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = hosting
            window.center()
            if let screen = NSScreen.main {
                let frame = window.frame
                let x = screen.visibleFrame.midX - frame.width / 2
                let y = screen.visibleFrame.maxY - frame.height - 48
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
