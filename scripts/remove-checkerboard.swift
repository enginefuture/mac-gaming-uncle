#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: remove-checkerboard.swift <input.png> <output.png>\n".utf8))
    exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSImage(contentsOf: input),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("unable to decode input image\n".utf8))
    exit(1)
}

let width = source.width
let height = source.height
let bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: &pixels, width: width, height: height,
    bitsPerComponent: 8, bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }
context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

func isBackground(_ index: Int) -> Bool {
    let red = Int(pixels[index])
    let green = Int(pixels[index + 1])
    let blue = Int(pixels[index + 2])
    let high = max(red, green, blue)
    let low = min(red, green, blue)
    return low >= 184 && high - low <= 20
}

var visited = [Bool](repeating: false, count: width * height)
var queue: [Int] = []
queue.reserveCapacity(width * height / 2)
for x in 0..<width { queue.append(x); queue.append((height - 1) * width + x) }
for y in 1..<(height - 1) { queue.append(y * width); queue.append(y * width + width - 1) }

var head = 0
while head < queue.count {
    let point = queue[head]
    head += 1
    guard !visited[point] else { continue }
    visited[point] = true
    let byte = point * 4
    guard isBackground(byte) else { continue }
    pixels[byte] = 0
    pixels[byte + 1] = 0
    pixels[byte + 2] = 0
    pixels[byte + 3] = 0
    let x = point % width
    let y = point / width
    if x > 0 { queue.append(point - 1) }
    if x + 1 < width { queue.append(point + 1) }
    if y > 0 { queue.append(point - width) }
    if y + 1 < height { queue.append(point + width) }
}

guard let rendered = context.makeImage(),
      let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
    exit(1)
}
try data.write(to: output, options: .atomic)
