import SwiftUI

enum RestlegTheme {
    static let ink = Color(red: 0.02, green: 0.13, blue: 0.25)
    static let teal = Color(red: 0.10, green: 0.77, blue: 0.80)
    static let mint = Color(red: 0.74, green: 0.96, blue: 0.86)
    static let green = Color(red: 0.08, green: 0.56, blue: 0.38)
    static let background = Color(red: 0.95, green: 0.99, blue: 0.98)
    static let panel = Color.white
    static let panelTint = Color(red: 0.92, green: 0.98, blue: 0.96)
    static let border = Color(red: 0.77, green: 0.89, blue: 0.86)
}

extension View {
    func panelStyle() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RestlegTheme.panel, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(RestlegTheme.border.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: RestlegTheme.ink.opacity(0.06), radius: 18, x: 0, y: 10)
    }

    func restlegBackground() -> some View {
        self.background(
            LinearGradient(
                colors: [
                    RestlegTheme.background,
                    Color(red: 0.91, green: 0.98, blue: 0.97),
                    Color(red: 0.96, green: 0.99, blue: 0.98),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
