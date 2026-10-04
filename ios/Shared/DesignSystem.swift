import SwiftUI
import UIKit

enum DWColors {
    // Light / dark pairs match the CSS variables of the Mac app (index.html).
    static let accent = dynamic(light: 0x536DFE, dark: 0xA9B4FF)
    static let accentSoft = dynamic(light: 0xE8EBFF, dark: 0x31395D)
    static let text = dynamic(light: 0x202431, dark: 0xF0F2F7)
    static let muted = dynamic(light: 0x747B8C, dark: 0xA8ADBA)
    static let line = dynamic(light: 0xE6E8EF, dark: 0x373C49)
    static let danger = dynamic(light: 0xC84B5B, dark: 0xFF9DAB)
    static let now = Color(red: 239 / 255, green: 83 / 255, blue: 80 / 255)
    /// Text and icons placed on top of `accent`.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x15171D)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func color(_ hex: UInt32) -> UIColor { UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1) }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }

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

enum DWSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum DWRadius {
    static let card: CGFloat = 16
    static let block: CGFloat = 9
}

/// Type scale built on text styles so every size follows Dynamic Type.
enum DWFont {
    /// 28pt heavy: page titles.
    static let title = Font.system(.title, design: .default, weight: .heavy)
    /// 15pt heavy: card and row titles.
    static let headline = Font.system(.subheadline, design: .default, weight: .heavy)
    /// 13pt: supporting text.
    static let body = Font.footnote
    /// 13pt semibold: labels and buttons.
    static let label = Font.footnote.weight(.semibold)
    /// 11pt with fixed-width digits: times and counters.
    static let caption = Font.caption2.monospacedDigit()
}

struct DWCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = DWSpacing.md
    func body(content: Content) -> some View {
        content.padding(padding).background(DWColors.surface(colorScheme), in: RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous)).overlay(RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous).stroke(DWColors.line.opacity(colorScheme == .dark ? 0.6 : 1)))
    }
}

/// Done / total as a ring with the count in the middle.
struct DWProgressRing: View {
    let completed: Int
    let total: Int
    var size: CGFloat = 52
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(DWColors.accentSoft, lineWidth: lineWidth)
            Circle().trim(from: 0, to: total == 0 ? 0 : CGFloat(completed) / CGFloat(total))
                .stroke(DWColors.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(completed)/\(total)").font(DWFont.caption.weight(.bold)).foregroundStyle(DWColors.text).minimumScaleFactor(0.7).lineLimit(1).padding(.horizontal, lineWidth + 2)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completed) / \(total)")
    }
}

enum DWFormat {
    static func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute % 1440 / 60, minute % 60) }
}

extension View {
    func dailyWidgetCard(padding: CGFloat = DWSpacing.md) -> some View { modifier(DWCardModifier(padding: padding)) }
}
