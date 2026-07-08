import SwiftUI

enum RestlegTheme {
    static let ink = Color(red: 0.02, green: 0.14, blue: 0.28)
    static let navy = Color(red: 0.02, green: 0.18, blue: 0.35)
    static let blue = Color(red: 0.07, green: 0.48, blue: 0.70)
    static let sky = Color(red: 0.69, green: 0.93, blue: 1.00)
    static let teal = Color(red: 0.11, green: 0.75, blue: 0.82)
    static let mint = Color(red: 0.74, green: 0.96, blue: 0.92)
    static let green = blue
    static let background = Color(red: 0.93, green: 0.98, blue: 1.00)
    static let panel = Color.white
    static let panelTint = Color(red: 0.88, green: 0.97, blue: 1.00)
    static let border = Color(red: 0.70, green: 0.86, blue: 0.94)
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
                    Color(red: 0.86, green: 0.96, blue: 1.00),
                    Color(red: 0.98, green: 0.99, blue: 1.00),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct AppSafetyFooter: View {
    var body: some View {
        Text("Screening only. Restleg does not diagnose RLS or any sleep disorder, and it does not replace clinician judgment. Seek professional review for persistent symptoms, severe daytime impairment, breathing pauses, chest pain, drowsy driving, pregnancy, childhood symptoms, medication questions, or device settings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}
