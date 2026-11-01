import AppKit
import mLINKSCore

let arguments = CommandLine.arguments

/// `--import <fichier>` : import sans interface, pour le terminal et les essais.
if let flag = arguments.firstIndex(of: "--import"), arguments.indices.contains(flag + 1) {
    MainActor.assumeIsolated {
        let store = LinkStore(directory: LinkStore.defaultDirectory)
        do {
            let report = try store.importLinks(from: URL(fileURLWithPath: arguments[flag + 1]))
            print("\(report.added) liens ajoutés, \(report.groupsCreated) groupes créés, \(report.alreadyPresent) déjà présents")
            exit(0)
        } catch {
            print("Import impossible : \(error)")
            exit(1)
        }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
// Pas d'icône dans le Dock, seulement la barre des menus. Aucune fenêtre au lancement.
app.setActivationPolicy(.accessory)

/// `--capture <fichier.png>` et `--capture-about <fichier.png>` : rendu hors écran pour vérifier
/// l'interface sans ouvrir de fenêtre devant le travail en cours.
for (flag, render) in [("--capture", Capture.manager), ("--capture-about", Capture.about)] {
    if let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) {
        let path = arguments[index + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            MainActor.assumeIsolated { render(delegate.store, path) }
        }
    }
}

app.run()
