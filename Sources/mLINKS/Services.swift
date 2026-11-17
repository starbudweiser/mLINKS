import AppKit
import SwiftUI
import mLINKSCore

/// Menu Services de macOS (clic droit > Services) : « Ajouter à mLINKS » sur un dossier ou une application
/// sélectionnés dans le Finder, ou sur une adresse sélectionnée (barre d'adresse de n'importe quel navigateur).
final class ServicesProvider: NSObject {
    private let store: LinkStore

    @MainActor init(store: LinkStore) {
        self.store = store
    }

    /// Appelée par le système avec la sélection ; `error` reçoit le message si rien n'est ajoutable.
    @objc func addToMLinks(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let files = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        var targets = files.map(\.path)
        var failure = "service.error.nothing"
        if targets.isEmpty, let text = pboard.string(forType: .string) {
            if let web = LinkItem.webTarget(fromText: text) { targets = [web] } else { failure = "service.error.notlink" }
        }
        guard !targets.isEmpty else {
            error.pointee = DispatchQueue.main.sync { L(failure) } as NSString
            return
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { AddLink.present(targets, store: self.store) }
        }
    }
}

/// Où placer les liens : sans choix à faire (un seul groupe), ils y vont directement ; sinon un petit panneau
/// liste les groupes, à l'endroit de la souris. Un message bref confirme l'ajout.
@MainActor
enum AddLink {
    private static var panel: NSPanel?

    static func present(_ targets: [String], store: LinkStore) {
        close()
        let groups = store.library.groups
        // Essais sans interface : MLINKS_SERVICE_GROUP désigne le groupe, aucune fenêtre n'apparaît.
        if let name = ProcessInfo.processInfo.environment["MLINKS_SERVICE_GROUP"] {
            let group = groups.first { $0.name == name }
            let added = store.add(targets: targets, to: group?.id)
            print("service : \(added) ajouté(s) à \(group?.name ?? L("group.default"))")
            return
        }
        if groups.count <= 1 {
            confirm(targets, group: groups.first, store: store)
        } else {
            choose(targets, groups: groups, store: store)
        }
    }

    private static func confirm(_ targets: [String], group: LinkGroup?, store: LinkStore) {
        let added = store.add(targets: targets, to: group?.id)
        let name = group?.name ?? store.library.groups.first?.name ?? L("group.default")
        let text = added == 0 ? L("service.duplicate", name)
            : added == 1 ? L("service.added", name) : L("service.added.many", added, name)
        toast(text, warning: added == 0)
    }

    // MARK: Panneaux

    private static func choose(_ targets: [String], groups: [LinkGroup], store: LinkStore) {
        let title = targets.count == 1 ? L("service.one", LinkItem.defaultName(for: LinkItem.normalizedTarget(targets[0])))
            : L("service.many", targets.count)
        let view = GroupChooser(title: title, groups: groups) { group in
            close()
            confirm(targets, group: group, store: store)
        } cancel: { close() }
        show(NSHostingView(rootView: view), activating: true)
    }

    private static func toast(_ text: String, warning: Bool) {
        show(NSHostingView(rootView: ToastView(text: text, warning: warning)), activating: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { close() }
    }

    private static func show(_ content: NSHostingView<some View>, activating: Bool) {
        let size = content.fittingSize
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size), activating: activating)
        panel.contentView = content
        panel.appearance = NSAppearance(named: .darkAqua)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: mouse.x + 8, y: mouse.y - size.height - 8)
        if let zone = screen?.visibleFrame {
            origin.x = min(max(origin.x, zone.minX + 8), zone.maxX - size.width - 8)
            origin.y = min(max(origin.y, zone.minY + 8), zone.maxY - size.height - 8)
        }
        panel.setFrameOrigin(origin)
        self.panel = panel
        if activating {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Essai hors écran : le panneau de choix et le message de confirmation, côte à côte, dans un PNG.
    static func capture(_ store: LinkStore, _ path: String) {
        let stack = VStack(alignment: .leading, spacing: 16) {
            GroupChooser(title: L("service.one", "duckduckgo.com"), groups: store.library.groups, pick: { _ in }, cancel: {})
            ToastView(text: L("service.added", "PERSO"), warning: false)
            ToastView(text: L("service.duplicate", "PERSO"), warning: true)
        }
        .padding(16).background(Color(white: 0.1)).environment(\.colorScheme, .dark)
        let view = NSHostingView(rootView: stack)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        exit(0)
    }

    static func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Panneau sans cadre : se ferme dès qu'on clique ailleurs ; ne prend le focus que s'il propose un choix.
private final class FloatingPanel: NSPanel {
    private let activating: Bool

    init(contentRect: NSRect, activating: Bool) {
        self.activating = activating
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { activating }
    override func resignKey() {
        super.resignKey()
        if activating { Task { @MainActor in AddLink.close() } }
    }
    override func cancelOperation(_ sender: Any?) { Task { @MainActor in AddLink.close() } }
}

private struct GroupChooser: View {
    let title: String
    let groups: [LinkGroup]
    let pick: (LinkGroup) -> Void
    let cancel: () -> Void
    @State private var hovered: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: Socle.M.space1) {
            Text(branded: "mLINKS").socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
                .padding(.horizontal, Socle.M.space2)
            Text(title).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong).lineLimit(2)
                .padding(.horizontal, Socle.M.space2).padding(.bottom, Socle.M.space1)
            ForEach(groups) { group in
                Button { pick(group) } label: {
                    HStack(spacing: Socle.M.space2) {
                        Circle().fill(group.color.map { Color(hex: $0) } ?? Socle.C.textSubtle).frame(width: 8, height: 8)
                        Text(group.name).socle(Socle.T.label).lineLimit(1)
                        Spacer(minLength: Socle.M.space3)
                        Text("\(group.links.count)").socle(Socle.T.monoSm).foregroundStyle(Socle.C.textSubtle)
                    }
                    .padding(.horizontal, Socle.M.space2)
                    .frame(maxWidth: .infinity, minHeight: Socle.M.sizeControl, alignment: .leading)
                    .background(hovered == group.id ? Socle.C.surfaceHover : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radius))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Socle.C.text)
                .onHover { hovered = $0 ? group.id : nil }
            }
        }
        .padding(Socle.M.space2)
        .frame(width: 260)
        .background(Socle.C.surfaceRaised, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))
        .padding(1)
        .onExitCommand(perform: cancel)
    }
}

private struct ToastView: View {
    let text: String
    let warning: Bool

    var body: some View {
        HStack(spacing: Socle.M.space2) {
            Image(systemName: warning ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(warning ? Socle.C.warning : Socle.C.success)
            Text(text).socle(Socle.T.label).foregroundStyle(Socle.C.textStrong).lineLimit(2)
        }
        .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Socle.C.surfaceRaised, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.border, lineWidth: 1))
        .padding(1)
    }
}
