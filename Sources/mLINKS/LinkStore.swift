import AppKit
import mLINKSCore

/// État partagé par le menu et la fenêtre de gestion.
@MainActor
final class LinkStore: ObservableObject {
    @Published private(set) var library: Library
    /// Cibles introuvables d'après la dernière vérification.
    @Published private(set) var missing: Set<String> = []
    @Published private(set) var icons: [String: NSImage] = [:]
    /// Liens dont le raccourci est refusé par le système (déjà pris par une autre appli).
    @Published private(set) var hotkeyFailures: Set<UUID> = []
    @Published var saveFailed = false

    private let file: LibraryFile
    private var checkingRoots = Set<String>()

    init(directory: URL) {
        file = LibraryFile(url: directory.appendingPathComponent("links.json"))
        library = file.load()
    }

    static var defaultDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["MLINKS_DATA_DIR"] { return URL(fileURLWithPath: custom) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mLINKS")
    }

    func mutate(_ change: (inout Library) -> Void) {
        let hotkeysBefore = hotkeyBindings
        change(&library)
        persist()
        if hotkeyBindings.map(\.1) != hotkeysBefore.map(\.1) || hotkeyBindings.map(\.0) != hotkeysBefore.map(\.0) {
            bindHotkeys()
        }
        refreshTargets()
    }

    private func persist() {
        do {
            try file.save(library)
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }

    // MARK: Ajouts

    /// Ajoute des cibles au groupe donné (le premier groupe, créé au besoin, sinon).
    func add(targets: [String], to groupID: UUID?, before: UUID? = nil) {
        mutate { library in
            if library.groups.isEmpty { library.groups.append(LinkGroup(name: L("group.default"))) }
            let group = groupID ?? library.groups[0].id
            for raw in targets {
                let target = LinkItem.normalizedTarget(raw)
                guard let g = library.groups.firstIndex(where: { $0.id == group }),
                      !library.groups[g].links.contains(where: { $0.target == target }) else { continue }
                let link = LinkItem(name: LinkItem.defaultName(for: target), target: target)
                library.groups[g].links.append(link)
                library.moveLink(link.id, to: group, before: before)
            }
        }
    }

    func importLinks(from url: URL) throws -> ImportReport {
        let groups = try QuickLinksImporter.read(url)
        var report = ImportReport()
        mutate { report = $0.merge(groups) }
        return report
    }

    // MARK: Raccourcis

    private var hotkeyBindings: [(UUID, Hotkey)] {
        library.allLinks.compactMap { link in link.hotkey.map { (link.id, $0) } }
    }

    func bindHotkeys() {
        hotkeyFailures = HotkeyCenter.shared.register(hotkeyBindings)
    }

    /// Pendant la saisie d'un raccourci, les raccourcis actifs ne doivent pas se déclencher.
    func suspendHotkeys() {
        HotkeyCenter.shared.unregisterAll()
    }

    // MARK: Vérification des cibles

    /// Vérifie les cibles et charge leurs icônes hors du fil principal, volume par volume :
    /// un disque endormi ou bloqué ne fige jamais le menu ni les autres volumes.
    func refreshTargets() {
        let paths = Set(library.allLinks.filter { !$0.isWeb }.map(\.target))
        let knownIcons = Set(icons.keys)
        for (root, targets) in Dictionary(grouping: paths, by: Library.volumeRoot) where !checkingRoots.contains(root) {
            checkingRoots.insert(root)
            Task.detached(priority: .utility) { [weak self] in
                var absent = Set<String>()
                var loaded: [String: NSImage] = [:]
                for target in targets {
                    if FileManager.default.fileExists(atPath: target) {
                        if !knownIcons.contains(target) {
                            let icon = NSWorkspace.shared.icon(forFile: target)
                            icon.size = NSSize(width: 16, height: 16)
                            loaded[target] = icon
                        }
                    } else {
                        absent.insert(target)
                    }
                }
                await self?.applyCheck(root: root, targets: targets, absent: absent, loaded: loaded)
            }
        }
    }

    private func applyCheck(root: String, targets: [String], absent: Set<String>, loaded: [String: NSImage]) {
        checkingRoots.remove(root)
        missing.subtract(targets)
        missing.formUnion(absent)
        icons.merge(loaded) { _, new in new }
    }
}
