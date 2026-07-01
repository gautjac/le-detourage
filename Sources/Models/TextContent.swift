import SwiftUI

/// A curated set of scrapbook lettering styles. Each maps to a system font
/// *design* so it renders identically in the live SwiftUI canvas and in the
/// Core Graphics exporter, with no bundled font files to ship.
enum ScrapFont: Int, CaseIterable, Codable, Identifiable {
    case rounded   // bubbly, the playful default
    case serif     // classic keepsake
    case mono      // label-maker
    case plain     // clean sans

    var id: Int { rawValue }

    /// The SwiftUI font design used by the live canvas.
    var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .serif:   return .serif
        case .mono:    return .monospaced
        case .plain:   return .default
        }
    }

    /// The SwiftUI weight used by the live canvas.
    var weight: Font.Weight {
        switch self {
        case .rounded: return .heavy
        case .serif:   return .bold
        case .mono:    return .semibold
        case .plain:   return .heavy
        }
    }

    /// The matching platform-font weight (the exporter builds a real font).
    var platformWeight: PlatformFont.Weight {
        switch self {
        case .rounded: return .heavy
        case .serif:   return .bold
        case .mono:    return .semibold
        case .plain:   return .heavy
        }
    }

    /// The matching platform-font system design (for the exporter's real font).
    #if os(macOS)
    var platformDesign: NSFontDescriptor.SystemDesign {
        switch self {
        case .rounded: return .rounded
        case .serif:   return .serif
        case .mono:    return .monospaced
        case .plain:   return .default
        }
    }
    #else
    var platformDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .rounded: return .rounded
        case .serif:   return .serif
        case .mono:    return .monospaced
        case .plain:   return .default
        }
    }
    #endif

    var titleKey: String {
        switch self {
        case .rounded: return "text.font.rounded"
        case .serif:   return "text.font.serif"
        case .mono:    return "text.font.mono"
        case .plain:   return "text.font.plain"
        }
    }
}

/// The content of a text element on the collage: the string plus its lettering
/// style, color, and an optional rounded "paper chip" behind it. Purely a value
/// type so it encodes cleanly and snapshots cheaply.
struct TextContent: Equatable, Codable {
    var string: String
    var font: ScrapFont
    var colorIndex: Int
    var chip: Bool
    var chipColorIndex: Int

    init(string: String = "",
         font: ScrapFont = .rounded,
         colorIndex: Int = 0,
         chip: Bool = false,
         chipColorIndex: Int = 0) {
        self.string = string
        self.font = font
        self.colorIndex = colorIndex
        self.chip = chip
        self.chipColorIndex = chipColorIndex
    }

    /// What actually renders — a placeholder while the string is still empty so a
    /// freshly added label is visible and tappable.
    var displayString: String {
        string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L.t("text.placeholder") : string
    }

    var isEffectivelyEmpty: Bool {
        string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Palettes

    /// Vivid ink colors for the lettering.
    static let colors: [Color] = [
        Theme.ink, .white, Theme.coral, Theme.teal,
        Theme.grape, Theme.marigold, Theme.sky, Theme.leaf,
    ]
    /// Soft paper colors for the chip behind the text.
    static let chipColors: [Color] = [
        .white, Theme.marigold, Theme.coral, Theme.teal,
        Theme.grape, Theme.sky, Theme.leaf, Theme.bubblegum,
    ]

    var color: Color { Self.colors[min(max(0, colorIndex), Self.colors.count - 1)] }
    var chipColor: Color { Self.chipColors[min(max(0, chipColorIndex), Self.chipColors.count - 1)] }
}
