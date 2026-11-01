import AppKit
import mLINKSCore

enum Opener {
    /// Ouvre un lien. Un fichier sans appli associée (.zshrc…) est montré dans le Finder.
    @MainActor
    static func open(_ link: LinkItem) {
        if link.isWeb {
            guard let url = URL(string: link.target) else { return }
            NSWorkspace.shared.open(url)
            return
        }
        let path = link.target
        let name = link.name
        // Vérification hors du fil principal : un volume endormi peut mettre du temps à répondre.
        Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: path) else {
                await showMissing(name: name, path: path)
                return
            }
            let url = URL(fileURLWithPath: path)
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(url, configuration: configuration) { _, error in
                if error != nil { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }

    @MainActor
    static func reveal(_ link: LinkItem) {
        if link.isWeb { open(link) } else { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: link.target)]) }
    }

    @MainActor
    private static func showMissing(name: String, path: String) {
        let alert = NSAlert()
        alert.messageText = L("open.missing.title", name)
        alert.informativeText = L("open.missing.text", path)
        NSApp.activate()
        alert.runModal()
    }
}
