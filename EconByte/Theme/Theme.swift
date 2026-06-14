import SwiftUI

enum Econ {
    static let ocean    = Color(hex: "0F3D52")
    static let tide     = Color(hex: "1A7EA6")
    static let sky      = Color(hex: "5BC4E0")
    static let amber    = Color(hex: "E8A020")
    static let amberLight = Color(hex: "F5C842")
    static let page     = Color(hex: "F7F9FC")
    static let ink      = Color(hex: "0D2533")
    static let mist     = Color(hex: "D8E8EF")
    static let subtext  = Color(hex: "5A7A8A")
    static let white    = Color.white
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundColor(Econ.ink)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Econ.amber)
            .cornerRadius(14)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundColor(Econ.sky)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Econ.tide.opacity(0.15))
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct TopicChip: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(Econ.sky)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Econ.tide.opacity(0.2))
            .cornerRadius(8)
    }
}
