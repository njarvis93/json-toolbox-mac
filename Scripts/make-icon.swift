#!/usr/bin/env swift
import AppKit

// Rellena el catálogo de iconos del proyecto de Xcode. El icono se dibuja aquí en vez de
// guardar solo los PNG en el repositorio: así se puede cambiar un color sin abrir un editor
// de imágenes, y se ve de dónde salen las medidas.
//
//   swift Scripts/make-icon.swift

let side: CGFloat = 1024
let margin: CGFloat = 100                    // los iconos de macOS no llegan al borde
let corner: CGFloat = 185                    // esquina de Big Sur en adelante

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Mapa de bits de 1024x1024 **píxeles** explícitos. Con `NSImage.lockFocus()` el lienzo sale a
// la escala de la pantalla: en una Retina daba 2048 px y Xcode avisaba de que el icono de
// 512@2x medía el doble de lo que debe.
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side),
                                    pixelsHigh: Int(side), bitsPerSample: 8, samplesPerPixel: 4,
                                    hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let ctx = context.cgContext

let body = NSRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2)
let shape = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)

// Fondo: el mismo gris azulado del editor en oscuro, hacia un azul más vivo abajo.
ctx.saveGState()
shape.addClip()
let gradient = NSGradient(colors: [color(0x2C3E56), color(0x16202E)])!
gradient.draw(in: body, angle: -90)
ctx.restoreGState()

// Filo superior, que es lo que hace que un icono plano parezca de macOS.
ctx.saveGState()
shape.addClip()
color(0xFFFFFF, 0.16).setStroke()
let edge = NSBezierPath(roundedRect: body.insetBy(dx: 3, dy: 3), xRadius: corner, yRadius: corner)
edge.lineWidth = 6
edge.stroke()
ctx.restoreGState()

// Las llaves, que es lo que se reconoce a 32 px.
let braces = "{ }" as NSString
let font = NSFont.monospacedSystemFont(ofSize: 470, weight: .medium)
let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(0xE8EEF7)]
let size = braces.size(withAttributes: attributes)
braces.draw(at: NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2 - 8),
            withAttributes: attributes)

// Dos barras gruesas dentro de las llaves, con los colores de clave y de cadena del resaltado.
// Pocas y gordas a propósito: con tres finas, a 32 px se fundían en una mancha.
let barWidths: [CGFloat] = [200, 150]
let barColors = [0x7FB6F5, 0xFC6A5D]
let barHeight: CGFloat = 58
let barGap: CGFloat = 86
let left = (side - barWidths[0]) / 2
for (index, hex) in barColors.enumerated() {
    let y = side / 2 + barGap / 2 - CGFloat(index) * barGap - barHeight / 2
    let bar = NSRect(x: left, y: y, width: barWidths[index], height: barHeight)
    color(hex).setFill()
    NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
}

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "JsonTooling.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let master = iconset + "/icon_512x512@2x.png"
try! png.write(to: URL(fileURLWithPath: master))

// El resto de tamaños salen del maestro con sips, que remuestrea mejor que redibujar a pelo.
for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                       ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                       ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512)] {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = ["-Z", "\(pixels)", master, "--out", "\(iconset)/\(name).png"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try! task.run()
    task.waitUntilExit()
}

// El proyecto de Xcode no usa el .icns, sino un catálogo de assets con los PNG sueltos.
// Se rellena desde el mismo iconset para que no haya dos iconos que puedan divergir.
let appIcon = "JsonToolingApp/JsonToolingApp/Assets.xcassets/AppIcon.appiconset"
guard fm.fileExists(atPath: appIcon) else {
    print("no encuentro \(appIcon)"); exit(1)
}
do {
    for file in (try? fm.contentsOfDirectory(atPath: appIcon)) ?? [] where file.hasSuffix(".png") {
        try? fm.removeItem(atPath: appIcon + "/" + file)
    }
    var entries: [String] = []
    for (name, _) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                      ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                      ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512),
                      ("icon_512x512@2x", 1024)] {
        try? fm.copyItem(atPath: "\(iconset)/\(name).png", toPath: "\(appIcon)/\(name).png")
        let parts = name.replacingOccurrences(of: "icon_", with: "").components(separatedBy: "@")
        let size = parts[0].components(separatedBy: "x")[0]
        let scale = parts.count > 1 ? "2" : "1"
        entries.append("""
            {
              "filename" : "\(name).png",
              "idiom" : "mac",
              "scale" : "\(scale)x",
              "size" : "\(size)x\(size)"
            }
        """)
    }
    let contents = """
    {
      "images" : [
    \(entries.joined(separator: ",\n"))
      ],
      "info" : { "author" : "make-icon.swift", "version" : 1 }
    }
    """
    try! contents.write(toFile: appIcon + "/Contents.json", atomically: true, encoding: .utf8)
    print(appIcon)
}

try? fm.removeItem(atPath: iconset)
