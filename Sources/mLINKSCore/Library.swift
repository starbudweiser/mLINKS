import Foundation

/// Raccourci clavier global : code de touche physique + modificateurs au format NSEvent
/// (le même que MASShortcut, donc celui de la base QuickLinks).
public struct Hotkey: Codable, Equatable, Hashable, Sendable {
    public static let shift: UInt = 1 << 17
    public static let control: UInt = 1 << 18
    public static let option: UInt = 1 << 19
    public static let command: UInt = 1 << 20
    private static let allModifiers = shift | control | option | command

    public var keyCode: Int
    public var modifiers: UInt

    public init(keyCode: Int, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Hotkey.allModifiers
    }
}

public struct LinkItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// Chemin absolu, ou adresse web.
    public var target: String
    public var visible: Bool
    public var hotkey: Hotkey?

    public init(id: UUID = UUID(), name: String, target: String, visible: Bool = true, hotkey: Hotkey? = nil) {
        self.id = id
        self.name = name
        self.target = target
        self.visible = visible
        self.hotkey = hotkey
    }

    public var isWeb: Bool { LinkItem.isWeb(target) }

    public static func isWeb(_ target: String) -> Bool {
        target.contains("://") && !target.hasPrefix("file:")
    }

    /// Ramène une cible à sa forme stockée : chemin décodé pour une adresse file://, ~ développé.
    public static func normalizedTarget(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("file:"), let url = URL(string: text) { return url.path }
        return text.hasPrefix("~") ? (text as NSString).expandingTildeInPath : text
    }

    /// Nom proposé pour une cible : le nom du fichier sans `.app`, ou l'hôte d'une adresse web.
    public static func defaultName(for target: String) -> String {
        if isWeb(target) { return URL(string: target)?.host ?? target }
        let name = (target as NSString).lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}

/// Couleur d'un groupe dans le menu de la barre des menus (au format #RRGGBB).
public enum GroupColor {
    /// Teintes proposées : celles de Socle, lisibles sur le fond sombre du menu comme sur le clair.
    public static let palette = ["#38BDF8", "#34D399", "#FBBF24", "#F97316", "#F87171", "#F472B6", "#A78BFA", "#A3A3A3"]

    public static func isValid(_ hex: String) -> Bool {
        hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
    }

    /// Composantes 0…1 ; nil si la valeur n'est pas une couleur valide (un fichier modifié à la main ne casse rien).
    public static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard isValid(hex), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (Double(value >> 16 & 255) / 255, Double(value >> 8 & 255) / 255, Double(value & 255) / 255)
    }
}

public struct LinkGroup: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var links: [LinkItem]
    /// Couleur du titre du groupe dans le menu ; nil = couleur normale du menu.
    public var color: String?

    public init(id: UUID = UUID(), name: String, links: [LinkItem] = [], color: String? = nil) {
        self.id = id
        self.name = name
        self.links = links
        self.color = color
    }
}

/// Bilan d'un import, affiché tel quel à l'utilisateur.
public struct ImportReport: Equatable, Sendable {
    public var added = 0
    public var groupsCreated = 0
    public var alreadyPresent = 0
    public var hotkeysDropped = 0

    public init() {}
}

public struct Library: Codable, Equatable, Sendable {
    public var version = 1
    public var groups: [LinkGroup] = []

    public init(groups: [LinkGroup] = []) {
        self.groups = groups
    }

    public var allLinks: [LinkItem] { groups.flatMap(\.links) }

    public func link(_ id: UUID) -> LinkItem? {
        allLinks.first { $0.id == id }
    }

    /// Le lien qui porte déjà ce raccourci, s'il y en a un (hors `excluding`).
    public func owner(of hotkey: Hotkey, excluding: UUID? = nil) -> LinkItem? {
        allLinks.first { $0.hotkey == hotkey && $0.id != excluding }
    }

    public mutating func update(_ id: UUID, _ change: (inout LinkItem) -> Void) {
        for g in groups.indices {
            if let i = groups[g].links.firstIndex(where: { $0.id == id }) {
                change(&groups[g].links[i])
                return
            }
        }
    }

    @discardableResult
    public mutating func removeLink(_ id: UUID) -> LinkItem? {
        for g in groups.indices {
            if let i = groups[g].links.firstIndex(where: { $0.id == id }) {
                return groups[g].links.remove(at: i)
            }
        }
        return nil
    }

    /// Déplace un lien dans un groupe, avant `before` s'il est donné, sinon à la fin.
    public mutating func moveLink(_ id: UUID, to groupID: UUID, before: UUID? = nil) {
        guard id != before, groups.contains(where: { $0.id == groupID }), let link = removeLink(id),
              let g = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let index = before.flatMap { b in groups[g].links.firstIndex { $0.id == b } } ?? groups[g].links.count
        groups[g].links.insert(link, at: index)
    }

    public mutating func moveGroup(_ id: UUID, before: UUID?) {
        guard id != before, let from = groups.firstIndex(where: { $0.id == id }) else { return }
        let group = groups.remove(at: from)
        let index = before.flatMap { b in groups.firstIndex { $0.id == b } } ?? groups.count
        groups.insert(group, at: index)
    }

    /// Ajoute des groupes importés sans rien retirer : un groupe de même nom est complété, un lien
    /// dont la cible s'y trouve déjà est ignoré, un raccourci déjà pris est abandonné.
    @discardableResult
    public mutating func merge(_ imported: [LinkGroup]) -> ImportReport {
        var report = ImportReport()
        for source in imported {
            let key = source.name.lowercased()
            var index = groups.firstIndex { $0.name.lowercased() == key }
            if index == nil, source.links.isEmpty == false {
                groups.append(LinkGroup(name: source.name))
                index = groups.count - 1
                report.groupsCreated += 1
            }
            guard let g = index else { continue }
            for var link in source.links {
                if groups[g].links.contains(where: { $0.target == link.target }) {
                    report.alreadyPresent += 1
                    continue
                }
                if let hotkey = link.hotkey, owner(of: hotkey) != nil {
                    link.hotkey = nil
                    report.hotkeysDropped += 1
                }
                link.id = UUID()
                groups[g].links.append(link)
                report.added += 1
            }
        }
        return report
    }

    /// Racine du volume d'un chemin : `/Volumes/Nom`, ou `/` pour le disque de démarrage.
    public static func volumeRoot(of path: String) -> String {
        let parts = path.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: true)
        return parts.count >= 2 && parts[0] == "Volumes" ? "/Volumes/\(parts[1])" : "/"
    }
}

/// Lecture et écriture de la bibliothèque (`links.json`).
public struct LibraryFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Un fichier illisible est mis de côté plutôt qu'écrasé par la prochaine sauvegarde.
    public func load() -> Library {
        guard let data = try? Data(contentsOf: url) else { return Library() }
        if let library = try? JSONDecoder().decode(Library.self, from: data) { return library }
        let aside = url.deletingPathExtension().appendingPathExtension("illisible.json")
        try? FileManager.default.removeItem(at: aside)
        try? FileManager.default.moveItem(at: url, to: aside)
        return Library()
    }

    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: url, options: .atomic)
    }
}
