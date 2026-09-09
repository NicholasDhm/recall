// Renders the 1024x1024 app icon into the asset catalog.
// Run from the repository root: swift Scripts/make-icon.swift

import AppKit
import CoreGraphics
import Foundation

let side = 1024
let output = URL(fileURLWithPath: "Recall/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

guard let context = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("could not create bitmap context")
}

let size = CGFloat(side)
let bounds = CGRect(x: 0, y: 0, width: size, height: size)

let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(red: 0.086, green: 0.078, blue: 0.071, alpha: 1),
        CGColor(red: 0.161, green: 0.145, blue: 0.133, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

// Symmetric waveform: bar heights mirror around the centre bar.
let heights: [CGFloat] = [0.18, 0.34, 0.56, 0.86, 1.0, 0.86, 0.56, 0.34, 0.18]
let barWidth = size * 0.052
let gap = size * 0.038
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
let maxHeight = size * 0.46
var x = (size - totalWidth) / 2

context.setFillColor(CGColor(red: 0.859, green: 0.427, blue: 0.220, alpha: 1))
for height in heights {
    let barHeight = maxHeight * height
    let rect = CGRect(x: x, y: (size - barHeight) / 2, width: barWidth, height: barHeight)
    let path = CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
    context.addPath(path)
    context.fillPath()
    x += barWidth + gap
}

guard let image = context.makeImage() else { fatalError("could not render image") }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
try data.write(to: output)
print("wrote \(output.path) (\(side)x\(side), \(data.count) bytes)")
