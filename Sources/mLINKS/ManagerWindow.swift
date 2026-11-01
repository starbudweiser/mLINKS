import AppKit
import SwiftUI

/// Fenêtre de gestion : une seule instance, ouverte uniquement à la demande.
@MainActor
enum ManagerWindow {
    static let defaultSize = NSSize(width: 1040, height: 640)
    private static var window: NSWindow?

    static func show(store: LinkStore, quietly: Bool = false) {
        if window == nil {
            let created = NSWindow(contentRect: NSRect(origin: .zero, size: defaultSize),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered, defer: false)
            created.title = "mLINKS"
            created.isReleasedWhenClosed = false
            created.minSize = NSSize(width: 900, height: 520)
            created.contentView = NSHostingView(rootView: ManagerView().environmentObject(store))
            created.center()
            created.setFrameAutosaveName("gestion")
            window = created
        }
        if quietly {
            window?.orderBack(nil)
            return
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
