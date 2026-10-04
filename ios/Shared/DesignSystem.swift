import SwiftUI

enum DWColors {
    static let accent = Color(red: 83 / 255, green: 109 / 255, blue: 254 / 255)
    static let accentSoft = Color(red: 232 / 255, green: 235 / 255, blue: 255 / 255)
    static let text = Color(red: 32 / 255, green: 36 / 255, blue: 49 / 255)
    static let muted = Color(red: 116 / 255, green: 123 / 255, blue: 140 / 255)
    static let line = Color(red: 230 / 255, green: 232 / 255, blue: 239 / 255)
    static let lightBackground = Color(red: 245 / 255, green: 246 / 255, blue: 250 / 255)
    static let darkBackground = Color(red: 21 / 255, green: 23 / 255, blue: 29 / 255)
    static let darkSurface = Color(red: 32 / 255, green: 35 / 255, blue: 44 / 255)

    static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkBackground : lightBackground }
    static func surface(_ scheme: ColorScheme) -> Color { scheme == .dark ? darkSurface : .white }
    static func category(_ value: String) -> Color {
        switch value {
        case "health": return .green
        case "home": return .orange
        case "social": return .pink
        case "learning": return .purple
        case "errands": return .brown
        default: return accent
        }
    }

    static func taskColor(mode: String, token: String?, category: String) -> Color {
        let resolved = mode == "custom" ? token : nil
        switch resolved ?? categoryDefaultToken(category) {
        case "mint": return Color(red: 55 / 255, green: 207 / 255, blue: 160 / 255)
        case "amber": return Color(red: 255 / 255, green: 193 / 255, blue: 74 / 255)
        case "rose": return Color(red: 232 / 255, green: 105 / 255, blue: 151 / 255)
        case "violet": return Color(red: 150 / 255, green: 113 / 255, blue: 232 / 255)
        case "coral": return Color(red: 239 / 255, green: 133 / 255, blue: 91 / 255)
        case "sky": return Color(red: 88 / 255, green: 166 / 255, blue: 255 / 255)
        default: return accent
        }
    }

    private static func categoryDefaultToken(_ category: String) -> String {
        switch category {
        case "health": return "mint"
        case "home": return "amber"
        case "social": return "rose"
        case "learning": return "violet"
        case "errands": return "coral"
        default: return "indigo"
        }
    }
}

struct DWCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.padding(14).background(DWColors.surface(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DWColors.line.opacity(colorScheme == .dark ? 0.2 : 1)))
    }
}

extension View {
    func dailyWidgetCard() -> some View { modifier(DWCardModifier()) }
}
