#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: build-icon.swift <source.png> <output.png>\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSImage(contentsOf: input),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("unable to decode source image\n".utf8))
    exit(1)
}

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("unable to create image context\n".utf8))
    exit(1)
}

context.clear(CGRect(x: 0, y: 0, width: size, height: size))
let iconBounds = CGRect(x: 8, y: 8, width: 1008, height: 1008)
context.addPath(CGPath(roundedRect: iconBounds, cornerWidth: 205, cornerHeight: 205, transform: nil))
context.clip()
context.interpolationQuality = .high
context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))

guard let rendered = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("unable to encode output image\n".utf8))
    exit(1)
}
try png.write(to: output, options: .atomic)
