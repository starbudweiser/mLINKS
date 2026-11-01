import SwiftUI
import UniformTypeIdentifiers

/// Ligne qu'on déplace à la souris. Pendant le survol, un filet `accent` montre où elle va s'insérer ;
/// quand `showsLine` répond non (un lien au-dessus d'un groupe, par exemple), c'est toute la ligne qui s'entoure.
struct ReorderRow<Content: View>: View {
    let token: String
    var showsLine: () -> Bool = { true }
    /// Reçoit les éléments déposés et dit si le dépôt vise le bas de la ligne.
    let drop: ([NSItemProvider], Bool) -> Bool
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0
    @State private var target: Edge?

    var body: some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .onDrag {
                Drops.dragged = token
                return NSItemProvider(object: token as NSString)
            }
            .onDrop(of: [.fileURL, .plainText], delegate: Delegate(height: height, target: $target, drop: drop))
            .overlay(alignment: target == .bottom ? .bottom : .top) {
                if target != nil {
                    if showsLine() {
                        Rectangle().fill(Socle.C.accent).frame(height: 2)
                    } else {
                        RoundedRectangle(cornerRadius: Socle.M.radius).stroke(Socle.C.accent, lineWidth: 1)
                    }
                }
            }
    }

    private struct Delegate: DropDelegate {
        let height: CGFloat
        @Binding var target: Edge?
        let drop: ([NSItemProvider], Bool) -> Bool

        private func edge(_ info: DropInfo) -> Edge { info.location.y > height / 2 ? .bottom : .top }

        func dropEntered(info: DropInfo) { target = edge(info) }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            target = edge(info)
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) { target = nil }

        func performDrop(info: DropInfo) -> Bool {
            let below = edge(info) == .bottom
            target = nil
            return drop(info.itemProviders(for: [.fileURL, .plainText]), below)
        }
    }
}

/// Flèches « monter » et « descendre » d'une ligne ; désactivées en bout de liste.
struct OrderButtons: View {
    let canGoUp: Bool
    let canGoDown: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("chevron.up", L("order.up"), enabled: canGoUp) { move(-1) }
            button("chevron.down", L("order.down"), enabled: canGoDown) { move(1) }
        }
    }

    private func button(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Socle.C.textMuted)
        .disabled(!enabled)
        .opacity(enabled ? 1 : Socle.M.opacityDisabled)
        .help(label)
        .accessibilityLabel(label)
    }
}
