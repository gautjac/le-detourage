import SwiftUI

/// Le Détourage's visual language: a bright cut-and-paste atelier. A warm
/// cream scrapbook page, torn-paper cutouts with soft drop-shadows, a candy
/// collage palette (teal / marigold / coral / grape / sky), and a rounded,
/// friendly type. Everything should feel like construction paper and glue.
enum Theme {
    // Paper & surfaces.
    static let page = Color(red: 0.965, green: 0.933, blue: 0.898)        // #F6EEE5 cream
    static let pageDeep = Color(red: 0.925, green: 0.878, blue: 0.827)    // shadowed cream
    static let card = Color.white
    static let panel = Color(red: 0.988, green: 0.976, blue: 0.957)
    static let hairline = Color(red: 0.86, green: 0.82, blue: 0.76)

    // Ink.
    static let ink = Color(red: 0.15, green: 0.13, blue: 0.12)            // #262220
    static let inkDim = Color(red: 0.42, green: 0.39, blue: 0.36)
    static let inkFaint = Color(red: 0.64, green: 0.60, blue: 0.55)

    // Candy collage palette.
    static let teal = Color(red: 0.16, green: 0.66, blue: 0.62)           // #29A89E
    static let marigold = Color(red: 0.98, green: 0.78, blue: 0.22)       // #FAC738
    static let coral = Color(red: 0.945, green: 0.298, blue: 0.361)       // #F14C5C
    static let grape = Color(red: 0.55, green: 0.42, blue: 0.80)          // #8C6BCC
    static let sky = Color(red: 0.33, green: 0.62, blue: 0.87)            // #54A0DE
    static let leaf = Color(red: 0.49, green: 0.73, blue: 0.36)           // #7DBB5C
    static let bubblegum = Color(red: 0.96, green: 0.55, blue: 0.72)      // #F58CB8

    /// The accent used for primary actions.
    static let accent = coral

    /// The full swatch set for pickers, cycled deterministically.
    static let palette: [Color] = [teal, marigold, coral, grape, sky, leaf, bubblegum]

    /// Background presets for the collage canvas.
    static let backgroundSwatches: [Color] = [
        page, .white, ink,
        Color(red: 0.98, green: 0.90, blue: 0.78),   // peach
        Color(red: 0.82, green: 0.93, blue: 0.90),   // mint
        Color(red: 0.90, green: 0.86, blue: 0.96),   // lilac
        Color(red: 0.99, green: 0.85, blue: 0.87),   // blush
        Color(red: 0.85, green: 0.91, blue: 0.98),   // powder
    ]

    // MARK: Type — a rounded, friendly ramp.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
    static func body(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // MARK: Shadows — the sticker "peeled off the page" look.
    static let stickerShadow = Color(red: 0.15, green: 0.10, blue: 0.08).opacity(0.28)
}

/// A soft drop-shadowed rounded card — the recurring "sticker on paper" surface.
struct StickerCard: ViewModifier {
    var cornerRadius: CGFloat = 18
    var fill: Color = Theme.card
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .shadow(color: Theme.stickerShadow, radius: 12, x: 0, y: 6)
            )
    }
}

extension View {
    func stickerCard(cornerRadius: CGFloat = 18, fill: Color = Theme.card) -> some View {
        modifier(StickerCard(cornerRadius: cornerRadius, fill: fill))
    }
}
