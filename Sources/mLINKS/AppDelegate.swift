import AppKit
import Combine
import SwiftUI
import mLINKSCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = LinkStore(directory: LinkStore.defaultDirectory)
    let updates = UpdateEngine.shared  // mise à jour automatique commune (_tools/shared/Updater.swift)
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
        updates.configure(repo: "mLINKS", lang: { Bundle.main.preferredLocalizations.first ?? "en" })
        updates.autoCheck = { UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true }
        updates.start()
        if CommandLine.arguments.contains("--dump-menu") { dumpMenu(); exit(0) } // essai : le menu tel qu'il serait construit, couleurs comprises

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
                if let color = MenuStyle.color(hex: group.color) { item.attributedTitle = MenuStyle.colored(group.name, color) }
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                addLinks(of: group, to: submenu)
                item.submenu = submenu
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        switch updates.state {
        case .available(let plan):
            menu.addItem(command(L("update.install", plan.target.version), #selector(installUpdateClicked)))
        case .downloading, .verifying, .installing:
            let busy = NSMenuItem(title: L("update.installing"), action: nil, keyEquivalent: "")
            busy.isEnabled = false
            menu.addItem(busy)
        case .idle, .checking, .upToDate, .failed:
            menu.addItem(command(L("update.check"), #selector(checkUpdateClicked)))
        }
        let manage = command(L("menu.manage"), #selector(manageClicked))
        manage.attributedTitle = MenuStyle.colored(L("menu.manage"), NSColor(Socle.C.action)) // jaune Socle
        menu.addItem(manage)
        menu.addItem(command(L("about.menu"), #selector(aboutClicked)))
        menu.addItem(command(L("menu.quit"), #selector(NSApplication.terminate(_:)), target: NSApp))
    }

    private func command(_ title: String, _ action: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target ?? self
        if let branded = MenuStyle.branded(title) { item.attributedTitle = branded } // « À propos de mLINKS », « Quitter mLINKS »
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

    @objc private func checkUpdateClicked() { updates.checkNow() }

    @objc private func installUpdateClicked() {
        guard case .available(let plan) = updates.state else { return }
        updates.present(plan)  // fenêtre : notes de version, puis « Installer et relancer »
    }

    /// Décrit chaque entrée du menu avec la couleur de ses portions de titre (sortie standard).
    private func dumpMenu() {
        guard let menu = statusItem?.menu else { return }
        menuNeedsUpdate(menu)
        func hex(_ c: NSColor) -> String {
            let rgb = c.usingColorSpace(.sRGB) ?? c
            return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
        }
        for item in menu.items where !item.isAlternate {
            if item.isSeparatorItem { print("———"); continue }
            var parts: [String] = []
            if let attributed = item.attributedTitle {
                attributed.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
                    let text = (attributed.string as NSString).substring(with: range)
                    parts.append("[\(text)]" + ((value as? NSColor).map { "=\(hex($0))" } ?? ""))
                }
            }
            print(item.title, parts.isEmpty ? "(titre normal)" : parts.joined(separator: " "))
        }
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
