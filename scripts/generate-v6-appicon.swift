#!/usr/bin/env swift
// Renders the canonical Poke Island app icon source bitmap.
//
// Produces a single 1024×1024 PNG at Assets/Brand/app-icon-v6.png. That
// image is the sole "master" — the Python pipeline
// (scripts/generate_brand_icons.py) resizes it into every
// AppIcon.appiconset slot and then composes OpenIsland.icns. Re-run this
// script after any design tweak, then run the Python pipeline.
//
// Spec:
// - Paper tone: background #f1ead9
// - Outer squircle: corner radius = size * 0.225 (full-bleed, no shadow
//   baked in — macOS supplies its own drop shadow)
// - Pixel monster ball mark, scaled to 72% of outer width
// - 1px ink ring at rgba(0,0,0,0.06) for edge crispness

import AppKit
import CoreGraphics
import Foundation

let outputPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Assets/Brand/app-icon-v6.png")
let ballPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Sources/OpenIslandApp/Resources/BootDance/pixel-monster-ball.png")

let paper = CGColor(red: 0xf1/255.0, green: 0xea/255.0, blue: 0xd9/255.0, alpha: 1)
let ring  = CGColor(red: 0, green: 0, blue: 0, alpha: 0.06)

func render(px: Int) -> Data {
    let size = CGFloat(px)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: px,
        height: px,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("CGContext failed") }

    // Transparent canvas.
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

    // Full-bleed squircle. The Python pipeline insets this to the macOS
    // icon content grid (824/1024), so no extra padding is baked in here.
    let radius = size * 0.225
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.setFillColor(paper)
    ctx.addPath(squircle)
    ctx.fillPath()

    // 1px inset ring for edge definition at small sizes.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(ring)
    ctx.setLineWidth(size / 1024.0)
    ctx.strokePath()
    ctx.restoreGState()

    // Clip to squircle so the mark corners can't bleed.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    guard let ball = NSImage(contentsOf: ballPath),
          let ballCG = ball.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("missing pixel monster ball at \(ballPath.path)")
    }

    let markSize = rect.width * 0.72
    let markRect = CGRect(
        x: rect.midX - markSize / 2,
        y: rect.midY - markSize / 2,
        width: markSize,
        height: markSize
    )
    ctx.interpolationQuality = .none
    ctx.draw(ballCG, in: markRect)

    ctx.restoreGState()

    guard let cgImage = ctx.makeImage() else { fatalError("makeImage failed") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    return data
}

let data = render(px: 1024)
try? data.write(to: outputPath)
print("wrote \(outputPath.path) (1024×1024)")
