import SwiftUI
import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Formateador de números para formato europeo (punto para miles, coma para decimales)
struct EuropeanNumberFormatter {
    static let shared = EuropeanNumberFormatter()
    
    private let formatter: NumberFormatter
    
    private init() {
        formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
    }
    
    func format(_ value: Double) -> String {
        return formatter.string(from: NSNumber(value: value)) ?? "0,00"
    }
    
    func format(_ value: Double, fractionDigits: Int) -> String {
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        let result = formatter.string(from: NSNumber(value: value)) ?? "0,00"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return result
    }
}

/// Wrapper para colores que funciona tanto en macOS como en iOS
struct ColorCompatibility {
    #if os(macOS)
    static func systemGray6() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func systemGray5() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func systemGray4() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func systemGray3() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func systemGray2() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func systemGray() -> Color {
        return Color(NSColor.systemGray)
    }
    
    static func label() -> Color {
        return Color(NSColor.labelColor)
    }
    
    static func secondaryLabel() -> Color {
        return Color(NSColor.secondaryLabelColor)
    }
    
    static func tertiaryLabel() -> Color {
        return Color(NSColor.tertiaryLabelColor)
    }
    
    static func quaternaryLabel() -> Color {
        return Color(NSColor.quaternaryLabelColor)
    }
    
    static func systemFill() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func secondarySystemFill() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func tertiarySystemFill() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func quaternarySystemFill() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func systemBackground() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func controlBackground() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func secondarySystemBackground() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func tertiarySystemBackground() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func systemGroupedBackground() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func secondarySystemGroupedBackground() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func tertiarySystemGroupedBackground() -> Color {
        return Color(NSColor.controlBackgroundColor)
    }
    
    static func separator() -> Color {
        return Color(NSColor.separatorColor)
    }
    
    static func opaqueSeparator() -> Color {
        return Color(NSColor.separatorColor)
    }
    
    static func link() -> Color {
        return Color(NSColor.linkColor)
    }
    
    static func placeholderText() -> Color {
        return Color(NSColor.placeholderTextColor)
    }
    
    static func systemRed() -> Color {
        return Color(NSColor.systemRed)
    }
    
    static func systemBlue() -> Color {
        return Color(NSColor.systemBlue)
    }
    
    static func systemPink() -> Color {
        return Color(NSColor.systemPink)
    }
    
    static func systemTeal() -> Color {
        return Color(NSColor.systemTeal)
    }
    
    static func systemIndigo() -> Color {
        return Color(NSColor.systemIndigo)
    }
    
    static func systemOrange() -> Color {
        return Color(NSColor.systemOrange)
    }
    
    static func systemPurple() -> Color {
        return Color(NSColor.systemPurple)
    }
    
    static func systemYellow() -> Color {
        return Color(NSColor.systemYellow)
    }
    
    static func systemGreen() -> Color {
        return Color(NSColor.systemGreen)
    }
    
    static func systemMint() -> Color {
        return Color(NSColor.systemMint)
    }
    
    static func systemCyan() -> Color {
        return Color(NSColor.systemCyan)
    }
    
    static func systemBrown() -> Color {
        return Color(NSColor.systemBrown)
    }
    
    #elseif os(iOS)
    static func systemGray6() -> Color {
        return Color(UIColor.systemGray6)
    }
    
    static func systemGray5() -> Color {
        return Color(UIColor.systemGray5)
    }
    
    static func systemGray4() -> Color {
        return Color(UIColor.systemGray4)
    }
    
    static func systemGray3() -> Color {
        return Color(UIColor.systemGray3)
    }
    
    static func systemGray2() -> Color {
        return Color(UIColor.systemGray2)
    }
    
    static func systemGray() -> Color {
        return Color(UIColor.systemGray)
    }
    
    static func label() -> Color {
        return Color(UIColor.label)
    }
    
    static func secondaryLabel() -> Color {
        return Color(UIColor.secondaryLabel)
    }
    
    static func tertiaryLabel() -> Color {
        return Color(UIColor.tertiaryLabel)
    }
    
    static func quaternaryLabel() -> Color {
        return Color(UIColor.quaternaryLabel)
    }
    
    static func systemFill() -> Color {
        return Color(UIColor.systemFill)
    }
    
    static func secondarySystemFill() -> Color {
        return Color(UIColor.secondarySystemFill)
    }
    
    static func tertiarySystemFill() -> Color {
        return Color(UIColor.tertiarySystemFill)
    }
    
    static func quaternarySystemFill() -> Color {
        return Color(UIColor.quaternarySystemFill)
    }
    
    static func systemBackground() -> Color {
        return Color(UIColor.systemBackground)
    }
    
    static func controlBackground() -> Color {
        return Color.black
    }
    
    static func appBackground() -> Color {
        return Color(UIColor.systemGray6)
    }
    
    static func secondarySystemBackground() -> Color {
        return Color(UIColor.secondarySystemBackground)
    }
    
    static func tertiarySystemBackground() -> Color {
        return Color(UIColor.tertiarySystemBackground)
    }
    
    static func systemGroupedBackground() -> Color {
        return Color(UIColor.systemGroupedBackground)
    }
    
    static func secondarySystemGroupedBackground() -> Color {
        return Color(UIColor.secondarySystemGroupedBackground)
    }
    
    static func tertiarySystemGroupedBackground() -> Color {
        return Color(UIColor.tertiarySystemGroupedBackground)
    }
    
    static func separator() -> Color {
        return Color(UIColor.separator)
    }
    
    static func opaqueSeparator() -> Color {
        return Color(UIColor.opaqueSeparator)
    }
    
    static func link() -> Color {
        return Color(UIColor.link)
    }
    
    static func placeholderText() -> Color {
        return Color(UIColor.placeholderText)
    }
    
    static func systemRed() -> Color {
        return Color(UIColor.systemRed)
    }
    
    static func systemBlue() -> Color {
        return Color(UIColor.systemBlue)
    }
    
    static func systemPink() -> Color {
        return Color(UIColor.systemPink)
    }
    
    static func systemTeal() -> Color {
        return Color(UIColor.systemTeal)
    }
    
    static func systemIndigo() -> Color {
        return Color(UIColor.systemIndigo)
    }
    
    static func systemOrange() -> Color {
        return Color(UIColor.systemOrange)
    }
    
    static func systemPurple() -> Color {
        return Color(UIColor.systemPurple)
    }
    
    static func systemYellow() -> Color {
        return Color(UIColor.systemYellow)
    }
    
    static func systemGreen() -> Color {
        return Color(UIColor.systemGreen)
    }
    
    static func systemMint() -> Color {
        return Color(UIColor.systemMint)
    }
    
    static func systemCyan() -> Color {
        return Color(UIColor.systemCyan)
    }
    
    static func systemBrown() -> Color {
        return Color(UIColor.systemBrown)
    }
    #endif
}