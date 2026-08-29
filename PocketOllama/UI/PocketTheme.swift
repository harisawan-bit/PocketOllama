import SwiftUI

public enum PocketTheme {
    // Deep Midnight OLED Bases
    public static let bgDeep = Color(red: 0.02, green: 0.03, blue: 0.06)      // #05080F
    public static let bgCard = Color(red: 0.06, green: 0.08, blue: 0.14)      // #0F1424
    public static let bgCardHover = Color(red: 0.09, green: 0.12, blue: 0.20) // #171E33
    public static let borderGlass = Color.white.opacity(0.06)
    
    // Vibrant Cyber & AI Accents
    public static let cyan = Color(red: 0.00, green: 0.94, blue: 1.00)        // #00F0FF (Primary AI)
    public static let emerald = Color(red: 0.00, green: 1.00, blue: 0.53)     // #00FF88 (Active / Online)
    public static let purple = Color(red: 0.65, green: 0.40, blue: 1.00)      // #A666FF (Reasoning / Thinking)
    public static let amber = Color(red: 1.00, green: 0.72, blue: 0.00)       // #FFB800 (Warning / Throttle)
    public static let rose = Color(red: 1.00, green: 0.20, blue: 0.40)        // #FF3366 (Danger / Stop)
    
    // Typography Colors
    public static let textPrimary = Color.white
    public static let textSecondary = Color(red: 0.65, green: 0.70, blue: 0.82)
    public static let textMuted = Color(red: 0.40, green: 0.45, blue: 0.58)
    
    // Gradients
    public static let cyanPurpleGradient = LinearGradient(
        colors: [cyan, purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let roseGradient = LinearGradient(
        colors: [rose, Color(red: 0.8, green: 0.1, blue: 0.3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public struct FluidGlassCard: ViewModifier {
    public var cornerRadius: CGFloat = 20
    public var borderColor: Color = PocketTheme.borderGlass

    public func body(content: Content) -> some View {
        content
            .background(PocketTheme.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.75)
            )
    }
}

public extension View {
    func fluidGlass(cornerRadius: CGFloat = 20, borderColor: Color = PocketTheme.borderGlass) -> some View {
        self.modifier(FluidGlassCard(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}
