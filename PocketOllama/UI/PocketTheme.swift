import SwiftUI

public enum PocketTheme {
    // True Industrial Dark Palette (No superficial gradients)
    public static let bgDeep = Color(red: 0.00, green: 0.00, blue: 0.00)       // #000000 True OLED Jet Black
    public static let bgSurface = Color(red: 0.05, green: 0.06, blue: 0.08)    // #0D0F14 Carbon Charcoal
    public static let bgSurfaceHover = Color(red: 0.09, green: 0.10, blue: 0.13) // #171A21
    public static let borderSubtle = Color(red: 0.16, green: 0.18, blue: 0.22) // #292E38 Zinc Border
    public static let borderFocus = Color(red: 0.25, green: 0.28, blue: 0.35)
    
    // Industrial Status Accents
    public static let terminalGreen = Color(red: 0.13, green: 0.77, blue: 0.36) // #22C55E Online / Active
    public static let amberWarning = Color(red: 0.96, green: 0.62, blue: 0.04)  // #F59E0B Throttled / Compiling
    public static let roseAlert = Color(red: 0.94, green: 0.27, blue: 0.27)     // #EF4444 Error / Stopped
    public static let devCyan = Color(red: 0.22, green: 0.74, blue: 0.97)       // #38BDF8 Precision Metric
    public static let devIndigo = Color(red: 0.50, green: 0.55, blue: 0.99)     // #818CF8 Reasoning Trace
    
    // High-Legibility Typography Colors
    public static let textPrimary = Color(red: 0.96, green: 0.96, blue: 0.97)   // #F4F4F5
    public static let textSecondary = Color(red: 0.63, green: 0.65, blue: 0.70) // #A1A7B3
    public static let textMuted = Color(red: 0.40, green: 0.43, blue: 0.48)     // #666E7A
    public static let textCode = Color(red: 0.85, green: 0.87, blue: 0.91)
}

public struct DevCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 12
    public var borderColor: Color = PocketTheme.borderSubtle

    public func body(content: Content) -> some View {
        content
            .background(PocketTheme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.0)
            )
    }
}

public extension View {
    func devCard(cornerRadius: CGFloat = 12, borderColor: Color = PocketTheme.borderSubtle) -> some View {
        self.modifier(DevCardModifier(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}
