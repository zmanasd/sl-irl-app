import SwiftUI

/// Centralized design tokens matching the stitch HTML designs
enum DesignSystem {
    
    // MARK: - Colors
    
    struct Colors {
        /// Primary accent color (iOS Standard Blue)
        static let primary = Color(hex: "007AFF")
        
        
        // Alert Type Colors (from Tailwind mappings in event log)
        static let alertGreen = Color(hex: "10B981") // Emerald-500
        static let alertPurple = Color(hex: "A855F7") // Purple-500
        static let alertOrange = Color(hex: "F97316") // Orange-500
        static let alertRed = Color(hex: "EF4444") // Red-500
        static let alertYellow = Color(hex: "EAB308") // Yellow-500
        static let primaryBlue = primary
    }
    
    // MARK: - Corner Radii
    
    struct Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12 // "rounded-lg" / "rounded-xl"
        static let large: CGFloat = 16
        static let extraLarge: CGFloat = 24 // "rounded-2xl"
    }
    
    // MARK: - Typography
    // SwiftUI uses San Francisco (SF) which is highly equivalent to Inter on iOS.
    // For maximum native feel, we use the system font with specific weights.
}

// MARK: - Color Extensions

extension Color {
    /// Initialize a Color from a hex string (e.g. "007AFF" or "#007AFF")
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// Dynamic System Colors for Backgrounds
extension ShapeStyle where Self == Color {
    static var appBackground: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(white: 0.0, alpha: 1.0) : UIColor(red: 242/255, green: 242/255, blue: 247/255, alpha: 1.0) // #F2F2F7
        })
    }
    
    static var appCard: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0) : UIColor.white // #1C1C1E
        })
    }
}
