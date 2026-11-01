import AppKit
import Combine
import SwiftUI
import mLINKSCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = LinkStore(directory: LinkStore.defaultDirectory)
    private var statusItem: NSStatusItem?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        Socle.brand("mLINKS", color: Color(red: 0.22, green: 0.74, blue: 0.97))
        installMainMenu()
        installStatusItem()

        HotkeyCenter.shared.onPress = { [weak self] id in
            if let link = self?.store.library.link(id) { Opener.open(link) }
        }
        store.bindHotkeys()
        store.refreshTargets()

        // Essais : la fenêtre s'ouvre derrière le travail en cours, sans prendre le focus.
        if CommandLine.arguments.contains("--gestion-discrete") { ManagerWindow.show(store: store, quietly: true) }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.store.refreshTargets() }
            })
        }
    }

    /// Relancer l'appli depuis le Finder ou le Dock ouvre la gestion des liens.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager()
        return false
    }

    // MARK: Barre des menus

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "link", accessibilityDescription: "mLINKS")
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        store.refreshTargets()

        let groups = store.library.groups.filter { group in group.links.contains(where: \.visible) }
        if groups.isEmpty {
            let empty = NSMenuItem(title: L("menu.empty"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else if groups.count == 1 {
            addLinks(of: groups[0], to: menu)
        } else {
            for group in groups {
                let item = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                addLinks(of: group, to: submenu)
                item.submenu = submenu
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(command(L("menu.manage"), #selector(manageClicked)))
        menu.addItem(command(L("about.menu"), #selector(aboutClicked)))
        menu.addItem(command(L("menu.quit"), #selector(NSApplication.terminate(_:)), target: NSApp))
    }

    private func command(_ title: String, _ action: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target ?? self
        return item
    }

    private func addLinks(of group: LinkGroup, to menu: NSMenu) {
        for link in group.links where link.visible {
            let available = !store.missing.contains(link.target)
            let image = linkImage(link)

            let item = NSMenuItem(title: link.name, action: #selector(linkClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = link.id
            item.image = image
            item.isEnabled = available
            if let hotkey = link.hotkey { item.badge = NSMenuItemBadge(string: KeyName.label(hotkey)) }
            if !available { item.toolTip = L("status.missing") }
            menu.addItem(item)

            // ⌥ maintenu : afficher dans le Finder au lieu d'ouvrir.
            guard !link.isWeb else { continue }
            let alternate = NSMenuItem(title: L("menu.reveal", link.name), action: #selector(revealClicked(_:)), keyEquivalent: "")
            alternate.target = self
            alternate.representedObject = link.id
            alternate.image = image
            alternate.isEnabled = available
            alternate.isAlternate = true
            alternate.keyEquivalentModifierMask = .option
            menu.addItem(alternate)
        }
    }

    private func linkImage(_ link: LinkItem) -> NSImage? {
        if link.isWeb { return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) }
        if store.missing.contains(link.target) {
            return NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        }
        return store.icons[link.target]
    }

    @objc private func linkClicked(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID, let link = store.library.link(id) { Opener.open(link) }
    }

    @objc private func revealClicked(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? UUID, let link = store.library.link(id) { Opener.reveal(link) }
    }

    @objc private func manageClicked() {
        showManager()
    }

    @objc private func aboutClicked() {
        About.show()
    }

    func showManager() {
        ManagerWindow.show(store: store)
    }

    // MARK: Menu principal

    /// Une appli sans Dock n'affiche pas de menu principal, mais c'est lui qui porte ⌘C, ⌘V, ⌘W…
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
