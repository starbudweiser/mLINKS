import AppKit
import SwiftUI

/// Rendus hors écran : aucune fenêtre n'apparaît et l'appli quitte aussitôt.
@MainActor
enum Capture {
    static func manager(_ store: LinkStore, _ path: String) {
        // La fiche du premier lien est ouverte pour vérifier les trois colonnes.
        let first = store.library.allLinks.first?.id
        let view = NSHostingView(rootView: ManagerView(selectedLink: first).environmentObject(store))
        view.frame = NSRect(origin: .zero, size: ManagerWindow.defaultSize)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            MainActor.assumeIsolated { write(view, path) }
        }
    }

    static func about(_ store: LinkStore, _ path: String) {
        let window = About.makeWindow()
        window.appearance = NSAppearance(named: .darkAqua)
        if let view = window.contentView {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(white: 0.17, alpha: 1).cgColor
            write(view, path)
        }
    }

    private static func write(_ view: NSView, _ path: String) {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        exit(0)
    }
}
