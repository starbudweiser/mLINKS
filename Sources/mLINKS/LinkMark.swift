import SwiftUI

/// Les deux maillons entrelacés de l'icône, d'une seule teinte : même géométrie que `scripts/make_icon.swift`.
struct LinkMark: View {
    var body: some View {
        Canvas { context, size in
            let thickness: CGFloat = 74
            let gap: CGFloat = 118
            let offset: CGFloat = 132
            func link(_ x: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x - 195, y: -105, width: 390, height: 210), cornerRadius: 105)
            }
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: size.width / 715, y: size.width / 715)
            context.rotate(by: .degrees(-45))

            context.stroke(link(offset), with: .foreground, lineWidth: thickness)
            var cut = context
            cut.blendMode = .destinationOut
            cut.stroke(link(-offset), with: .color(.black), lineWidth: gap)
            context.stroke(link(-offset), with: .foreground, lineWidth: thickness)

            // Le second maillon repasse devant sur un seul des deux croisements : c'est l'entrelacs.
            var front = context
            front.clip(to: Path(CGRect(x: -600, y: 0, width: 1200, height: 600)))
            var frontCut = front
            frontCut.blendMode = .destinationOut
            frontCut.stroke(link(offset), with: .color(.black), lineWidth: gap)
            front.stroke(link(offset), with: .foreground, lineWidth: thickness)
        }
    }
}
