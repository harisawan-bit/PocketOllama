import SwiftUI

public enum PocketTheme {
    // Surface & Background Colors
    public static let bgDeep = Color(red: 0.03, green: 0.04, blue: 0.07)      // #080A12
    public static let bgCard = Color(red: 0.07, green: 0.09, blue: 0.15)      // #121726
    public static let bgCardHover = Color(red: 0.10, green: 0.13, blue: 0.22) // #1A2138
    public static let bgGlass = Color.white.opacity(0.04)
    public static let borderGlass = Color.white.opacity(0.08)
    
    // Vibrant Cyber & AI Accents
    public static let cyan = Color(red: 0.00, green: 0.94, blue: 1.00)        // #00F0FF (Primary AI)
    public static let emerald = Color(red: 0.00, green: 1.00, blue: 0.53)     // #00FF88 (Active / Online)
    public static let purple = Color(red: 0.61, green: 0.35, blue: 1.00)      // #9B59B6 (Reasoning / Thinking)
    public static let amber = Color(red: 1.00, green: 0.72, blue: 0.00)       // #FFB800 (Warning / Throttle)
    public static let rose = Color(red: 1.00, green: 0.20, blue: 0.40)        // #FF3366 (Danger / Stop)
    
    // Typography Colors
    public static let textPrimary = Color.white
    public static let textSecondary = Color(red: 0.60, green: 0.65, blue: 0.75)
    public static let textMuted = Color(red: 0.40, green: 0.45, blue: 0.55)
    
    // Gradients
    public static let cyanPurpleGradient = LinearGradient(
        colors: [cyan, purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let glowCardGradient = LinearGradient(
        colors: [Color.white.opacity(0.06), Color.white.opacity(0.01)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public struct GlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 20
    public var borderColor: Color = PocketTheme.borderGlass
    
    public func body(content: Content) -> some View {
        content
            .background(PocketTheme.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
            .cornerRadius(cornerRadius)
    }
}

public extension View {
    func glassCard(cornerRadius: CGFloat = 20, borderColor: Color = PocketTheme.borderGlass) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}
