#!/usr/bin/env swift
// Renders the app icons for iOS (1024, plus dark and tinted variants) and
// macOS (all sizes, Big Sur squircle with shadow) from code.
//
//     swift Tools/make-icons.swift
import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iosSet = root.appendingPathComponent("Apps/iOS/Assets.xcassets/AppIcon.appiconset")
let macSet = root.appendingPathComponent("Apps/Helper/Assets.xcassets/AppIcon.appiconset")

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

enum Variant { case standard, tinted }

/// Draws the artwork into `rect` (a square). `squircle` clips to the macOS shape.
func drawArt(_ ctx: CGContext, rect: CGRect, variant: Variant, squircle: Bool) {
    let s = rect.width / 1024
    ctx.saveGState()
    if squircle {
        let path = CGPath(roundedRect: rect, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)
        ctx.addPath(path)
        ctx.clip()
    }
    // Background.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let top: CGColor = variant == .tinted ? rgb(0x2A2A2A) : rgb(0x1D2844)
    let bottom: CGColor = variant == .tinted ? rgb(0x000000) : rgb(0x0A0A0F)
    let background = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    if variant == .standard {
        let glow = CGGradient(colorsSpace: space, colors: [rgb(0x2E86AB, 0.35), rgb(0x2E86AB, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: rect.minX + 250 * s, y: rect.maxY - 230 * s), startRadius: 0, endCenter: CGPoint(x: rect.minX + 250 * s, y: rect.maxY - 230 * s), endRadius: 620 * s, options: [])
    }

    // 2 × 2 tiles.
    let inset: CGFloat = 196 * s
    let gap: CGFloat = 48 * s
    let area = rect.insetBy(dx: inset, dy: inset)
    let tile = (area.width - gap) / 2
    let radius: CGFloat = 64 * s
    func tileRect(_ col: Int, _ row: Int) -> CGRect {
        // row 0 = top
        CGRect(x: area.minX + CGFloat(col) * (tile + gap), y: area.maxY - CGFloat(row + 1) * tile - CGFloat(row) * gap, width: tile, height: tile)
    }
    let accent: CGColor = variant == .tinted ? rgb(0xFFFFFF) : rgb(0x2E86AB)
    let accentTop: CGColor = variant == .tinted ? rgb(0xDDDDDD) : rgb(0x3FA3CC)
    let navy: CGColor = variant == .tinted ? rgb(0x3A3A3A) : rgb(0x16213E)
    let navyTop: CGColor = variant == .tinted ? rgb(0x4A4A4A) : rgb(0x223058)
    let border: CGColor = variant == .tinted ? rgb(0xFFFFFF, 0.25) : rgb(0x2E86AB, 0.45)
    let green: CGColor = variant == .tinted ? rgb(0xFFFFFF) : rgb(0x2ECC71)
    let orange: CGColor = variant == .tinted ? rgb(0xFFFFFF) : rgb(0xF18F01)
    let white: CGColor = variant == .tinted ? rgb(0x000000) : rgb(0xFFFFFF)

    func fillTile(_ r: CGRect, _ colors: [CGColor]) {
        let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: r.midX, y: r.maxY), end: CGPoint(x: r.midX, y: r.minY), options: [])
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(border)
        ctx.setLineWidth(5 * s)
        ctx.strokePath()
    }

    // Top-left: accent tile with a rising line.
    let a = tileRect(0, 0)
    fillTile(a, [accentTop, accent])
    let points: [CGFloat] = [0.18, 0.34, 0.28, 0.52, 0.44, 0.7, 0.62, 0.84]
    ctx.setStrokeColor(white)
    ctx.setLineWidth(26 * s)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.beginPath()
    for (index, value) in points.enumerated() {
        let x = a.minX + a.width * (0.16 + 0.68 * CGFloat(index) / CGFloat(points.count - 1))
        let y = a.minY + a.height * (0.12 + 0.76 * value)
        index == 0 ? ctx.move(to: CGPoint(x: x, y: y)) : ctx.addLine(to: CGPoint(x: x, y: y))
    }
    ctx.strokePath()

    // Top-right: recovery ring.
    let b = tileRect(1, 0)
    fillTile(b, [navyTop, navy])
    let center = CGPoint(x: b.midX, y: b.midY)
    let ringRadius = b.width * 0.3
    ctx.setLineWidth(34 * s)
    ctx.setStrokeColor(variant == .tinted ? rgb(0xFFFFFF, 0.2) : rgb(0x2ECC71, 0.18))
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()
    ctx.setStrokeColor(green)
    ctx.addArc(center: center, radius: ringRadius, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 2 * 0.78, clockwise: true)
    ctx.strokePath()

    // Bottom-left: pause.
    let c = tileRect(0, 1)
    fillTile(c, [navyTop, navy])
    ctx.setFillColor(orange)
    let barWidth = c.width * 0.12
    let barHeight = c.height * 0.42
    for offset in [-0.11, 0.11] {
        let bar = CGRect(x: c.midX + c.width * CGFloat(offset) - barWidth / 2, y: c.midY - barHeight / 2, width: barWidth, height: barHeight)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.fillPath()
    }

    // Bottom-right: bars.
    let d = tileRect(1, 1)
    fillTile(d, [navyTop, navy])
    ctx.setFillColor(accent)
    let heights: [CGFloat] = [0.3, 0.55, 0.42]
    let w = d.width * 0.12
    for (index, h) in heights.enumerated() {
        let x = d.midX + (CGFloat(index) - 1) * d.width * 0.2 - w / 2
        let bar = CGRect(x: x, y: d.minY + d.height * 0.24, width: w, height: d.height * h)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: w / 2, cornerHeight: w / 2, transform: nil))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

func render(size: Int, variant: Variant, mac: Bool) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = context.cgContext
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.clear(full)
    if mac {
        // Big Sur grid: 824 pt body, centred, soft shadow.
        let body = full.insetBy(dx: CGFloat(size) * 100 / 1024, dy: CGFloat(size) * 100 / 1024).offsetBy(dx: 0, dy: CGFloat(size) * 12 / 1024)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -CGFloat(size) * 10 / 1024), blur: CGFloat(size) * 28 / 1024, color: rgb(0x000000, 0.45))
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: body.width * 0.2245, cornerHeight: body.width * 0.2245, transform: nil))
        ctx.setFillColor(rgb(0x0A0A0F))
        ctx.fillPath()
        ctx.restoreGState()
        drawArt(ctx, rect: body, variant: variant, squircle: true)
    } else {
        drawArt(ctx, rect: full, variant: variant, squircle: false)
    }
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: iosSet, withIntermediateDirectories: true)
try render(size: 1024, variant: .standard, mac: false).write(to: iosSet.appendingPathComponent("AppIcon.png"))
try render(size: 1024, variant: .standard, mac: false).write(to: iosSet.appendingPathComponent("AppIcon-Dark.png"))
try render(size: 1024, variant: .tinted, mac: false).write(to: iosSet.appendingPathComponent("AppIcon-Tinted.png"))
let iosContents = """
{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "AppIcon-Dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "AppIcon-Tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try iosContents.write(to: iosSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

try FileManager.default.createDirectory(at: macSet, withIntermediateDirectories: true)
var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(size: pixels, variant: .standard, mac: true).write(to: macSet.appendingPathComponent(name))
        entries.append(#"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)" }"#)
    }
}
let macContents = "{\n  \"images\" : [\n" + entries.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try macContents.write(to: macSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// A preview for the README.
try render(size: 512, variant: .standard, mac: true).write(to: root.appendingPathComponent("docs/icon.png"))
print("Icons written.")
