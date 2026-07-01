import SwiftUI

/// Tiny localization helper. Keys resolve against the .strings tables; the
/// French table is the development/fallback language.
enum L {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

/// Convenience so views can write `Text(loc: "canvas.title")`.
extension Text {
    init(loc key: String) {
        self.init(L.t(key))
    }
}
