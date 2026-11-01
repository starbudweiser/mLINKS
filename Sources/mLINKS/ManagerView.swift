import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import mLINKSCore

/// Message affiché en tête de la liste après une action.
private struct Notice: Equatable {
    var text: String
    var isError: Bool
}

struct ManagerView: View {
    @EnvironmentObject private var store: LinkStore
    @State private var selectedGroup: UUID?
    @State var selectedLink: UUID?
    @State private var notice: Notice?
    @State private var showWebField = false
    @State private var webAddress = ""
    @State private var groupToDelete: LinkGroup?

    private var group: LinkGroup? {
        store.library.groups.first { $0.id == selectedGroup } ?? store.library.groups.first
    }

    private var link: LinkItem? {
        selectedLink.flatMap { store.library.link($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Socle.C.border)
            HStack(spacing: 0) {
                GroupSidebar(selectedGroup: Binding(get: { group?.id }, set: { selectedGroup = $0; selectedLink = nil }),
                             groupToDelete: $groupToDelete, importAction: importFromQuickLinks, importCSVAction: importCSV)
                    .frame(width: 240)
                Divider().overlay(Socle.C.border)
                linksColumn
                if let link {
                    Divider().overlay(Socle.C.border)
                    LinkDetail(link: link, onDelete: {
                        store.mutate { $0.removeLink(link.id) }
                        selectedLink = nil
                    })
                    .id(link.id)
                    .frame(width: 320)
                }
            }
        }
        .background(Socle.C.bg)
        .foregroundStyle(Socle.C.text)
        .alert(L("group.delete.title", groupToDelete?.name ?? ""), isPresented: Binding(
            get: { groupToDelete != nil }, set: { if !$0 { groupToDelete = nil } })) {
            Button(L("common.delete"), role: .destructive) {
                if let doomed = groupToDelete {
                    store.mutate { $0.groups.removeAll { $0.id == doomed.id } }
                    selectedLink = nil
                }
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("group.delete.text", groupToDelete?.links.count ?? 0))
        }
        // Sélection explicite dès l'ouverture : déplacer le premier groupe ne doit pas faire sauter la sélection.
        .onAppear { selectedGroup = selectedGroup ?? store.library.groups.first?.id }
        .onChange(of: store.saveFailed) { _, failed in
            if failed { notice = Notice(text: L("save.failed"), isError: true) }
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: Socle.M.space2) {
            Text(branded: "mLINKS").socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
            Spacer()
            Button(L("add.web")) { showWebField = true }
                .buttonStyle(SocleButtonStyle(.secondary))
                .fixedSize()
                .popover(isPresented: $showWebField, arrowEdge: .bottom) { webPopover }
            Button(L("add.files"), action: chooseFiles).buttonStyle(SocleButtonStyle(.action)).fixedSize()
        }
        .padding(.horizontal, Socle.M.space3)
        .frame(minHeight: Socle.M.sizeBar + Socle.M.space2)
        .background(Socle.C.surfaceRaised)
    }

    private var webPopover: some View {
        VStack(alignment: .leading, spacing: Socle.M.space2) {
            Text(L("add.web.title")).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
            TextField("https://…", text: $webAddress).socleField().frame(width: 320).onSubmit(addWebLink)
            Button(L("common.add"), action: addWebLink).buttonStyle(SocleButtonStyle(.primary)).fixedSize()
                .disabled(!LinkItem.isWeb(webAddress))
        }
        .padding(Socle.M.space4)
    }

    private func addWebLink() {
        guard LinkItem.isWeb(webAddress) else { return }
        store.add(targets: [webAddress], to: group?.id)
        webAddress = ""
        showWebField = false
    }

    // MARK: Liste

    private var linksColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notice {
                NoticeBar(notice: notice) { self.notice = nil }
            }
            if store.library.groups.isEmpty {
                welcome
            } else if let group {
                HStack {
                    Text(group.name).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
                    GroupColorButton(group: group)
                    Spacer()
                    Text(L("links.count", group.links.count)).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
                }
                .padding(.horizontal, Socle.M.space4).padding(.top, Socle.M.space4).padding(.bottom, Socle.M.space2)
                if group.links.isEmpty {
                    emptyGroup
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(group.links) { item in
                                let index = group.links.firstIndex { $0.id == item.id } ?? 0
                                let next = group.links.indices.contains(index + 1) ? group.links[index + 1].id : nil
                                ReorderRow(token: "link:\(item.id.uuidString)") { providers, below in
                                    Drops.handle(providers, store: store, target: .init(group: group.id, before: below ? next : item.id))
                                } content: {
                                    LinkRow(link: item, selected: item.id == selectedLink,
                                            canGoUp: index > 0, canGoDown: next != nil)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedLink = item.id }
                                        .contextMenu { linkMenu(item, in: group, index: index) }
                                }
                            }
                        }
                        .padding(.horizontal, Socle.M.space3).padding(.bottom, Socle.M.space3)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .plainText], isTargeted: nil) { providers in
            Drops.handle(providers, store: store, target: .init(group: group?.id))
        }
    }

    @ViewBuilder
    private func linkMenu(_ item: LinkItem, in group: LinkGroup, index: Int) -> some View {
        Button(L("order.up")) { store.mutate { $0.moveLink(item.id, by: -1) } }.disabled(index == 0)
        Button(L("order.down")) { store.mutate { $0.moveLink(item.id, by: 1) } }.disabled(index == group.links.count - 1)
        let others = store.library.groups.filter { $0.id != group.id }
        if !others.isEmpty {
            Menu(L("order.moveto")) {
                ForEach(others) { other in
                    Button(other.name) { store.mutate { $0.moveLink(item.id, to: other.id) } }
                }
            }
        }
    }

    private var emptyGroup: some View {
        Text(L("group.empty")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcome: some View {
        VStack(spacing: Socle.M.space3) {
            Text(L("welcome.title")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
            Text(L("welcome.text")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            Button(L("import.quicklinks"), action: importFromQuickLinks).buttonStyle(SocleButtonStyle(.primary)).fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK else { return }
        store.add(targets: panel.urls.map(\.path), to: group?.id)
    }

    private func importFromQuickLinks() {
        runImport(QuickLinksImporter.defaultDatabase)
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runImport(url)
    }

    private func runImport(_ url: URL) {
        do {
            let report = try store.importLinks(from: url)
            var text = L("import.done", report.added, report.groupsCreated, report.alreadyPresent)
            if report.hotkeysDropped > 0 { text += " " + L("import.hotkeys.dropped", report.hotkeysDropped) }
            notice = Notice(text: text, isError: false)
            if selectedGroup == nil { selectedGroup = store.library.groups.first?.id }
        } catch let error as ImportError {
            let key = switch error {
            case .databaseNotFound: "import.error.notfound"
            case .databaseUnreadable: "import.error.unreadable"
            case .notQuickLinksCSV: "import.error.csv"
            }
            notice = Notice(text: L(key), isError: true)
        } catch {
            notice = Notice(text: L("import.error.unreadable"), isError: true)
        }
    }
}

// MARK: - Glisser-déposer

@MainActor
enum Drops {
    /// Où va un dépôt : `reordersGroups` seulement sur la liste des groupes, avec `groupBefore` (nil : à la fin).
    struct Target {
        var group: UUID?
        var before: UUID?
        var reordersGroups = false
        var groupBefore: UUID?
    }

    /// Ce qui est en cours de déplacement dans la fenêtre : un dépôt ne se lit qu'une fois lâché, le survol a besoin de le savoir avant.
    static var dragged: String?

    /// Fichiers du Finder : ajoutés. Lien ou groupe déplacé dans la fenêtre : texte `link:<id>` ou `group:<id>`.
    static func handle(_ providers: [NSItemProvider], store: LinkStore, target: Target) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let path = url?.path else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { store.add(targets: [path], to: target.group, before: target.before) }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                    guard let token = text as? String else { return }
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { apply(token, store: store, target: target) }
                    }
                }
            }
        }
        return handled
    }

    private static func apply(_ token: String, store: LinkStore, target: Target) {
        dragged = nil
        if token.hasPrefix("link:"), let id = UUID(uuidString: String(token.dropFirst(5))), let group = target.group {
            store.mutate { $0.moveLink(id, to: group, before: target.before) }
        } else if token.hasPrefix("group:"), target.reordersGroups, let id = UUID(uuidString: String(token.dropFirst(6))) {
            store.mutate { $0.moveGroup(id, before: target.groupBefore) }
        }
    }
}

// MARK: - Barre latérale

private struct GroupSidebar: View {
    @EnvironmentObject private var store: LinkStore
    @Binding var selectedGroup: UUID?
    @Binding var groupToDelete: LinkGroup?
    let importAction: () -> Void
    let importCSVAction: () -> Void
    @State private var renaming: UUID?
    @State private var startAtLogin = SMAppService.mainApp.status == .enabled
    @State private var hoveredGroup: UUID?
    @AppStorage("autoUpdate") private var autoUpdate = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("groups.title")).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
                Spacer()
                Button {
                    let created = LinkGroup(name: L("group.new"))
                    store.mutate { $0.groups.append(created) }
                    selectedGroup = created.id
                    renaming = created.id
                } label: {
                    Image(systemName: "plus").frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(L("group.add"))
            }
            .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space3)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.library.groups) { group in
                        reorderable(group)
                    }
                }
                .padding(.horizontal, Socle.M.space2)
            }

            Spacer(minLength: 0)
            Divider().overlay(Socle.C.border)
            VStack(alignment: .leading, spacing: Socle.M.space2) {
                Menu(L("import.menu")) {
                    Button(L("import.quicklinks"), action: importAction)
                    Button(L("import.csv"), action: importCSVAction)
                }
                .menuStyle(.button)
                .buttonStyle(SocleButtonStyle(.secondary))
                .fixedSize()
                Toggle(L("settings.login"), isOn: Binding(get: { startAtLogin }, set: setLogin))
                    .toggleStyle(.checkbox)
                    .socle(Socle.T.body)
                Toggle(L("settings.autoupdate"), isOn: $autoUpdate)
                    .toggleStyle(.checkbox)
                    .socle(Socle.T.body)
            }
            .padding(Socle.M.space3)
        }
        .socleWatermark { LinkMark() }
        .background(Socle.C.surfaceRaised)
    }

    private func reorderable(_ group: LinkGroup) -> some View {
        let groups = store.library.groups
        let index = groups.firstIndex { $0.id == group.id } ?? 0
        let next = groups.indices.contains(index + 1) ? groups[index + 1].id : nil
        return ReorderRow(token: "group:\(group.id.uuidString)", showsLine: { Drops.dragged?.hasPrefix("group:") == true }) { providers, below in
            Drops.handle(providers, store: store, target: .init(
                group: group.id, reordersGroups: true, groupBefore: below ? next : group.id))
        } content: {
            row(group, index: index, groups: groups)
        }
    }

    private func row(_ group: LinkGroup, index: Int, groups: [LinkGroup]) -> some View {
        let selected = group.id == selectedGroup
        return HStack(spacing: Socle.M.space2) {
            if renaming == group.id {
                RenameField(name: group.name) { name in
                    if !name.isEmpty { store.mutate { $0.groups[$0.groups.firstIndex { $0.id == group.id }!].name = name } }
                    renaming = nil
                }
            } else {
                if let hex = group.color { Circle().fill(Color(hex: hex)).frame(width: 8, height: 8) }
                Text(group.name).socle(Socle.T.label).lineLimit(1)
                    .foregroundStyle(selected ? Socle.C.textStrong : Socle.C.text)
                Spacer(minLength: Socle.M.space2)
                if selected || hoveredGroup == group.id {
                    OrderButtons(canGoUp: index > 0, canGoDown: index < groups.count - 1) { offset in
                        store.mutate { $0.moveGroup(group.id, by: offset) }
                    }
                }
                Text("\(group.links.count)").socle(Socle.T.monoSm).foregroundStyle(Socle.C.textSubtle)
            }
        }
        .padding(.horizontal, Socle.M.space2)
        .frame(minHeight: Socle.M.sizeControl)
        .background(selected ? Socle.C.surfaceSelected : hoveredGroup == group.id ? Socle.C.surfaceHover : .clear,
                    in: RoundedRectangle(cornerRadius: Socle.M.radius))
        .contentShape(Rectangle())
        .onHover { hoveredGroup = $0 ? group.id : nil }
        .onTapGesture(count: 2) { renaming = group.id }
        .onTapGesture { selectedGroup = group.id }
        .contextMenu {
            Button(L("order.up")) { store.mutate { $0.moveGroup(group.id, by: -1) } }.disabled(index == 0)
            Button(L("order.down")) { store.mutate { $0.moveGroup(group.id, by: 1) } }.disabled(index == groups.count - 1)
            Button(L("common.rename")) { renaming = group.id }
            Button(L("common.delete"), role: .destructive) {
                if group.links.isEmpty {
                    store.mutate { $0.groups.removeAll { $0.id == group.id } }
                } else {
                    groupToDelete = group
                }
            }
        }
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        startAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct RenameField: View {
    @State var name: String
    let commit: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $name)
            .textFieldStyle(.plain)
            .socle(Socle.T.label)
            .foregroundStyle(Socle.C.textStrong)
            .focused($focused)
            .onAppear { focused = true }
            .onSubmit { commit(name) }
            .onChange(of: focused) { _, now in if !now { commit(name) } }
    }
}

// MARK: - Lignes et détail

private struct LinkRow: View {
    @EnvironmentObject private var store: LinkStore
    let link: LinkItem
    let selected: Bool
    let canGoUp: Bool
    let canGoDown: Bool
    @State private var hovered = false

    var body: some View {
        let missing = store.missing.contains(link.target)
        HStack(spacing: Socle.M.space2) {
            LinkIcon(link: link).frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(link.name).socle(Socle.T.label).lineLimit(1)
                    .foregroundStyle(selected ? Socle.C.textStrong : Socle.C.text)
                Text(link.target).socle(Socle.T.monoSm).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(Socle.C.textSubtle)
            }
            Spacer(minLength: Socle.M.space3)
            if selected || hovered {
                OrderButtons(canGoUp: canGoUp, canGoDown: canGoDown) { offset in
                    store.mutate { $0.moveLink(link.id, by: offset) }
                }
            }
            if missing {
                Text(L("status.missing")).socle(Socle.T.meta).foregroundStyle(Socle.C.warning)
            }
            if !link.visible {
                Text(L("status.hidden")).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted)
            }
            if let hotkey = link.hotkey {
                SocleChip(text: KeyName.label(hotkey))
            }
        }
        .padding(.horizontal, Socle.M.space2).padding(.vertical, Socle.M.space1_5)
        .background(selected ? Socle.C.surfaceSelected : hovered ? Socle.C.surfaceHover : .clear,
                    in: RoundedRectangle(cornerRadius: Socle.M.radius))
        .onHover { hovered = $0 }
    }
}

private struct LinkIcon: View {
    @EnvironmentObject private var store: LinkStore
    let link: LinkItem

    var body: some View {
        if link.isWeb {
            Image(systemName: "globe").foregroundStyle(Socle.C.textMuted)
        } else if store.missing.contains(link.target) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Socle.C.warning)
        } else if let icon = store.icons[link.target] {
            Image(nsImage: icon).resizable()
        } else {
            Color.clear
        }
    }
}

private struct LinkDetail: View {
    @EnvironmentObject private var store: LinkStore
    let link: LinkItem
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space4) {
                field(L("detail.name")) {
                    TextField("", text: Binding(
                        get: { link.name },
                        set: { name in store.mutate { $0.update(link.id) { $0.name = name } } }))
                        .socleField()
                }
                field(link.isWeb ? L("detail.address") : L("detail.target")) {
                    Text(link.target).socle(Socle.T.mono).foregroundStyle(Socle.C.accentText)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if store.missing.contains(link.target) {
                        Text(L("detail.missing")).socle(Socle.T.meta).foregroundStyle(Socle.C.warning)
                    }
                    if !link.isWeb {
                        Button(L("detail.choose"), action: chooseTarget).buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                    }
                }
                field(L("detail.shortcut")) {
                    ShortcutRecorder(link: link)
                }
                Toggle(L("detail.visible"), isOn: Binding(
                    get: { link.visible },
                    set: { value in store.mutate { $0.update(link.id) { $0.visible = value } } }))
                    .toggleStyle(.checkbox)
                    .socle(Socle.T.body)
                HStack(spacing: Socle.M.space2) {
                    Button(L("detail.open")) { Opener.open(link) }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                    if !link.isWeb {
                        Button(L("detail.reveal")) { Opener.reveal(link) }.buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                    }
                }
                Button(L("detail.delete"), action: onDelete).buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
            }
            .padding(Socle.M.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Socle.C.surface)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Socle.M.space1_5) {
            Text(title).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
            content()
        }
    }

    private func chooseTarget() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        store.mutate { $0.update(link.id) { $0.target = path } }
    }
}

private struct NoticeBar: View {
    let notice: Notice
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Socle.M.space2) {
            Image(systemName: notice.isError ? "exclamationmark.triangle" : "checkmark")
                .foregroundStyle(notice.isError ? Socle.C.danger : Socle.C.success)
                .frame(width: 16, height: 16)
            Text(notice.text).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Socle.M.space2)
            Button(action: close) { Image(systemName: "xmark").frame(width: 16, height: 16) }
                .buttonStyle(.plain)
        }
        .padding(Socle.M.space3)
        .background(Socle.C.surfaceRaised, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        .padding([.horizontal, .top], Socle.M.space3)
    }
}

/// Couleur du groupe dans le menu de la barre des menus : une pastille qui ouvre la palette.
private struct GroupColorButton: View {
    @EnvironmentObject private var store: LinkStore
    let group: LinkGroup
    @State private var open = false

    private func set(_ hex: String?) {
        store.mutate { library in
            if let i = library.groups.firstIndex(where: { $0.id == group.id }) { library.groups[i].color = hex }
        }
        open = false
    }

    var body: some View {
        Button { open.toggle() } label: {
            ZStack {
                if let hex = group.color {
                    Circle().fill(Color(hex: hex))
                } else {
                    Circle().stroke(Socle.C.borderControl, lineWidth: 1.5)
                }
            }
            .frame(width: 14, height: 14)
            .padding(Socle.M.space1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L("group.color"))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: Socle.M.space2) {
                Text(L("group.color")).socle(Socle.T.label).foregroundStyle(Socle.C.textStrong)
                HStack(spacing: Socle.M.space2) {
                    ForEach(GroupColor.palette, id: \.self) { hex in
                        Button { set(hex) } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Socle.C.textStrong, lineWidth: group.color?.uppercased() == hex ? 2 : 0).padding(-3))
                                .padding(3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button(L("group.color.none")) { set(nil) }
                    .buttonStyle(SocleButtonStyle(.secondary, height: 26)).fixedSize().disabled(group.color == nil)
            }
            .padding(Socle.M.space3)
            .background(Socle.C.surface)
        }
    }
}
