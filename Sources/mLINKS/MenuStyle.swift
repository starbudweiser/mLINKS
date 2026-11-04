import AppKit
import SwiftUI
import mLINKSCore

/// Titres colorés pour la barre des menus : la couleur d'un groupe, le jaune Socle d'une commande (le nom de l'appli reste en texte normal dans les menus, règle Socle).
@MainActor
enum MenuStyle {
    private static var font: NSFont { .menuFont(ofSize: 0) }

    static func colored(_ title: String, _ color: NSColor) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: color])
    }

    /// Couleur d'un groupe (#RRGGBB) ; nil si absente ou invalide.
    static func color(hex: String?) -> NSColor? {
        guard let hex, let c = GroupColor.components(hex) else { return nil }
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }
}

extension Color {
    /// #RRGGBB ; gris si la valeur est invalide.
    init(hex: String) {
        let c = GroupColor.components(hex) ?? (0.5, 0.5, 0.5)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }
}
