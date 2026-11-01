// Dessine l'icône de mLINKS : deux maillons entrelacés sur fond sombre, à plat (Socle).
// Usage : swift scripts/make_icon.swift <sortie.png>
import AppKit

let size: CGFloat = 1024
let color = NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1)
let background = NSColor(white: 0.118, alpha: 1)
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.current = context
let cg = context.cgContext

// Gabarit macOS : carré arrondi de 824 px centré.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
cg.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
cg.setFillColor(background.cgColor)
cg.fillPath()

cg.translateBy(x: size / 2, y: size / 2)
cg.rotate(by: .pi / 4)
let thickness: CGFloat = 74
let link = CGSize(width: 390, height: 210)
let offset: CGFloat = 132

func maillon(_ x: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x - link.width / 2, y: -link.height / 2, width: link.width, height: link.height),
           cornerWidth: link.height / 2, cornerHeight: link.height / 2, transform: nil)
}

func trait(_ path: CGPath, _ couleur: NSColor, épaisseur: CGFloat) {
    cg.setStrokeColor(couleur.cgColor)
    cg.setLineWidth(épaisseur)
    cg.addPath(path)
    cg.strokePath()
}

// Le maillon bleu passe devant sur le croisement du haut, le blanc sur celui du bas.
// Les deux extrémités ne se touchent pas en y = 0 : le découpage ne laisse aucune couture.
let halo = thickness + 44
trait(maillon(offset), .white, épaisseur: thickness)
trait(maillon(-offset), background, épaisseur: halo)
trait(maillon(-offset), color, épaisseur: thickness)
cg.saveGState()
cg.clip(to: CGRect(x: -600, y: -600, width: 1200, height: 600))
trait(maillon(offset), background, épaisseur: halo)
trait(maillon(offset), .white, épaisseur: thickness)
cg.restoreGState()

NSGraphicsContext.current = nil
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
