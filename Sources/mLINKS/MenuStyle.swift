import AppKit
import SwiftUI
import mLINKSCore

/// Titres colorés pour la barre des menus : le « m » du nom de l'appli, la couleur d'un groupe, le jaune Socle d'une commande.
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

    /// Le titre avec la lettre minuscule du nom de l'appli à la couleur de son logo (règle Socle) ; nil s'il n'y a rien à colorer.
    static func branded(_ title: String) -> NSAttributedString? {
        let marked = Socle.branded(title)
        let ranges = marked.runs.filter { $0.foregroundColor != nil }.map { NSRange($0.range, in: marked) }
        guard !ranges.isEmpty else { return nil }
        let text = NSMutableAttributedString(string: title, attributes: [.font: font])
        let brand = NSColor(Socle.brandColor)
        for range in ranges { text.addAttribute(.foregroundColor, value: brand, range: range) }
        return text
    }
}

extension Color {
    /// #RRGGBB ; gris si la valeur est invalide.
    init(hex: String) {
        let c = GroupColor.components(hex) ?? (0.5, 0.5, 0.5)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }
}
