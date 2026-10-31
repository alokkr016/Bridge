import SwiftUI

enum Brand {
    static let canvas = Color.black
    static let surface = Color(white: 17.0 / 255.0)
    static let line = Color.white.opacity(0.12)
    static let ink = Color(white: 237.0 / 255.0)
    static let muted = Color(white: 161.0 / 255.0)
    static let live = Color.red
}

struct BlinkRed: ViewModifier {
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Brand.live)
            .opacity(dim ? 0.28 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

extension View {
    func blinkRed() -> some View { modifier(BlinkRed()) }
}

struct MadeByAlok: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Made with ")
            Text("♥").blinkRed()
            Text(" by ")
            Link("Alok", destination: URL(string: "https://github.com/alokkr016")!)
                .tint(.blue)
        }
        .font(.system(size: 12))
        .foregroundStyle(Brand.muted)
    }
}
